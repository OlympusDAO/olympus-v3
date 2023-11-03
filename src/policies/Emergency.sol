// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

// Contract to allow emergency shutdown of minting and treasury withdrawals
contract Emergency is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    event Status(bool treasury_, bool minter_);

    // =========  STATE ========= //

    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        requests = new Permissions[](4);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.deactivate.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.activate.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.deactivate.selector);
        requests[3] = Permissions(MINTR_KEYCODE, MINTR.activate.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice Emergency shutdown of treasury withdrawals and minting
    function shutdown() external onlyRole("emergency_shutdown") {
        TRSRY.deactivate();
        MINTR.deactivate();
        _reportStatus();
    }

    /// @notice Emergency shutdown of treasury withdrawals
    function shutdownWithdrawals() external onlyRole("emergency_shutdown") {
        TRSRY.deactivate();
        _reportStatus();
    }

    /// @notice Emergency shutdown of minting
    function shutdownMinting() external onlyRole("emergency_shutdown") {
        MINTR.deactivate();
        _reportStatus();
    }

    /// @notice Restart treasury withdrawals and minting after shutdown
    function restart() external onlyRole("emergency_restart") {
        TRSRY.activate();
        MINTR.activate();
        _reportStatus();
    }

    /// @notice Restart treasury withdrawals after shutdown
    function restartWithdrawals() external onlyRole("emergency_restart") {
        TRSRY.activate();
        _reportStatus();
    }

    /// @notice Restart minting after shutdown
    function restartMinting() external onlyRole("emergency_restart") {
        MINTR.activate();
        _reportStatus();
    }

    /// @notice Emit an event to show the current status of TRSRY and MINTR
    function _reportStatus() internal {
        emit Status(TRSRY.active(), MINTR.active());
    }
}
