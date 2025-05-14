// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

// CCIP
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";
import {IPoolV1} from "@chainlink-ccip-1.6.0/ccip/interfaces/IPool.sol";

/// @title  CCIPMintBurnTokenPool
/// @notice Bophades policy to handling minting and burning of OHM using Chainlink CCIP
/// @dev    This is a modified version of the `BurnMintTokenPoolAbstract` contract from Chainlink CCIP
///         As the CCIP contracts have a minimum solidity version of 0.8.24, this policy is also compiled with 0.8.24
contract CCIPMintBurnTokenPool is Policy, PolicyEnabler, TokenPool {
    // Tasks
    // [X] Add PolicyEnabler
    // [X] Add compiler configuration for 0.8.24
    // [X] Import TokenPool abstract
    // [X] Implement minting of OHM
    // [X] Implement burning of OHM
    // [X] Implement support for rate-limiting
    // [X] Implement tracking of bridged supply from mainnet
    // [X] failure handling
    // [X] extract interface

    // =========  ERRORS ========= //

    error TokenPool_MintApprovalOutOfSync(uint256 expected, uint256 actual);

    error TokenPool_InvalidToken(address expected, address actual);

    error TokenPool_InvalidTokenDecimals(uint8 expected, uint8 actual);

    error TokenPool_ZeroAmount();

    error TokenPool_InvalidAddress(string param);

    error TokenPool_ZeroAddress();

    error TokenPool_InvalidRecipient(address recipient);

    error TokenPool_InsufficientBalance(uint256 expected, uint256 actual);

    error TokenPool_BridgedSupplyExceeded(uint256 bridgedSupply, uint256 amount);

    // =========  STATE VARIABLES ========= //

    /// @notice Bophades module for minting and burning OHM
    MINTRv1 public MINTR;

    /// @notice Whether the contract is on mainnet
    // solhint-disable-next-line immutable-vars-naming
    bool public immutable isChainMainnet;

    /// @notice Quantity of OHM bridged
    /// @dev    This will only be set on mainnet
    uint256 internal _bridgedSupply;

    /// @notice Initial bridged supply
    /// @dev    This is used in `configureDependencies` to set the initial value for `bridgedSupply`
    uint256 internal immutable _INITIAL_BRIDGED_SUPPLY;

    /// @notice Whether the bridged supply has been initialized
    bool public isBridgeSupplyInitialized;

    // =========  CONSTRUCTOR ========= //

    constructor(
        address kernel_,
        uint256 initialBridgedSupply_,
        address ohm_,
        address rmnProxy_,
        address ccipRouter_,
        uint256 mainnetChainId_
    ) Policy(Kernel(kernel_)) TokenPool(IERC20(ohm_), 9, new address[](0), rmnProxy_, ccipRouter_) {
        // Check if the contract is on mainnet
        isChainMainnet = block.chainid == mainnetChainId_;

        // Set the initial bridged supply
        _INITIAL_BRIDGED_SUPPLY = initialBridgedSupply_;

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

        // Validate bridged supply
        // This is done in both enable() and configureDependencies()
        // as the contract could be re-installed in the kernel or
        // re-enabled [locally]
        _validateBridgedSupply();
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

    /// @inheritdoc IPoolV1
    /// @dev        This is based on the {BurnMintTokenPoolAbstract.lockOrBurn} function, with customisations for the Olympus protocol stack.
    ///
    ///             This function performs the following:
    ///             - Validates the lockOrBurnIn data
    ///             - On mainnet: increments the bridged supply
    ///             - Burns the OHM
    ///             - Emits the Burned event
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external virtual override onlyEnabled returns (Pool.LockOrBurnOutV1 memory) {
        // CCIP-provided validation:
        // - Supported token
        // - RMN curse status
        // - Allowlist status (unused)
        // - Caller is the OnRamp configured in the Router for the destination chain
        //
        // Also consumes the outbound rate limit for the destination chain
        _validateLockOrBurn(lockOrBurnIn);

        // Validate that the amount is not zero
        if (lockOrBurnIn.amount == 0) revert TokenPool_ZeroAmount();

        // We should ideally check that the destination token pool is on the whitelist, but it is not provided in `Pool.LockOrBurnInV1`

        // Tracking of bridged amounts
        if (isChainMainnet) {
            // If the contract is on mainnet, increment the bridged supply
            // This is used to track the total supply of OHM that has been bridged, and hence the amount that can be minted on mainnet when bridged back
            _bridgedSupply += lockOrBurnIn.amount;

            // In step, adjust the mint approval for the contract, so that it can mint the OHM when bridged back
            // The mint approval should be consistent with the bridgedSupply
            MINTR.increaseMintApproval(address(this), lockOrBurnIn.amount);
        }

        // The Router will have sent the OHM to this contract already

        // Check that there is sufficient balance
        {
            uint256 balance = i_token.balanceOf(address(this));
            if (balance < lockOrBurnIn.amount)
                revert TokenPool_InsufficientBalance(lockOrBurnIn.amount, balance);
        }

        // Burn the OHM
        i_token.approve(address(MINTR), lockOrBurnIn.amount);
        MINTR.burnOhm(address(this), lockOrBurnIn.amount);

        emit Burned(lockOrBurnIn.originalSender, lockOrBurnIn.amount);

        return
            Pool.LockOrBurnOutV1({
                destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
                destPoolData: _encodeLocalDecimals()
            });
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

        // Tracking of bridged amounts
        if (isChainMainnet) {
            // Validate that the amount is not greater than the bridged supply
            if (localAmount > _bridgedSupply)
                revert TokenPool_BridgedSupplyExceeded(_bridgedSupply, localAmount);

            // If the contract is on mainnet, decrement the bridged supply
            // This puts a hard cap on the amount of OHM that can be bridged back to mainnet
            _bridgedSupply -= localAmount;

            // Mint approval would have already been granted in `lockOrBurn` when bridging from mainnet
        } else {
            // If the contract is not on mainnet, increment the mint approval
            // Although this permits infinite minting on the non-mainnet chain, it would not be possible to bridge back to mainnet due to the hard cap set by `bridgedSupply`
            MINTR.increaseMintApproval(address(this), localAmount);
        }

        // Mint to the receiver
        MINTR.mintOhm(releaseOrMintIn.receiver, localAmount);

        // TODO see if we can get the original sender if EVM
        emit Minted(msg.sender, releaseOrMintIn.receiver, localAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
    }

    // ========= ENABLE FUNCTIONS ========= //

    function _enable(bytes calldata) internal override {
        // Validate the bridged supply
        _validateBridgedSupply();

        // If the contract is not on mainnet, nothing more to do
        if (!isChainMainnet) return;

        // If the bridged supply has been initialized, nothing more to do
        // Since the bridged supply and mint approval are in sync
        if (isBridgeSupplyInitialized) return;

        // Otherwise, set the initial bridged supply
        MINTR.increaseMintApproval(address(this), _INITIAL_BRIDGED_SUPPLY);

        // Update the bridged supply
        _bridgedSupply = _INITIAL_BRIDGED_SUPPLY;

        // Mark that the bridged supply has been initialized
        isBridgeSupplyInitialized = true;
    }

    /// @notice Validates that the bridged supply and mint approval are in sync, where appropriate
    function _validateBridgedSupply() internal view {
        // Not needed on non-mainnet chains
        if (!isChainMainnet) return;

        // If the contract has previously been enabled, ensure that the bridged supply and mint approval are in sync
        uint256 mintApproval = MINTR.mintApproval(address(this));
        if (isBridgeSupplyInitialized) {
            if (mintApproval != _bridgedSupply)
                revert TokenPool_MintApprovalOutOfSync(_bridgedSupply, mintApproval);

            return;
        }

        // Otherwise it is the first time, and the mint approval should be zero
        if (mintApproval != 0) revert TokenPool_MintApprovalOutOfSync(0, mintApproval);
    }

    // ========= VIEW FUNCTIONS ========= //

    /// @notice Returns the amount of OHM that has been bridged from mainnet
    /// @dev    This will only return a value on mainnet
    function getBridgedSupply() external view returns (uint256) {
        return _bridgedSupply;
    }

    // TODO override admin functions to allow for RBAC
}
