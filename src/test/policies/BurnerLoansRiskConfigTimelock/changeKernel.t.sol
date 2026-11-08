// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";

contract BurnerLoansRiskConfigTimelockChangeKernelTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-KERNEL-P01.
    function test_givenQueueMigratesAlone_whenPendingIntentExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        vm.mockCall(
            address(next),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_timelock)),
            abi.encode(true)
        );
        _makeReady(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(next),
                address(_kernel)
            )
        );
        _timelock.executeQueuedAction(id);
        assertEq(
            address(_timelock.risk()),
            address(_risk),
            "migration does not retarget pending actions"
        );
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            id,
            "mismatched migration preserves intent"
        );
    }

    // Scenarios: BLRCT-KERNEL-P02.
    function test_givenCompatibleKernelMigration_whenPendingIntentExecuted() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        Kernel next = new Kernel();
        _kernel.executeAction(Actions.MigrateKernel, address(next));
        next.executeAction(Actions.InstallModule, address(_roles));
        next.executeAction(Actions.InstallModule, address(_floan));
        next.executeAction(Actions.InstallModule, address(_price));
        next.executeAction(Actions.ActivatePolicy, address(_risk));
        next.executeAction(Actions.ActivatePolicy, address(_timelock));
        assertEq(address(_risk.kernel()), address(next), "target Kernel migrated");
        assertEq(address(_timelock.kernel()), address(next), "queue Kernel migrated");
        _makeReady(id);
        _executeAndAssert(id, _recipient);
        assertEq(
            _risk.referralFeeBps(),
            2500,
            "original intent executes after compatible restoration"
        );
    }
}
