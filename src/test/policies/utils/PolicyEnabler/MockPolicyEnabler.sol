// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice Mock Policy that can be enabled and disabled.
/// @dev    This contract does not implement any custom enable/disable logic.
contract MockPolicyEnabler is Policy, PolicyEnabler {
    uint256 public enableValue;
    uint256 public disableValue;
    uint256 public disableAnotherValue;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function requiresEnabled() external view onlyEnabled returns (bool) {
        return true;
    }

    function requiresDisabled() external view onlyDisabled returns (bool) {
        return true;
    }
}

/// @notice Mock Policy that can be enabled and disabled.
/// @dev    This contract implements custom enable/disable logic.
contract MockPolicyEnablerWithCustomLogic is MockPolicyEnabler {
    // Define a structure for the enable data
    struct EnableData {
        uint256 value;
    }

    struct DisableData {
        uint256 value;
        uint256 anotherValue;
    }

    bool public enableShouldRevert;
    bool public disableShouldRevert;

    constructor(Kernel kernel_) MockPolicyEnabler(kernel_) {}

    function setEnableShouldRevert(bool shouldRevert_) external {
        enableShouldRevert = shouldRevert_;
    }

    function setDisableShouldRevert(bool shouldRevert_) external {
        disableShouldRevert = shouldRevert_;
    }

    function _enable(bytes calldata data_) internal override {
        // Decode the enable data
        EnableData memory enableData = abi.decode(data_, (EnableData));

        // Log the enable data
        console2.log("Enable data:", enableData.value);

        // solhint-disable-next-line custom-errors
        if (enableShouldRevert) revert("Enable should revert");

        enableValue = enableData.value;
    }

    function _disable(bytes calldata data_) internal override {
        // Decode the disable data
        DisableData memory disableData = abi.decode(data_, (DisableData));

        // Log the disable data
        console2.log("Disable data:", disableData.value, disableData.anotherValue);

        // solhint-disable-next-line custom-errors
        if (disableShouldRevert) revert("Disable should revert");

        disableValue = disableData.value;
        disableAnotherValue = disableData.anotherValue;
    }
}
