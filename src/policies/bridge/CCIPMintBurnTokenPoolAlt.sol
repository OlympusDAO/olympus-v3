// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPMintBurnTokenPool} from "src/policies/interfaces/ICCIPMintBurnTokenPool.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

// CCIP
import {BurnMintTokenPoolAbstract} from "@chainlink-ccip-1.6.0/ccip/pools/BurnMintTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";
import {IPoolV1} from "@chainlink-ccip-1.6.0/ccip/interfaces/IPool.sol";

/// @title  CCIPMintBurnTokenPool
/// @notice Bophades policy to handling minting and burning of OHM using Chainlink CCIP on non-mainnet chains
/// @dev    This is a modified version of the `BurnMintTokenPoolAbstract` contract from Chainlink CCIP
///         As the CCIP contracts have a minimum solidity version of 0.8.24, this policy is also compiled with 0.8.24
///
///         Despite being a policy, the admin functions inherited from `TokenPool` are not virtual and cannot be overriden, and so remain gated to the owner.
contract CCIPMintBurnTokenPool is
    Policy,
    PolicyEnabler,
    BurnMintTokenPoolAbstract,
    ICCIPMintBurnTokenPool
{
    // =========  STATE VARIABLES ========= //

    /// @notice Bophades module for minting and burning OHM
    MINTRv1 public MINTR;

    // =========  CONSTRUCTOR ========= //

    constructor(
        address kernel_,
        address ohm_,
        address rmnProxy_,
        address ccipRouter_
    ) Policy(Kernel(kernel_)) TokenPool(IERC20(ohm_), 9, new address[](0), rmnProxy_, ccipRouter_) {
        // Disabled by default
        // Owner is set to msg.sender
        // The current owner must call `transferOwnership` to transfer ownership to the desired address
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        // Check that OHM is the same as the token passed in to the constructor
        if (address(i_token) != address(MINTR.ohm()))
            revert TokenPool_InvalidToken(address(MINTR.ohm()), address(i_token));

        // No need to check that OHM has 9 decimals, as this is done in the constructor
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        permissions = new Permissions[](3);
        permissions[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
    }

    /// @notice Returns the version of the policy
    ///
    /// @return major The major version of the policy
    /// @return minor The minor version of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= MINT/BURN FUNCTIONS ========= //

    function _burn(uint256 amount_) internal override {
        // Validate that the policy is enabled
        if (!isEnabled) revert NotEnabled();

        // Validate that the amount is not zero
        if (amount_ == 0) revert TokenPool_ZeroAmount();

        // Check that there is sufficient balance
        uint256 balance = i_token.balanceOf(address(this));
        if (balance < amount_) revert TokenPool_InsufficientBalance(amount_, balance);

        // Burn the OHM
        i_token.approve(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);
    }

    /// @inheritdoc IPoolV1
    /// @dev        This is based on the {BurnMintTokenPoolAbstract.releaseOrMint} function, with customisations for the Olympus protocol stack.
    ///
    ///             This function performs the following:
    ///             - Validates the releaseOrMintIn data
    ///             - Calculates the local amount
    ///             - Mints the OHM to the receiver
    ///             - Emits the Minted event
    ///
    ///             In the situation where this function reverts,
    ///             the CCIP infrastructure will not retry, and it
    ///             will be marked as a failure. It will need to be
    ///             manually executed (after resolving the issue that caused the revert).
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) public virtual override onlyEnabled returns (Pool.ReleaseOrMintOutV1 memory) {
        // CCIP-provided validation:
        // - Supported token
        // - RMN curse status
        // - Caller is the OffRamp configured in the Router for the source chain
        // - Source pool is configured on the destination pool
        //
        // Also consumes the inbound rate limit for the source chain
        _validateReleaseOrMint(releaseOrMintIn);

        // Calculate the local amount
        // Not strictly necessary, as we keep OHM to 9 decimals on all chains, but done for consistency
        uint256 localAmount = _calculateLocalAmount(
            releaseOrMintIn.amount,
            _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        );

        // Validate that the amount is not zero
        if (localAmount == 0) revert TokenPool_ZeroAmount();

        // Increment the mint approval
        // Although this permits infinite minting on the non-mainnet chain, it would not be possible to bridge back to mainnet due to the hard cap set by `bridgedSupply`
        MINTR.increaseMintApproval(address(this), localAmount);

        // Mint to the receiver
        MINTR.mintOhm(releaseOrMintIn.receiver, localAmount);

        emit Minted(msg.sender, releaseOrMintIn.receiver, localAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
    }

    function getBridgedSupply() external view returns (uint256) {
        // ignore this, it's just to satisfy the interface
        return 0;
    }
}
