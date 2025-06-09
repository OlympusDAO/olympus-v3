// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositTokenManager} from "src/policies/interfaces/IConvertibleDepositTokenManager.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

import {AssetManager} from "src/policies/utils/AssetManager.sol";

/// @title Convertible Deposit Token Manager
/// @notice This policy is used to manage convertible deposit ("CD") tokens on behalf of deposit facilities. It is meant to be used by the facilities, and is not an end-user policy.
contract CDTokenManager is Policy, PolicyEnabler, IConvertibleDepositTokenManager, AssetManager {
    using SafeTransferLib for ERC20;

    // ========== CONSTANTS ========== //

    /// @notice The role that is allowed to deposit and withdraw funds
    bytes32 public constant ROLE_DEPOSITOR = "cd_token_manager";

    // Tasks
    // [ ] Rename to DepositManager
    // [X] Idle/vault strategy for deposited tokens
    // [ ] ERC6909 migration
    // [ ] Rename to receipt tokens
    // [X] CDTokenSupply to depositor supply

    // ========== STATE VARIABLES ========== //

    /// @notice The CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice Maps depositors and CD tokens to the number of CD tokens they have minted
    /// @dev    This is used to ensure that the CD token is redeemable/solvent
    mapping(address => mapping(IConvertibleDepositERC20 => uint256)) internal _cdTokenSupply;

    /// @notice Maps assets and depositors to the number of receipt tokens that have been minted
    /// @dev    This is used to ensure that the receipt tokens are solvent
    mapping(address => mapping(address => uint256)) internal _receiptTokenSupply;

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Disabled by default by PolicyEnabler
    }

    // ========== Policy Configuration ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdepoKeycode = toKeycode("CDEPO");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(cdepoKeycode, CDEPO.create.selector);
        permissions[1] = Permissions(cdepoKeycode, CDEPO.setReclaimRate.selector);
        permissions[2] = Permissions(cdepoKeycode, CDEPO.mintFor.selector);
        permissions[3] = Permissions(cdepoKeycode, CDEPO.burnFrom.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositTokenManager
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Deposit into vault
        uint256 shares = _depositAsset(address(cdToken_.asset()), msg.sender, amount_);

        // Update the asset tracking
        _receiptTokenSupply[address(cdToken_.asset())][msg.sender] += amount_;

        // Mint the CD token to the caller
        // This will also validate that the CD token is supported
        CDEPO.mintFor(cdToken_, msg.sender, amount_);

        // Emit an event
        emit Mint(msg.sender, address(cdToken_), amount_, shares);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    /// @dev        Care must be taken to ensure that
    function withdraw(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Withdraw the funds from the vault
        address asset = address(cdToken_.asset());
        uint256 shares = _withdrawAsset(asset, msg.sender, amount_);

        // The CD token supply is not adjusted here, as there is no minting/burning of CD tokens

        // Post-withdrawal, there should be at least as many underlying asset tokens as there are CD tokens, otherwise the CD token is not redeemable
        if (_receiptTokenSupply[asset][msg.sender] > getDepositedAssets(asset, msg.sender)) {
            revert ConvertibleDepositTokenManager_Insolvent(
                address(cdToken_),
                _receiptTokenSupply[asset][msg.sender],
                getDepositedAssets(asset, msg.sender)
            );
        }

        // Emit an event
        emit Withdraw(msg.sender, address(cdToken_), amount_, shares);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function burn(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external onlyRole(ROLE_DEPOSITOR) returns (uint256 shares) {
        // Burn the CD token from the caller
        CDEPO.burnFrom(cdToken_, msg.sender, amount_);

        // Withdraw the funds from the vault
        shares = _withdrawAsset(address(cdToken_.asset()), msg.sender, amount_);

        // Update the asset tracking
        _receiptTokenSupply[address(cdToken_.asset())][msg.sender] -= amount_;

        // Emit an event
        emit Burn(msg.sender, address(cdToken_), amount_, shares);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositTokenManager
    function createToken(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        cdToken = CDEPO.create(vault_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function setTokenReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole {
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getTokenReclaimRate(
        IConvertibleDepositERC20 cdToken_
    ) external view returns (uint16 reclaimRate) {
        reclaimRate = CDEPO.reclaimRate(address(cdToken_));
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getDepositTokens()
        external
        view
        returns (IConvertibleDepository.DepositToken[] memory depositTokens)
    {
        depositTokens = CDEPO.getDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory convertibleDepositTokens)
    {
        convertibleDepositTokens = CDEPO.getConvertibleDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositTokenManager
    function isConvertibleDepositToken(
        address convertibleDepositToken_
    ) external view returns (bool isConvertible) {
        isConvertible = CDEPO.isConvertibleDepositToken(convertibleDepositToken_);
    }
}
