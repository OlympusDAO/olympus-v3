// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

contract BurnerLoansSeizerTaskSelfExecuteTaskTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-SELF-EXECUTE-A01.
    function test_whenCallerIsNotSelf_reverts(address caller_) public {
        vm.assume(caller_ != address(_task));
        vm.expectRevert(IBurnerLoansSeizerTask.BurnerLoansSeizer_OnlySelf.selector);
        vm.prank(caller_);
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Rejected self-call preserves progress");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-L01.
    function test_givenTaskInactive_whenSelfCalls_reverts(bool disabled_) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Inactive self-call cannot mutate progress");
    }
}
