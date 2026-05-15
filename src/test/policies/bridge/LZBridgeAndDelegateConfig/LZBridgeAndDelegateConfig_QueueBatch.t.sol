// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @dev Verifies that batching multiple supported sub-actions yields atomic execution and
///      that the strictest proposer role implied by the batch applies.
contract LZBridgeAndDelegateConfigTests_QueueBatch is LZBridgeAndDelegateConfigTestBase {
    function _rateConfig(
        uint256 limit_,
        uint32 window_
    ) internal view returns (IOffsettingRateLimiter.RateLimitConfig[] memory cfg) {
        cfg = new IOffsettingRateLimiter.RateLimitConfig[](1);
        cfg[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: limit_,
            window: window_
        });
    }

    function _gatewayRateBatch(
        uint256 limit_,
        uint32 window_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory batch) {
        batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(gateway),
            selector: ILZBridgeGateway.setOutRateLimits.selector,
            payload: abi.encode(_rateConfig(limit_, window_))
        });
        batch[1] = ITimelockBatchQueue.BatchAction({
            target: address(gateway),
            selector: ILZBridgeGateway.setInRateLimits.selector,
            payload: abi.encode(_rateConfig(limit_, window_))
        });
    }

    function test_queueBatch_appliesAllSubActions() external {
        uint256 limit = 9_000e9;
        uint32 window = 4 hours;

        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queueBatch(_gatewayRateBatch(limit, window));

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        (, uint256 outLimit, uint32 outWindow, ) = gateway.outRateLimits(NONCANONICAL_EID);
        (, uint256 inLimit, uint32 inWindow, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(outLimit, limit, "Outbound limit applied");
        assertEq(outWindow, window, "Outbound window applied");
        assertEq(inLimit, limit, "Inbound limit applied");
        assertEq(inWindow, window, "Inbound window applied");
    }

    function test_queueBatch_revertsIfAnySubActionLacksProposerRole() external {
        // A batch with a rate-limit sub-action AND a bridge-admin sub-action requires the
        // proposer to satisfy the strictest role: bridgeAdmin or admin. A proposer that
        // only holds bridge_rate_limiter must be rejected.
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](2);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(gateway),
            selector: ILZBridgeGateway.setOutRateLimits.selector,
            payload: abi.encode(_rateConfig(1e9, 60))
        });
        batch[1] = ITimelockBatchQueue.BatchAction({
            target: address(gateway),
            selector: ILZBridgeGateway.increaseBridgedSupply.selector,
            payload: abi.encode(uint256(1))
        });

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(bridgeRateLimiter);
        config.queueBatch(batch);
    }

    function test_queueBatch_revertsIfSubActionTargetIsUnknown() external {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: makeAddr("strangerContract"),
            selector: ILZBridgeGateway.increaseBridgedSupply.selector,
            payload: abi.encode(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                batch[0].target,
                batch[0].selector
            )
        );
        vm.prank(admin);
        config.queueBatch(batch);
    }

    function test_queueBatch_revertsIfBatchEmpty() external {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](0);

        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        vm.prank(admin);
        config.queueBatch(batch);
    }
}
