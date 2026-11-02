// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

// Numeric bounds fit uint8 and uint32 by construction.
// forge-lint: disable-start(unsafe-typecast,literal-instead-of-constant)
contract BurnerLoansSeizerTaskSetExecutionGasLimitTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-EXECUTION-GAS-A02, BLSEIZ-EXECUTION-GAS-A03, BLSEIZ-EXECUTION-GAS-A04, BLSEIZ-EXECUTION-GAS-P02.
    function test_givenPermittedCaller_whenGasLimitSet(
        address caller_,
        uint8 roleClass_,
        uint32 gas_,
        bool disabled_
    ) public {
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        _grantTaskAdmin(caller_, roleClass_);
        gas_ = uint32(bound(gas_, 1, type(uint32).max));
        vm.assume(gas_ != _task.executionGasLimit());
        _setTaskEnabled(!disabled_);
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionGasLimitSet(gas_);
        vm.prank(caller_);
        _task.setExecutionGasLimit(gas_);
        assertEq(_task.executionGasLimit(), gas_, "Exact uint32 gas budget stored");
        assertEq(_task.isEnabled(), !disabled_, "Setting gas preserves lifecycle");
    }

    // Scenarios: BLSEIZ-EXECUTION-GAS-A02, BLSEIZ-EXECUTION-GAS-A03, BLSEIZ-EXECUTION-GAS-A04, BLSEIZ-EXECUTION-GAS-P02.
    function test_whenRoleAndNumericBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            assertTrue(vm.revertToState(checkpoint), "Restore minimum-budget role fixture");
            test_givenPermittedCaller_whenGasLimitSet(_ALICE, roleClass, 1, true);
            assertTrue(vm.revertToState(checkpoint), "Restore maximum-budget role fixture");
            test_givenPermittedCaller_whenGasLimitSet(_ALICE, roleClass, type(uint32).max, false);
        }
    }

    // Scenarios: BLSEIZ-EXECUTION-GAS-A01.
    function test_whenCallerHasNeitherRole_whenGasLimitSet_reverts(
        address caller_,
        uint32 gas_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _task.setExecutionGasLimit(gas_);
        assertEq(_task.executionGasLimit(), 10_000_000, "Unauthorized call preserves gas budget");
    }

    // Scenarios: BLSEIZ-EXECUTION-GAS-P01.
    function test_whenGasLimitZero_reverts() public {
        vm.expectRevert(IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidExecutionGasLimit.selector);
        _task.setExecutionGasLimit(0);
    }

    // Scenarios: BLSEIZ-EXECUTION-GAS-P04.
    function test_whenGasLimitUnchanged_thenNoEvent() public {
        vm.recordLogs();
        _task.setExecutionGasLimit(_task.executionGasLimit());
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged gas budget is an event-free no-op");
    }

    // Scenarios: BLSEIZ-EXECUTION-GAS-P03.
    function test_givenInactiveTask_whenGasLimitSet_reverts(bool disabled_) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.setExecutionGasLimit(1);
    }
}
// forge-lint: disable-end(unsafe-typecast,literal-instead-of-constant)
