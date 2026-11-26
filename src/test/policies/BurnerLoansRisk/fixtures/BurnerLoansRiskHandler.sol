// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";

/// @dev Exercises a Kernel-active Risk. Unit tests cover deactivation and grace boundaries.
contract BurnerLoansRiskHandler is Test {
    BurnerLoansRisk internal immutable _risk;
    address internal immutable _ADMIN;
    address internal immutable _KERNEL_EXECUTOR;
    address public expectedOperator;
    uint48 public expectedAge;
    bool public expectedEnabled = true;

    constructor(BurnerLoansRisk risk_, address admin_, address kernelExecutor_) {
        _risk = risk_;
        _ADMIN = admin_;
        _KERNEL_EXECUTOR = kernelExecutor_;
        expectedAge = risk_.priceCacheMaxAge();
    }

    function selectOperator(address next_) external {
        if (next_ == expectedOperator) return;
        vm.prank(_ADMIN);
        _risk.setConfigOperator(next_);
        expectedOperator = next_;
    }

    function setAgeAsAdmin(uint48 age_) external {
        if (!expectedEnabled) return;
        vm.prank(_ADMIN);
        _risk.setPriceCacheMaxAge(age_);
        expectedAge = age_;
    }

    function setAgeAsOperator(uint48 age_) external {
        if (!expectedEnabled || expectedOperator == address(0)) return;
        vm.prank(expectedOperator);
        _risk.setPriceCacheMaxAge(age_);
        expectedAge = age_;
    }

    function attemptUnauthorizedAge(address caller_, uint48 age_) external {
        if (!expectedEnabled || caller_ == _ADMIN || caller_ == expectedOperator) return;
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.setPriceCacheMaxAge(age_);
    }

    function pause() external {
        if (!expectedEnabled) return;
        vm.prank(_ADMIN);
        _risk.disable("");
        expectedEnabled = false;
    }

    function enable() external {
        if (expectedEnabled) return;
        address oracle = _risk.backingOracle();
        if (
            !_risk.kernel().isPolicyActive(Policy(oracle)) || !MockBackingOracle(oracle).isEnabled()
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
            );
            vm.prank(_ADMIN);
            _risk.enable("");
            return;
        }
        vm.prank(_ADMIN);
        _risk.enable("");
        expectedEnabled = true;
    }

    function setBackingEnabled(bool enabled_) external {
        MockBackingOracle(_risk.backingOracle()).setEnabled(enabled_);
    }

    function setBackingActive(bool active_) external {
        address oracle = _risk.backingOracle();
        if (_risk.kernel().isPolicyActive(Policy(oracle)) == active_) return;
        Kernel kernel = _risk.kernel();
        vm.prank(_KERNEL_EXECUTOR);
        kernel.executeAction(active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy, oracle);
    }
}
