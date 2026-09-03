// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";
import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

contract BurnerLoansYieldClaimerExecuteTest is BurnerLoansYieldClaimerTest {
    function test_givenCallerWithoutHeartRole_reverts(address caller_) public {
        vm.assume(caller_ != heart);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        claimer.execute();
    }

    function test_givenClaimSucceeds_callsBurnerLoans() public {
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 1, "claim calls");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    function test_givenClaimReverts_reportsFailure() public {
        target.setClaimReverts(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldClaimFailed(
            address(target),
            MockBurnerLoansYieldClaimerTarget.ClaimReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix() public {
        target.setClaimRevertsWithShortData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldClaimFailed(address(target), bytes4(0xab000000));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenClaimRevertsWithLargeData_reportsBoundedFailure() public {
        target.setClaimRevertsWithLargeData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldClaimFailed(address(target), bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenConfiguredGasExceedsAvailableGas_reportsFailure() public {
        target.setClaimConsumesAllGas(true);
        vm.prank(admin);
        claimer.setExecutionGasLimit(type(uint32).max);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldClaimFailed(address(target), bytes4(0));
        vm.prank(heart);
        claimer.execute{gas: 200_000}();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenClaimExhaustsGas_laterHeartTaskStillExecutes() public {
        target.setClaimConsumesAllGas(true);
        MockPeriodicTaskManager taskManager = new MockPeriodicTaskManager(kernel);
        MockPeriodicTask laterTask = new MockPeriodicTask();

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(taskManager));
        rolesAdmin.grantRole(HEART_ROLE, address(taskManager));
        claimer.setExecutionGasLimit(200_000);
        taskManager.addPeriodicTask(address(claimer));
        taskManager.addPeriodicTask(address(laterTask));
        vm.stopPrank();

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldClaimFailed(address(target), bytes4(0));
        taskManager.executeAllTasks{gas: 1_000_000}();

        assertEq(laterTask.count(), 1, "later task count");
        assertEq(target.claimCalls(), 0, "claim calls");
    }
}
