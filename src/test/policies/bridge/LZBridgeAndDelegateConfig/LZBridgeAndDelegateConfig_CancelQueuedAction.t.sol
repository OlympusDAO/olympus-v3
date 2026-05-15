// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract LZBridgeAndDelegateConfigTests_CancelQueuedAction is LZBridgeAndDelegateConfigTestBase {
    function _queueAny() internal returns (uint64 actionId) {
        vm.prank(bridgeAdmin);
        actionId = config.queueIncreaseBridgedSupply(1);
    }

    function test_cancel_emergencyCanCancel() external {
        uint64 actionId = _queueAny();

        vm.expectEmit(true, true, true, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, emergency);

        vm.prank(emergency);
        config.cancelQueuedAction(actionId);

        // After cancel the action is no longer accessible for execution.
        _warpPastTimelock();
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        config.executeQueuedAction(actionId);
    }

    function test_cancel_succeedsWhilePolicyDisabled() external {
        uint64 actionId = _queueAny();

        vm.prank(admin);
        config.disable(bytes(""));

        // Emergency cancellation is still available even when the policy is disabled, so
        // operators can flush stale entries before re-enabling.
        vm.prank(emergency);
        config.cancelQueuedAction(actionId);
    }

    function test_cancel_revertsForUnknownAction() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(42)
            )
        );
        vm.prank(emergency);
        config.cancelQueuedAction(42);
    }

    function test_cancel_revertsIfNotEmergency_admin() external {
        uint64 actionId = _queueAny();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(admin);
        config.cancelQueuedAction(actionId);
    }

    function test_cancel_revertsIfNotEmergency_proposer() external {
        uint64 actionId = _queueAny();

        // The proposer is intentionally not authorized to rescind their own queued action.
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(bridgeAdmin);
        config.cancelQueuedAction(actionId);
    }

    function testFuzz_cancel_revertsIfNotEmergency(address caller_) external {
        vm.assume(caller_ != emergency);
        uint64 actionId = _queueAny();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        config.cancelQueuedAction(actionId);
    }
}
