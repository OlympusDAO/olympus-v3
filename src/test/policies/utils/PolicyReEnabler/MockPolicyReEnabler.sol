// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Contracts
import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyReEnabler} from "src/policies/utils/PolicyReEnabler.sol";

/// @notice Minimal `PolicyReEnabler` implementation used to drive the
///         policy-side tests. The `_beforeEnable`, `_beforeDisable`, and
///         `_beforeReEnable` overrides are togglable so tests can verify
///         revert paths through the implementation hooks.
contract MockPolicyReEnabler is Policy, PolicyReEnabler {
    error MockBeforeReEnableReverted();

    bool public beforeReEnableShouldRevert;

    uint256 public reEnableCount;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        return dependencies;
    }

    function setBeforeReEnableShouldRevert(bool v_) external {
        beforeReEnableShouldRevert = v_;
    }

    function _beforeReEnable() internal override {
        ++reEnableCount;
        if (beforeReEnableShouldRevert) revert MockBeforeReEnableReverted();
    }
}
