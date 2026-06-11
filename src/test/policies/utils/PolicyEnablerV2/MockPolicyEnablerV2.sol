// SPDX-License-Identifier: AGPL-3.0
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Interfaces
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Contracts
import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @notice Minimal `PolicyEnablerV2` implementation used to drive the
///         policy-side tests. The `_beforeEnable` and `_beforeDisable`
///         overrides are togglable so tests can verify revert paths.
contract MockPolicyEnablerV2 is Policy, PolicyEnablerV2 {
    error MockBeforeEnableReverted();
    error MockBeforeDisableReverted();

    bool public beforeEnableShouldRevert;
    bool public beforeDisableShouldRevert;

    bytes public lastBeforeEnableData;
    bytes public lastBeforeDisableData;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function setBeforeEnableShouldRevert(bool v_) external {
        beforeEnableShouldRevert = v_;
    }

    function setBeforeDisableShouldRevert(bool v_) external {
        beforeDisableShouldRevert = v_;
    }

    function _beforeEnable(bytes calldata data_) internal override {
        lastBeforeEnableData = data_;
        if (beforeEnableShouldRevert) revert MockBeforeEnableReverted();
    }

    function _beforeDisable(bytes calldata data_) internal override {
        lastBeforeDisableData = data_;
        if (beforeDisableShouldRevert) revert MockBeforeDisableReverted();
    }

    function gatedGivenEnabled() external view givenEnabled returns (bool) {
        return true;
    }

    function gatedGivenDisabled() external view givenDisabled returns (bool) {
        return true;
    }
}
