// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositTokenConfig} from "src/policies/interfaces/IConvertibleDepositTokenConfig.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title Convertible Deposit Token Config
/// @notice This policy is used to configure the parameters of a convertible deposit ("CD") token
contract CDTokenConfig is Policy, PolicyEnabler, IConvertibleDepositTokenConfig {
    // ========== STATE VARIABLES ========== //

    /// @notice The CDEPO module
    CDEPOv1 public CDEPO;

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
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
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositTokenConfig
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        cdToken = CDEPO.create(vault_, periodMonths_, reclaimRate_);
    }

    /// @inheritdoc IConvertibleDepositTokenConfig
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole {
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }
}
