// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSelfExecuteTaskTest is RevenueDistributorTaskTest {
    // Scenarios: SELF-A01.
    function test_whenExternalCallerExecutesTaskDirectly_reverts(
        address caller_,
        bool taskActive_,
        bool taskEnabled_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(caller_ != address(task));
        _setTaskLifecycle(taskActive_, taskEnabled_);
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_OnlySelf.selector);
        vm.prank(caller_);
        task.selfExecuteTask();

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: SELF-A01.
    function test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts(
        uint8 callerIndex_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        address[5] memory callers = [admin, alice, bob, emergency, address(distributor)];
        callerIndex_ = _boundUint8(callerIndex_, 0, 4);

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_OnlySelf.selector);
        vm.prank(callers[callerIndex_]);
        task.selfExecuteTask();
    }
}
