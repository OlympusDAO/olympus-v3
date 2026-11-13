// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Contracts
import {BackingOracleConfigTimelockTest, BackingOracleConfigTimelock, IBackingOracle, IPolicyAdmin} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract BackingOracleTimelockReplacementTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-REPLACEMENT-01.
    function test_givenReplacement_whenOldQueueExecutes_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        BackingOracleConfigTimelock replacement = new BackingOracleConfigTimelock(
            _kernel,
            IBackingOracle(address(_oracle))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(replacement));
        vm.prank(_ADMIN);
        replacement.enable("");
        vm.prank(_ADMIN);
        uint64 next = replacement.queueSetBacking(90e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        _timelock.executeQueuedAction(id);
        assertFalse(
            _timelock.getQueuedAction(id).executed,
            "old intent retained without authority"
        );
        replacement.executeQueuedAction(next);
        assertEq(_oracle.backing(), 90e18, "replacement queue controls existing backing storage");
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(id);
        assertEq(
            _timelock.pendingActionId(_backingKey()),
            0,
            "old intent cancelled after replacement"
        );
    }
}
