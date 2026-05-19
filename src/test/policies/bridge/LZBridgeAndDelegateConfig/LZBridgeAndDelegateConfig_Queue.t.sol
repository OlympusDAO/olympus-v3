// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";

// Contracts
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";

/// @dev Queue-time validation for the `queue` batch entry point on
///      `LZBridgeAndDelegateConfig`: every gateway, delegate, and facilitator sub-action is
///      submitted as a length-1 batch and exercises its proposer-role gate, payload shape,
///      and the target-side `validate*` mirror. Each sub-action gets a positive test per
///      accepted role, a `testFuzz_*_revertsIfNot*` rejection check, and (where applicable)
///      a payload-invariant revert. Multi-action atomic batching and the self-target
///      rejection are covered up top. Self-config (`queueSetTarget*`,
///      `queueSetTimelockDelay`) is covered in dedicated per-function test files.
contract LZBridgeAndDelegateConfigTests_Queue is LZBridgeAndDelegateConfigTestBase {
    // ========== HELPERS ========== //

    /// @dev Single-action batch targeting the gateway.
    function _gw(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory) {
        return _singleAction(address(gateway), selector_, payload_);
    }

    /// @dev Single-action batch targeting the delegate.
    function _dg(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory) {
        return _singleAction(address(lzDelegate), selector_, payload_);
    }

    /// @dev Single-action batch targeting the facilitator.
    function _fac(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory) {
        return _singleAction(address(facilitator), selector_, payload_);
    }

    /// @dev Deploys a fresh config policy whose ERC-165 advertises
    ///      `ILZBridgeAndDelegateConfig`, so that `validateSetConfigurator` accepts it.
    function _deploySecondaryConfig() internal returns (LZBridgeAndDelegateConfig secondary) {
        secondary = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
    }

    /// @dev Seeds the gateway with bridged supply so that a positive decrease payload does
    ///      not trip the queue-time underflow guard before the role check is exercised.
    function _seedBridgedSupply(uint256 amount_) internal {
        vm.prank(address(config));
        gateway.increaseBridgedSupply(amount_);
    }

    /// @dev Builds a single-entry outbound/inbound rate-limit configuration array.
    function _rateConfigs()
        internal
        view
        returns (IOffsettingRateLimiter.RateLimitConfig[] memory cfg)
    {
        cfg = _rateConfig(1e9, 3600);
    }

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

    /// @dev Builds a single-entry endpoint-id list for the in-flight-clear helpers.
    function _eidList() internal pure returns (uint32[] memory eids) {
        eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;
    }

    /// @dev Builds an empty `SetConfigParam` list for endpoint-config helpers.
    function _emptyConfigParams() internal pure returns (SetConfigParam[] memory params) {
        params = new SetConfigParam[](0);
    }

    /// @dev Returns `data_` with its final byte removed, i.e. one byte shorter than the
    ///      minimal validly encoded payload. Feeding this to `queue` trips the queue-time
    ///      payload-length guard, which reverts with `ITimelockBatchQueue_ActionInvalid`,
    ///      as the truncated-payload tests assert. Callers must pass a non-empty buffer.
    function _oneByteShort(bytes memory data_) internal pure returns (bytes memory short_) {
        uint256 newLen = data_.length - 1;
        short_ = new bytes(newLen);
        for (uint256 i = 0; i < newLen; ++i) {
            short_[i] = data_[i];
        }
    }

    /// @dev Returns `data_` with a trailing zero word appended. For static-shape payloads
    ///      this overshoots the exact length; for dynamic-shape payloads it decodes fine but
    ///      no longer round-trips to the canonical encoding. Either way the queue-time guard
    ///      rejects it with `ITimelockBatchQueue_ActionInvalid`.
    function _withTrailingWord(bytes memory data_) internal pure returns (bytes memory padded_) {
        padded_ = bytes.concat(data_, new bytes(32));
    }

    /// @dev Minimal valid encoding of a `RateLimitConfig[]` argument: an empty array, which
    ///      ABI-encodes to the 64-byte offset/length pair.
    function _emptyRateConfigsEncoded() internal pure returns (bytes memory) {
        return abi.encode(new IOffsettingRateLimiter.RateLimitConfig[](0));
    }

    /// @dev Minimal valid encoding of a `uint32[]` argument: an empty array.
    function _emptyEidsEncoded() internal pure returns (bytes memory) {
        return abi.encode(new uint32[](0));
    }

    /// @dev Minimal valid encoding of `setEndpointConfig`'s `(address, SetConfigParam[])`
    ///      argument: a library address followed by an empty config-param array.
    function _emptyEndpointConfigEncoded() internal returns (bytes memory) {
        return abi.encode(makeAddr("lib"), new SetConfigParam[](0));
    }

    /// @dev Asserts the complete `TimelockBatchQueue` state after a successful `queue` call.
    ///      Checks `nextActionId`, all `QueuedAction` metadata fields, batch length, and every
    ///      sub-action (target, selector, payload).
    function _assertQueued(
        uint64 actionId_,
        address proposer_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view {
        assertEq(config.nextActionId(), actionId_ + 1, "nextActionId incremented");

        ITimelockBatchQueue.QueuedAction memory stored = config.getQueuedAction(actionId_);
        assertEq(stored.proposer, proposer_, "proposer recorded");
        assertEq(stored.queuedAt, uint48(block.timestamp), "queuedAt set");
        assertEq(
            stored.executableAt,
            uint48(block.timestamp) + INITIAL_TIMELOCK_DELAY,
            "executableAt set"
        );
        assertEq(
            stored.expiresAt,
            stored.executableAt + config.EXECUTION_WINDOW(),
            "expiresAt set"
        );
        assertFalse(stored.executed, "not yet executed");
        assertFalse(stored.cancelled, "not yet cancelled");

        assertEq(config.getQueuedActionLength(actionId_), actions_.length, "batch length stored");
        for (uint256 i = 0; i < actions_.length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = config.getQueuedSubAction(
                actionId_,
                i
            );
            assertEq(target, actions_[i].target, "sub-action target");
            assertEq(bytes32(selector), bytes32(actions_[i].selector), "sub-action selector");
            assertEq(payload, actions_[i].payload, "sub-action payload");
        }
    }

    /// @dev Sets up `vm.expectEmit` expectations for every event emitted by `_queueAction`:
    ///      one `TimelockSubActionQueued` per sub-action followed by one `TimelockActionQueued`.
    ///      Must be called immediately before the `config.queue()` call.
    function _expectQueueEvents(
        uint64 actionId_,
        address proposer_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal {
        uint48 executableAt = uint48(block.timestamp) + INITIAL_TIMELOCK_DELAY;
        uint48 expiresAt = executableAt + config.EXECUTION_WINDOW();

        for (uint256 i = 0; i < actions_.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                actionId_,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }

        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionQueued(
            actionId_,
            proposer_,
            keccak256(abi.encode(actions_)),
            executableAt,
            expiresAt
        );
    }

    // ========== BATCH SEMANTICS ========== //

    function test_queue_appliesAllSubActions() external {
        uint256 limit = 9_000e9;
        uint32 window = 4 hours;

        ITimelockBatchQueue.BatchAction[] memory batch = _gatewayRateBatch(limit, window);

        _expectQueueEvents(1, bridgeRateLimiter, batch);
        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(batch);

        _assertQueued(actionId, bridgeRateLimiter, batch);

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        (, uint256 outLimit, uint32 outWindow, ) = gateway.outRateLimits(NONCANONICAL_EID);
        (, uint256 inLimit, uint32 inWindow, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(outLimit, limit, "Outbound limit applied");
        assertEq(outWindow, window, "Outbound window applied");
        assertEq(inLimit, limit, "Inbound limit applied");
        assertEq(inWindow, window, "Inbound window applied");

        ITimelockBatchQueue.QueuedAction memory executedAction = config.getQueuedAction(actionId);
        assertTrue(executedAction.executed, "action marked executed");
        assertFalse(executedAction.cancelled, "action not cancelled");
        assertEq(executedAction.actions.length, 0, "sub-actions cleared after execution");
        assertEq(config.nextActionId(), 2, "nextActionId unchanged after execution");
    }

    function test_queue_revertsIfAnySubActionLacksProposerRole() external {
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

        _expectNotAuthorized();
        vm.prank(bridgeRateLimiter);
        config.queue(batch);
    }

    function test_queue_revertsIfSubActionTargetIsUnknown() external {
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
        config.queue(batch);
    }

    function test_queue_revertsIfSubActionTargetsSelf() external {
        // Self-config must go through the typed `queueSetTarget*` helpers; `queue` rejects
        // any sub-action aimed at the policy itself before it reaches the timelock.
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(config),
            selector: config.queueSetTargetGateway.selector,
            payload: abi.encode(makeAddr("newGateway"))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                batch[0].target,
                batch[0].selector
            )
        );
        vm.prank(admin);
        config.queue(batch);
    }

    function test_queue_revertsIfBatchEmpty() external {
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](0);

        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        vm.prank(admin);
        config.queue(batch);
    }

    // ========== gateway: setDelegate ========== //

    function test_queue_acceptsGatewaySetDelegateByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setDelegate.selector,
            abi.encode(makeAddr("delegateCandidate"))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setDelegate queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewaySetDelegateByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setDelegate.selector,
            abi.encode(makeAddr("delegateCandidate"))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setDelegate queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewaySetDelegatePayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setDelegate.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setDelegate.selector, bytes("")));
    }

    function test_queue_revertsIfGatewaySetDelegatePayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setDelegate.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.setDelegate.selector,
                _oneByteShort(abi.encode(makeAddr("delegateCandidate")))
            )
        );
    }

    function testFuzz_queue_revertsIfGatewaySetDelegateNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _gw(ILZBridgeGateway.setDelegate.selector, abi.encode(makeAddr("delegateCandidate")))
        );
    }

    function test_queue_revertsIfGatewaySetDelegateZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "delegate"
            )
        );
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setDelegate.selector, abi.encode(address(0))));
    }

    // ========== gateway: increaseBridgedSupply ========== //

    function test_queue_acceptsGatewayIncreaseBridgedSupplyByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.increaseBridgedSupply.selector,
            abi.encode(uint256(1))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "increaseBridgedSupply queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewayIncreaseBridgedSupplyByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.increaseBridgedSupply.selector,
            abi.encode(uint256(1))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "increaseBridgedSupply queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewayIncreaseBridgedSupplyPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.increaseBridgedSupply.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, bytes("")));
    }

    function test_queue_revertsIfGatewayIncreaseBridgedSupplyPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.increaseBridgedSupply.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.increaseBridgedSupply.selector,
                _oneByteShort(abi.encode(uint256(1)))
            )
        );
    }

    function testFuzz_queue_revertsIfGatewayIncreaseBridgedSupplyNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_revertsIfGatewayIncreaseBridgedSupplyZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(0))));
    }

    // ========== gateway: decreaseBridgedSupply ========== //

    function test_queue_acceptsGatewayDecreaseBridgedSupplyByAdmin() external {
        _seedBridgedSupply(100);

        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.decreaseBridgedSupply.selector,
            abi.encode(uint256(1))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "decreaseBridgedSupply queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewayDecreaseBridgedSupplyByBridgeAdmin() external {
        _seedBridgedSupply(100);

        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.decreaseBridgedSupply.selector,
            abi.encode(uint256(1))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "decreaseBridgedSupply queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewayDecreaseBridgedSupplyPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.decreaseBridgedSupply.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, bytes("")));
    }

    function test_queue_revertsIfGatewayDecreaseBridgedSupplyPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.decreaseBridgedSupply.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.decreaseBridgedSupply.selector,
                _oneByteShort(abi.encode(uint256(1)))
            )
        );
    }

    function testFuzz_queue_revertsIfGatewayDecreaseBridgedSupplyNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_revertsIfGatewayDecreaseBridgedSupplyZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(0))));
    }

    function test_queue_revertsIfGatewayDecreaseBridgedSupplyUnderflow() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                5
            )
        );
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(5))));
    }

    // ========== gateway: setGracePeriod ========== //

    function test_queue_acceptsGatewaySetGracePeriodByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            IGracePeriod.setGracePeriod.selector,
            abi.encode(uint32(1))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGracePeriod queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewaySetGracePeriodByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            IGracePeriod.setGracePeriod.selector,
            abi.encode(uint32(1))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGracePeriod queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewaySetGracePeriodPayloadEmpty() external {
        _expectActionInvalid(address(gateway), IGracePeriod.setGracePeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, bytes("")));
    }

    function test_queue_revertsIfGatewaySetGracePeriodPayloadTooShort() external {
        _expectActionInvalid(address(gateway), IGracePeriod.setGracePeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(IGracePeriod.setGracePeriod.selector, _oneByteShort(abi.encode(uint32(1))))
        );
    }

    function testFuzz_queue_revertsIfGatewaySetGracePeriodNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_revertsIfGatewaySetGracePeriodZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(0))));
    }

    // ========== gateway: setOutRateLimits ========== //

    function test_queue_acceptsGatewaySetOutRateLimitsByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setOutRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setOutRateLimits queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewaySetOutRateLimitsByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setOutRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setOutRateLimits queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_acceptsGatewaySetOutRateLimitsByBridgeRateLimiter() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setOutRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setOutRateLimits queued");
        _assertQueued(actionId, bridgeRateLimiter, batch);
    }

    function test_queue_acceptsGatewaySetOutRateLimitsWithMinimalValidPayload() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setOutRateLimits.selector,
            _emptyRateConfigsEncoded()
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "Minimal valid setOutRateLimits payload should be queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewaySetOutRateLimitsPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setOutRateLimits.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, bytes("")));
    }

    function test_queue_revertsIfGatewaySetOutRateLimitsPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setOutRateLimits.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.setOutRateLimits.selector,
                _oneByteShort(_emptyRateConfigsEncoded())
            )
        );
    }

    function testFuzz_queue_revertsIfGatewaySetOutRateLimitsNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, abi.encode(_rateConfigs())));
    }

    // ========== gateway: setInRateLimits ========== //

    function test_queue_acceptsGatewaySetInRateLimitsByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setInRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setInRateLimits queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewaySetInRateLimitsByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setInRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setInRateLimits queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_acceptsGatewaySetInRateLimitsByBridgeRateLimiter() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setInRateLimits.selector,
            abi.encode(_rateConfigs())
        );
        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setInRateLimits queued");
        _assertQueued(actionId, bridgeRateLimiter, batch);
    }

    function test_queue_acceptsGatewaySetInRateLimitsWithMinimalValidPayload() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.setInRateLimits.selector,
            _emptyRateConfigsEncoded()
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "Minimal valid setInRateLimits payload should be queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewaySetInRateLimitsPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setInRateLimits.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, bytes("")));
    }

    function test_queue_revertsIfGatewaySetInRateLimitsPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setInRateLimits.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.setInRateLimits.selector,
                _oneByteShort(_emptyRateConfigsEncoded())
            )
        );
    }

    function testFuzz_queue_revertsIfGatewaySetInRateLimitsNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, abi.encode(_rateConfigs())));
    }

    // ========== gateway: clearOutboundInFlight ========== //

    function test_queue_acceptsGatewayClearOutboundInFlightByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearOutboundInFlight.selector,
            abi.encode(_eidList())
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearOutboundInFlight queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewayClearOutboundInFlightByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearOutboundInFlight.selector,
            abi.encode(_eidList())
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearOutboundInFlight queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_acceptsGatewayClearOutboundInFlightByBridgeRateLimiter() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearOutboundInFlight.selector,
            abi.encode(_eidList())
        );
        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearOutboundInFlight queued");
        _assertQueued(actionId, bridgeRateLimiter, batch);
    }

    function test_queue_acceptsGatewayClearOutboundInFlightWithMinimalValidPayload() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearOutboundInFlight.selector,
            _emptyEidsEncoded()
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "Minimal valid clearOutboundInFlight payload should be queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewayClearOutboundInFlightPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.clearOutboundInFlight.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, bytes("")));
    }

    function test_queue_revertsIfGatewayClearOutboundInFlightPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.clearOutboundInFlight.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(ILZBridgeGateway.clearOutboundInFlight.selector, _oneByteShort(_emptyEidsEncoded()))
        );
    }

    function testFuzz_queue_revertsIfGatewayClearOutboundInFlightNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, abi.encode(_eidList())));
    }

    // ========== gateway: clearInboundInFlight ========== //

    function test_queue_acceptsGatewayClearInboundInFlightByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearInboundInFlight.selector,
            abi.encode(_eidList())
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearInboundInFlight queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsGatewayClearInboundInFlightByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearInboundInFlight.selector,
            abi.encode(_eidList())
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearInboundInFlight queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_acceptsGatewayClearInboundInFlightByBridgeRateLimiter() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearInboundInFlight.selector,
            abi.encode(_eidList())
        );
        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "clearInboundInFlight queued");
        _assertQueued(actionId, bridgeRateLimiter, batch);
    }

    function test_queue_acceptsGatewayClearInboundInFlightWithMinimalValidPayload() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _gw(
            ILZBridgeGateway.clearInboundInFlight.selector,
            _emptyEidsEncoded()
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "Minimal valid clearInboundInFlight payload should be queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfGatewayClearInboundInFlightPayloadEmpty() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.clearInboundInFlight.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, bytes("")));
    }

    function test_queue_revertsIfGatewayClearInboundInFlightPayloadTooShort() external {
        _expectActionInvalid(address(gateway), ILZBridgeGateway.clearInboundInFlight.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(ILZBridgeGateway.clearInboundInFlight.selector, _oneByteShort(_emptyEidsEncoded()))
        );
    }

    function testFuzz_queue_revertsIfGatewayClearInboundInFlightNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, abi.encode(_eidList())));
    }

    // ========== delegate: setSendLibrary ========== //

    function test_queue_acceptsDelegateSetSendLibraryByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setSendLibrary.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("sendLib"))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setSendLibrary queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsDelegateSetSendLibraryByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setSendLibrary.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("sendLib"))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setSendLibrary queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfDelegateSetSendLibraryPayloadEmpty() external {
        _expectActionInvalid(address(lzDelegate), ILZEndpointV2Authorized.setSendLibrary.selector);
        vm.prank(bridgeAdmin);
        config.queue(_dg(ILZEndpointV2Authorized.setSendLibrary.selector, bytes("")));
    }

    function test_queue_revertsIfDelegateSetSendLibraryPayloadTooShort() external {
        _expectActionInvalid(address(lzDelegate), ILZEndpointV2Authorized.setSendLibrary.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setSendLibrary.selector,
                _oneByteShort(abi.encode(NONCANONICAL_EID, makeAddr("sendLib")))
            )
        );
    }

    function testFuzz_queue_revertsIfDelegateSetSendLibraryNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setSendLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("sendLib"))
            )
        );
    }

    // ========== delegate: setReceiveLibrary ========== //

    function test_queue_acceptsDelegateSetReceiveLibraryByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setReceiveLibrary.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReceiveLibrary queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsDelegateSetReceiveLibraryByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setReceiveLibrary.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReceiveLibrary queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfDelegateSetReceiveLibraryPayloadEmpty() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setReceiveLibrary.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(_dg(ILZEndpointV2Authorized.setReceiveLibrary.selector, bytes("")));
    }

    function test_queue_revertsIfDelegateSetReceiveLibraryPayloadTooShort() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setReceiveLibrary.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibrary.selector,
                _oneByteShort(abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0)))
            )
        );
    }

    function testFuzz_queue_revertsIfDelegateSetReceiveLibraryNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    // ========== delegate: setReceiveLibraryTimeout ========== //

    function test_queue_acceptsDelegateSetReceiveLibraryTimeoutByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReceiveLibraryTimeout queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsDelegateSetReceiveLibraryTimeoutByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
            abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReceiveLibraryTimeout queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfDelegateSetReceiveLibraryTimeoutPayloadEmpty() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(_dg(ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector, bytes("")));
    }

    function test_queue_revertsIfDelegateSetReceiveLibraryTimeoutPayloadTooShort() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
                _oneByteShort(abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0)))
            )
        );
    }

    function testFuzz_queue_revertsIfDelegateSetReceiveLibraryTimeoutNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    // ========== delegate: setEndpointConfig ========== //

    function test_queue_acceptsDelegateSetEndpointConfigByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setEndpointConfig.selector,
            abi.encode(makeAddr("lib"), _emptyConfigParams())
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setEndpointConfig queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsDelegateSetEndpointConfigByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setEndpointConfig.selector,
            abi.encode(makeAddr("lib"), _emptyConfigParams())
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setEndpointConfig queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_acceptsDelegateSetEndpointConfigWithMinimalValidPayload() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _dg(
            ILZEndpointV2Authorized.setEndpointConfig.selector,
            _emptyEndpointConfigEncoded()
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "Minimal valid setEndpointConfig payload should be queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfDelegateSetEndpointConfigPayloadEmpty() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setEndpointConfig.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(_dg(ILZEndpointV2Authorized.setEndpointConfig.selector, bytes("")));
    }

    function test_queue_revertsIfDelegateSetEndpointConfigPayloadTooShort() external {
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setEndpointConfig.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setEndpointConfig.selector,
                _oneByteShort(_emptyEndpointConfigEncoded())
            )
        );
    }

    function testFuzz_queue_revertsIfDelegateSetEndpointConfigNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setEndpointConfig.selector,
                abi.encode(makeAddr("lib"), _emptyConfigParams())
            )
        );
    }

    // ========== facilitator: setGateway ========== //

    function test_queue_acceptsFacilitatorSetGatewayByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            ILZCrossChainBridge.setGateway.selector,
            abi.encode(makeAddr("gatewayCandidate"))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGateway queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsFacilitatorSetGatewayByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            ILZCrossChainBridge.setGateway.selector,
            abi.encode(makeAddr("gatewayCandidate"))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGateway queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfFacilitatorSetGatewayPayloadEmpty() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setGateway.selector);
        vm.prank(bridgeAdmin);
        config.queue(_fac(ILZCrossChainBridge.setGateway.selector, bytes("")));
    }

    function test_queue_revertsIfFacilitatorSetGatewayPayloadTooShort() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setGateway.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setGateway.selector,
                _oneByteShort(abi.encode(makeAddr("gatewayCandidate")))
            )
        );
    }

    function testFuzz_queue_revertsIfFacilitatorSetGatewayNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _fac(ILZCrossChainBridge.setGateway.selector, abi.encode(makeAddr("gatewayCandidate")))
        );
    }

    function test_queue_revertsIfFacilitatorSetGatewayZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        vm.prank(bridgeAdmin);
        config.queue(_fac(ILZCrossChainBridge.setGateway.selector, abi.encode(address(0))));
    }

    // ========== facilitator: setReEnabler ========== //

    function test_queue_acceptsFacilitatorSetReEnablerByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            ILZCrossChainBridge.setReEnabler.selector,
            abi.encode(makeAddr("reEnablerCandidate"))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReEnabler queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsFacilitatorSetReEnablerByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            ILZCrossChainBridge.setReEnabler.selector,
            abi.encode(makeAddr("reEnablerCandidate"))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setReEnabler queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfFacilitatorSetReEnablerPayloadEmpty() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setReEnabler.selector);
        vm.prank(bridgeAdmin);
        config.queue(_fac(ILZCrossChainBridge.setReEnabler.selector, bytes("")));
    }

    function test_queue_revertsIfFacilitatorSetReEnablerPayloadTooShort() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setReEnabler.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setReEnabler.selector,
                _oneByteShort(abi.encode(makeAddr("reEnablerCandidate")))
            )
        );
    }

    function testFuzz_queue_revertsIfFacilitatorSetReEnablerNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _fac(
                ILZCrossChainBridge.setReEnabler.selector,
                abi.encode(makeAddr("reEnablerCandidate"))
            )
        );
    }

    // ========== facilitator: setGracePeriod ========== //

    function test_queue_acceptsFacilitatorSetGracePeriodByAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            IGracePeriod.setGracePeriod.selector,
            abi.encode(uint32(1))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGracePeriod queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_acceptsFacilitatorSetGracePeriodByBridgeAdmin() external {
        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            IGracePeriod.setGracePeriod.selector,
            abi.encode(uint32(1))
        );
        vm.prank(bridgeAdmin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setGracePeriod queued");
        _assertQueued(actionId, bridgeAdmin, batch);
    }

    function test_queue_revertsIfFacilitatorSetGracePeriodPayloadEmpty() external {
        _expectActionInvalid(address(facilitator), IGracePeriod.setGracePeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, bytes("")));
    }

    function test_queue_revertsIfFacilitatorSetGracePeriodPayloadTooShort() external {
        _expectActionInvalid(address(facilitator), IGracePeriod.setGracePeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _fac(IGracePeriod.setGracePeriod.selector, _oneByteShort(abi.encode(uint32(1))))
        );
    }

    function testFuzz_queue_revertsIfFacilitatorSetGracePeriodNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_revertsIfFacilitatorSetGracePeriodZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(0))));
    }

    // ========== facilitator: setConfigurator ========== //

    function test_queue_acceptsFacilitatorSetConfiguratorByAdmin() external {
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        ITimelockBatchQueue.BatchAction[] memory batch = _fac(
            ILZCrossChainBridge.setConfigurator.selector,
            abi.encode(address(secondary))
        );
        _expectQueueEvents(1, admin, batch);
        vm.prank(admin);
        uint64 actionId = config.queue(batch);
        assertEq(actionId, 1, "setConfigurator queued");
        _assertQueued(actionId, admin, batch);
    }

    function test_queue_revertsIfFacilitatorSetConfiguratorPayloadEmpty() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setConfigurator.selector);
        vm.prank(admin);
        config.queue(_fac(ILZCrossChainBridge.setConfigurator.selector, bytes("")));
    }

    function test_queue_revertsIfFacilitatorSetConfiguratorPayloadTooShort() external {
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setConfigurator.selector);
        vm.prank(admin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setConfigurator.selector,
                _oneByteShort(abi.encode(makeAddr("configuratorCandidate")))
            )
        );
    }

    function testFuzz_queue_revertsIfFacilitatorSetConfiguratorNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        _expectAdminRole();
        vm.prank(caller_);
        config.queue(
            _fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(secondary)))
        );
    }

    function test_queue_revertsIfFacilitatorSetConfiguratorZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        vm.prank(admin);
        config.queue(_fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(0))));
    }

    function test_queue_revertsIfFacilitatorSetConfiguratorErc165Rejects() external {
        // The gateway is not an `ILZBridgeAndDelegateConfig`; its ERC-165 will return false
        // for that interface ID, so the configurator validator must reject it.
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidConfigurator.selector,
                address(gateway)
            )
        );
        vm.prank(admin);
        config.queue(
            _fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(gateway)))
        );
    }

    // ========== payload canonicalization: trailing bytes ========== //

    // A canonical payload with an extra trailing word appended. For static-shape sub-actions
    // this overshoots the exact length guard; for dynamic-shape sub-actions it decodes fine
    // but no longer round-trips to the canonical encoding. Both must be rejected with
    // `ITimelockBatchQueue_ActionInvalid` at queue time. One representative selector is
    // exercised per distinct guard branch.

    function test_queue_revertsIfGatewaySetDelegatePayloadHasTrailingBytes() external {
        // Static single-word guard (_LEN_SINGLE_WORD).
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setDelegate.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.setDelegate.selector,
                _withTrailingWord(abi.encode(makeAddr("delegateCandidate")))
            )
        );
    }

    function test_queue_revertsIfDelegateSetSendLibraryPayloadHasTrailingBytes() external {
        // Static two-word guard (_LEN_SEND_LIBRARY).
        _expectActionInvalid(address(lzDelegate), ILZEndpointV2Authorized.setSendLibrary.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setSendLibrary.selector,
                _withTrailingWord(abi.encode(NONCANONICAL_EID, makeAddr("sendLib")))
            )
        );
    }

    function test_queue_revertsIfDelegateSetReceiveLibraryPayloadHasTrailingBytes() external {
        // Static three-word guard (_LEN_RECEIVE_LIBRARY).
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setReceiveLibrary.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibrary.selector,
                _withTrailingWord(abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0)))
            )
        );
    }

    function test_queue_revertsIfGatewaySetOutRateLimitsPayloadHasTrailingBytes() external {
        // Dynamic array canonical round-trip guard (RateLimitConfig[]).
        _expectActionInvalid(address(gateway), ILZBridgeGateway.setOutRateLimits.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.setOutRateLimits.selector,
                _withTrailingWord(_emptyRateConfigsEncoded())
            )
        );
    }

    function test_queue_revertsIfGatewayClearOutboundInFlightPayloadHasTrailingBytes() external {
        // Dynamic array canonical round-trip guard (uint32[]).
        _expectActionInvalid(address(gateway), ILZBridgeGateway.clearOutboundInFlight.selector);
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(
                ILZBridgeGateway.clearOutboundInFlight.selector,
                _withTrailingWord(_emptyEidsEncoded())
            )
        );
    }

    function test_queue_revertsIfDelegateSetEndpointConfigPayloadHasTrailingBytes() external {
        // Dynamic tuple canonical round-trip guard ((address, SetConfigParam[])).
        _expectActionInvalid(
            address(lzDelegate),
            ILZEndpointV2Authorized.setEndpointConfig.selector
        );
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setEndpointConfig.selector,
                _withTrailingWord(_emptyEndpointConfigEncoded())
            )
        );
    }

    function test_queue_revertsIfFacilitatorSetConfiguratorPayloadHasTrailingBytes() external {
        // Inline single-word guard in `_validateFacilitatorSubAction`, before the ERC-165
        // configurator check.
        _expectActionInvalid(address(facilitator), ILZCrossChainBridge.setConfigurator.selector);
        vm.prank(admin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setConfigurator.selector,
                _withTrailingWord(abi.encode(makeAddr("configuratorCandidate")))
            )
        );
    }
}
