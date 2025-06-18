// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPTokenPool} from "src/policies/interfaces/ICCIPTokenPool.sol";
import {ITypeAndVersion} from "@chainlink-ccip-1.6.0/shared/interfaces/ITypeAndVersion.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

// CCIP
import {BurnMintTokenPoolBase} from "src/policies/bridge/BurnMintTokenPoolBase.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";

/// @title  CCIPBurnMintTokenPool
/// @notice Bophades policy to handling minting and burning of OHM using Chainlink CCIP on non-canonical chains
/// @dev    As the CCIP contracts have a minimum solidity version of 0.8.24, this policy is also compiled with 0.8.24
///
///         Despite being a policy, the admin functions inherited from `TokenPool` are not virtual and cannot be overriden, and so remain gated to the owner.
contract CCIPBurnMintTokenPool is
    Policy,
    PolicyEnabler,
    BurnMintTokenPoolBase,
    ICCIPTokenPool,
    ITypeAndVersion
{
    // =========  STATE VARIABLES ========= //

    /// @notice Bophades module for minting and burning OHM
    MINTRv1 public MINTR;

    /// @notice Unique identifier for the TokenPool
    /// @dev    This is used to identify the TokenPool to CCIP
    string internal constant _typeAndVersion = "BurnMintTokenPool 1.5.1";

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

    /// @notice Burns the specified amount of OHM
    /// @dev    Implementation of the `_burn` function from the `BurnMintTokenPoolAbstract` contract
    function _burn(uint256 amount_) internal override onlyEnabled {
        // Burn the OHM
        // Will revert if amount is 0 or if there is insufficient balance
        i_token.approve(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);
    }

    /// @notice Mints the specified amount of OHM
    /// @dev    Implementation of the `_mint` function from the `BurnMintTokenPoolBase` contract
    function _mint(address receiver_, uint256 amount_) internal override onlyEnabled {
        // Increment the mint approval
        // Although this permits infinite minting on the non-mainnet chain, it would not be possible to bridge back to mainnet due to checks on that side of the bridge
        MINTR.increaseMintApproval(address(this), amount_);

        // Mint to the receiver
        // Will revert if amount is 0
        MINTR.mintOhm(receiver_, amount_);
    }

    /// @inheritdoc ICCIPTokenPool
    /// @dev        This function is not used in this policy, so it returns 0
    function getBridgedSupply() external pure returns (uint256) {
        return 0;
    }

    // ========= TYPE AND VERSION ========= //

    /// @inheritdoc ITypeAndVersion
    function typeAndVersion() external pure override returns (string memory) {
        return _typeAndVersion;
    }

    // ========= ERC165 ========= //

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(ICCIPTokenPool).interfaceId ||
            interfaceId == type(ITypeAndVersion).interfaceId ||
            interfaceId == type(IPolicyEnabler).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
