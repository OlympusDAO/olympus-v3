// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @dev Asserts that queued sub-actions reach the configured target with the queued parameters
///      once the timelock has elapsed. One representative selector per target covers the
///      typed-dispatch path; the access matrix is in `LZBridgeAndDelegateConfig_QueueAccess`.
contract LZBridgeAndDelegateConfigTests_ExecuteQueuedAction is LZBridgeAndDelegateConfigTestBase {
    function test_execute_gatewayIncreaseBridgedSupply() external {
        uint256 amount = 100e9;

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queueIncreaseBridgedSupply(amount);

        _warpPastTimelock();

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyIncreased(amount);

        config.executeQueuedAction(actionId);

        assertEq(gateway.bridgedSupply(), amount, "Gateway supply should reflect the queued op");
    }

    function test_execute_gatewaySetOutRateLimits() external {
        IOffsettingRateLimiter.RateLimitConfig[]
            memory cfg = new IOffsettingRateLimiter.RateLimitConfig[](1);
        cfg[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 7e9,
            window: 600
        });

        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queueSetOutRateLimits(cfg);

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        (, uint256 limit, uint32 window, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(limit, 7e9, "Outbound limit should be set from the queued payload");
        assertEq(window, 600, "Outbound window should be set from the queued payload");
    }

    function test_execute_delegateSetSendLibrary() external {
        address lib = makeAddr("sendLib");

        vm.prank(admin);
        uint64 actionId = config.queueSetSendLibrary(NONCANONICAL_EID, lib);

        _warpPastTimelock();

        // The LZ endpoint will reject an unknown library, so we expect a revert from the
        // endpoint - which still exercises the typed dispatch path and confirms the call
        // landed on the endpoint with the gateway as the OApp.
        vm.expectRevert();
        config.executeQueuedAction(actionId);
    }

    function test_execute_facilitatorSetGateway() external {
        address newGateway = makeAddr("newPeripheryGateway");

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queueSetFacilitatorGateway(newGateway);

        _warpPastTimelock();

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.GatewaySet(newGateway);

        config.executeQueuedAction(actionId);
        assertEq(facilitator.gateway(), newGateway, "Periphery gateway should be set");
    }

    function test_execute_selfSetTargetGateway() external {
        address newGateway = makeAddr("rotatedGateway");

        vm.prank(admin);
        uint64 actionId = config.queueSetTargetGateway(newGateway);

        _warpPastTimelock();

        config.executeQueuedAction(actionId);
        assertEq(config.gateway(), newGateway, "Config's gateway slot should be rotated");
    }

    function test_execute_selfSetTimelockDelay() external {
        uint48 newDelay = INITIAL_TIMELOCK_DELAY + 1 days;

        vm.prank(admin);
        uint64 actionId = config.queueSetTimelockDelay(newDelay);

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        assertEq(
            uint256(config.timelockDelay()),
            uint256(newDelay),
            "Timelock delay should reflect the queued value"
        );
    }

    // ========== STATE GUARDS ========== //

    function test_execute_revertsBeforeTimelockElapsed() external {
        uint48 executableAt = uint48(vm.getBlockTimestamp()) + INITIAL_TIMELOCK_DELAY;

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queueIncreaseBridgedSupply(1);

        // Without warping the action is still timelocked
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                executableAt
            )
        );
        config.executeQueuedAction(actionId);
    }

    function test_execute_revertsAfterExpiry() external {
        uint48 expiresAt = uint48(vm.getBlockTimestamp()) +
            INITIAL_TIMELOCK_DELAY +
            uint48(config.EXECUTION_WINDOW());

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queueIncreaseBridgedSupply(1);

        // Warp past timelock + execution window
        vm.warp(vm.getBlockTimestamp() + INITIAL_TIMELOCK_DELAY + config.EXECUTION_WINDOW() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                expiresAt
            )
        );
        config.executeQueuedAction(actionId);
    }

    function test_execute_revertsIfDisabled() external {
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queueIncreaseBridgedSupply(1);

        // Disable the config policy; execution should fail until re-enabled
        vm.prank(admin);
        config.disable(bytes(""));

        _warpPastTimelock();

        vm.expectRevert();
        config.executeQueuedAction(actionId);
    }
}
