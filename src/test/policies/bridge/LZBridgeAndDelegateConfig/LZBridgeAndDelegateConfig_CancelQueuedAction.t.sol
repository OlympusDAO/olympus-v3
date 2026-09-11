// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract LZBridgeAndDelegateConfigTests_CancelQueuedAction is LZBridgeAndDelegateConfigTestBase {
    function _queueAny() internal returns (uint64 actionId) {
        vm.prank(bridgeAdmin);
        actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(uint256(1))
            )
        );
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

    /// @dev The per-sub-action `TargetKind` entries recorded at queue time are cleared on
    ///      cancellation, so no stale storage remains for the cancelled action.
    function test_cancel_clearsSubActionTargetKind() external {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(gateway),
            selector: ILZBridgeGateway.increaseBridgedSupply.selector,
            payload: abi.encode(uint256(1))
        });
        batch[1] = ITimelockBatchQueue.BatchAction({
            target: address(facilitator),
            selector: IGracePeriod.setGracePeriod.selector,
            payload: abi.encode(uint32(123))
        });

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);

        assertEq(
            uint256(config.subActionTargetKind(actionId, 0)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.GATEWAY),
            "Sub-action 0 kind should be GATEWAY after queueing"
        );
        assertEq(
            uint256(config.subActionTargetKind(actionId, 1)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.FACILITATOR),
            "Sub-action 1 kind should be FACILITATOR after queueing"
        );

        vm.prank(emergency);
        config.cancelQueuedAction(actionId);

        assertEq(
            uint256(config.subActionTargetKind(actionId, 0)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.NONE),
            "Sub-action 0 kind should be cleared after cancellation"
        );
        assertEq(
            uint256(config.subActionTargetKind(actionId, 1)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.NONE),
            "Sub-action 1 kind should be cleared after cancellation"
        );
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
