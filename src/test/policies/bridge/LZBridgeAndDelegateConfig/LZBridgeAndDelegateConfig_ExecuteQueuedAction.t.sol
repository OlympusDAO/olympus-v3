// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {Errors as LZErrors} from "@lz-evm-protocol-v2-3.0.162/libs/Errors.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @dev Asserts that queued sub-actions reach the configured target with the queued parameters
///      once the timelock has elapsed. One representative selector per target covers the
///      typed-dispatch path; the access matrix is in `LZBridgeAndDelegateConfig_QueueAccess`.
contract LZBridgeAndDelegateConfigTests_ExecuteQueuedAction is LZBridgeAndDelegateConfigTestBase {
    function test_execute_gatewayIncreaseBridgedSupply() external {
        uint256 amount = 100e9;

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(amount)
            )
        );

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
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.setOutRateLimits.selector,
                abi.encode(cfg)
            )
        );

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        (, uint256 limit, uint32 window, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(limit, 7e9, "Outbound limit should be set from the queued payload");
        assertEq(window, 600, "Outbound window should be set from the queued payload");
    }

    function test_execute_delegateSetSendLibrary() external {
        address lib = makeAddr("sendLib");

        vm.prank(admin);
        uint64 actionId = config.queue(
            _singleAction(
                address(lzDelegate),
                ILZEndpointV2Authorized.setSendLibrary.selector,
                abi.encode(NONCANONICAL_EID, lib)
            )
        );

        _warpPastTimelock();

        // The LZ endpoint rejects an unknown library with `LZ_OnlyRegisteredOrDefaultLib`,
        // which still exercises the typed dispatch path and confirms the call landed on the
        // endpoint with the gateway as the OApp.
        vm.expectRevert(LZErrors.LZ_OnlyRegisteredOrDefaultLib.selector);
        config.executeQueuedAction(actionId);
    }

    function test_execute_facilitatorSetGateway() external {
        address newGateway = makeAddr("newPeripheryGateway");

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(
                address(facilitator),
                ILZCrossChainBridge.setGateway.selector,
                abi.encode(newGateway)
            )
        );

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

    /// @dev The per-sub-action `TargetKind` entries recorded at queue time are consumed and
    ///      cleared by execution, so no stale storage remains for the completed action.
    function test_execute_clearsSubActionTargetKind() external {
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

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        assertEq(
            uint256(config.subActionTargetKind(actionId, 0)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.NONE),
            "Sub-action 0 kind should be cleared after execution"
        );
        assertEq(
            uint256(config.subActionTargetKind(actionId, 1)),
            uint256(ILZBridgeAndDelegateConfig.TargetKind.NONE),
            "Sub-action 1 kind should be cleared after execution"
        );
    }

    // ========== STATE GUARDS ========== //

    function test_execute_revertsBeforeTimelockElapsed() external {
        uint48 executableAt = uint48(vm.getBlockTimestamp()) + INITIAL_TIMELOCK_DELAY;

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(uint256(1))
            )
        );

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
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(uint256(1))
            )
        );

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
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(uint256(1))
            )
        );

        // Disable the config policy; execution should fail until re-enabled
        vm.prank(admin);
        config.disable(bytes(""));

        _warpPastTimelock();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        config.executeQueuedAction(actionId);
    }

    // ========== TARGET ROTATION ========== //

    /// @dev The gateway slot is rotated after a gateway sub-action is queued; the stale queued
    ///      action reverts on execution and can then be emergency cancelled.
    function test_execute_revertsIfGatewaySlotRotated() external {
        address oldGateway = address(gateway);
        address newGateway = makeAddr("rotatedGateway");

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(uint256(1))
            )
        );

        vm.prank(admin);
        uint64 rotationId = config.queueSetTargetGateway(newGateway);

        _warpPastTimelock();

        config.executeQueuedAction(rotationId);
        assertEq(config.gateway(), newGateway, "Gateway slot should be rotated");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_SubActionTargetStale.selector,
                actionId,
                uint256(0),
                oldGateway,
                newGateway
            )
        );
        config.executeQueuedAction(actionId);

        // The stale action is not bricked: emergency can clear it.
        vm.prank(emergency);
        config.cancelQueuedAction(actionId);
    }

    /// @dev An address that was the facilitator at queue time later becomes the
    ///      gateway slot (after the facilitator slot moves elsewhere). The facilitator
    ///      sub-action must NOT be re-routed through the gateway branch; it reverts because
    ///      its recorded kind is FACILITATOR and the facilitator slot no longer holds it.
    function test_execute_facilitatorActionNotReroutedWhenAddressBecomesGateway() external {
        address fac = address(facilitator);
        address fac2 = makeAddr("rotatedFacilitator");

        // setGracePeriod is the selector shared by the gateway and the facilitator branches,
        // so a re-resolution bug would have silently dispatched this through the gateway.
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(fac, IGracePeriod.setGracePeriod.selector, abi.encode(uint32(123)))
        );

        vm.prank(admin);
        uint64 moveFac = config.queueSetTargetFacilitator(fac2);
        vm.prank(admin);
        uint64 makeGwFac = config.queueSetTargetGateway(fac);

        _warpPastTimelock();

        config.executeQueuedAction(moveFac);
        config.executeQueuedAction(makeGwFac);
        assertEq(config.facilitator(), fac2, "Facilitator slot moved away");
        assertEq(config.gateway(), fac, "Gateway slot now holds the old facilitator address");

        // Recorded kind is FACILITATOR; facilitator slot is now fac2, not fac -> revert,
        // rather than dispatching through the gateway branch (gateway == fac).
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_SubActionTargetStale.selector,
                actionId,
                uint256(0),
                fac,
                fac2
            )
        );
        config.executeQueuedAction(actionId);
    }

    /// @dev A queued action whose slot was NOT rotated still executes normally (regression).
    function test_execute_succeedsWhenSlotUnchanged() external {
        uint256 amount = 100e9;

        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(
            _singleAction(
                address(gateway),
                ILZBridgeGateway.increaseBridgedSupply.selector,
                abi.encode(amount)
            )
        );

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        assertEq(gateway.bridgedSupply(), amount, "Action should execute against the gateway");
    }
}
