// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
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

    function _clearOrigin() internal pure returns (Origin memory origin) {
        origin = Origin({srcEid: NONCANONICAL_EID, sender: bytes32(uint256(1)), nonce: 1});
    }

    // ========== BATCH SEMANTICS ========== //

    function test_queue_appliesAllSubActions() external {
        uint256 limit = 9_000e9;
        uint32 window = 4 hours;

        vm.prank(bridgeRateLimiter);
        uint64 actionId = config.queue(_gatewayRateBatch(limit, window));

        _warpPastTimelock();
        config.executeQueuedAction(actionId);

        (, uint256 outLimit, uint32 outWindow, ) = gateway.outRateLimits(NONCANONICAL_EID);
        (, uint256 inLimit, uint32 inWindow, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(outLimit, limit, "Outbound limit applied");
        assertEq(outWindow, window, "Outbound window applied");
        assertEq(inLimit, limit, "Inbound limit applied");
        assertEq(inWindow, window, "Inbound window applied");
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

    function test_queue_gatewaySetDelegate_admin() external {
        vm.prank(admin);
        config.queue(
            _gw(ILZBridgeGateway.setDelegate.selector, abi.encode(makeAddr("delegateCandidate")))
        );
    }

    function test_queue_gatewaySetDelegate_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _gw(ILZBridgeGateway.setDelegate.selector, abi.encode(makeAddr("delegateCandidate")))
        );
    }

    function testFuzz_queue_gatewaySetDelegate_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _gw(ILZBridgeGateway.setDelegate.selector, abi.encode(makeAddr("delegateCandidate")))
        );
    }

    function test_queue_gatewaySetDelegate_revertsIfZeroAddress() external {
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

    function test_queue_gatewayIncreaseBridgedSupply_admin() external {
        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_gatewayIncreaseBridgedSupply_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function testFuzz_queue_gatewayIncreaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_gatewayIncreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.increaseBridgedSupply.selector, abi.encode(uint256(0))));
    }

    // ========== gateway: decreaseBridgedSupply ========== //

    function test_queue_gatewayDecreaseBridgedSupply_admin() external {
        _seedBridgedSupply(100);

        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_gatewayDecreaseBridgedSupply_bridgeAdmin() external {
        _seedBridgedSupply(100);

        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function testFuzz_queue_gatewayDecreaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(1))));
    }

    function test_queue_gatewayDecreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.decreaseBridgedSupply.selector, abi.encode(uint256(0))));
    }

    function test_queue_gatewayDecreaseBridgedSupply_revertsIfUnderflow() external {
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

    function test_queue_gatewaySetGracePeriod_admin() external {
        vm.prank(admin);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_gatewaySetGracePeriod_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function testFuzz_queue_gatewaySetGracePeriod_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_gatewaySetGracePeriod_revertsIfZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_gw(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(0))));
    }

    // ========== gateway: setOutRateLimits ========== //

    function test_queue_gatewaySetOutRateLimits_admin() external {
        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function test_queue_gatewaySetOutRateLimits_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function test_queue_gatewaySetOutRateLimits_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function testFuzz_queue_gatewaySetOutRateLimits_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.setOutRateLimits.selector, abi.encode(_rateConfigs())));
    }

    // ========== gateway: setInRateLimits ========== //

    function test_queue_gatewaySetInRateLimits_admin() external {
        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function test_queue_gatewaySetInRateLimits_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function test_queue_gatewaySetInRateLimits_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, abi.encode(_rateConfigs())));
    }

    function testFuzz_queue_gatewaySetInRateLimits_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.setInRateLimits.selector, abi.encode(_rateConfigs())));
    }

    // ========== gateway: clearOutboundInFlight ========== //

    function test_queue_gatewayClearOutboundInFlight_admin() external {
        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, abi.encode(_eidList())));
    }

    function test_queue_gatewayClearOutboundInFlight_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, abi.encode(_eidList())));
    }

    function test_queue_gatewayClearOutboundInFlight_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, abi.encode(_eidList())));
    }

    function testFuzz_queue_gatewayClearOutboundInFlight_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.clearOutboundInFlight.selector, abi.encode(_eidList())));
    }

    // ========== gateway: clearInboundInFlight ========== //

    function test_queue_gatewayClearInboundInFlight_admin() external {
        vm.prank(admin);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, abi.encode(_eidList())));
    }

    function test_queue_gatewayClearInboundInFlight_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, abi.encode(_eidList())));
    }

    function test_queue_gatewayClearInboundInFlight_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, abi.encode(_eidList())));
    }

    function testFuzz_queue_gatewayClearInboundInFlight_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_gw(ILZBridgeGateway.clearInboundInFlight.selector, abi.encode(_eidList())));
    }

    // ========== delegate: setSendLibrary ========== //

    function test_queue_delegateSetSendLibrary_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setSendLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("sendLib"))
            )
        );
    }

    function test_queue_delegateSetSendLibrary_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setSendLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("sendLib"))
            )
        );
    }

    function testFuzz_queue_delegateSetSendLibrary_revertsIfNotBridgeAdminOrAdmin(
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

    function test_queue_delegateSetReceiveLibrary_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    function test_queue_delegateSetReceiveLibrary_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibrary.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    function testFuzz_queue_delegateSetReceiveLibrary_revertsIfNotBridgeAdminOrAdmin(
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

    function test_queue_delegateSetReceiveLibraryTimeout_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    function test_queue_delegateSetReceiveLibraryTimeout_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector,
                abi.encode(NONCANONICAL_EID, makeAddr("recvLib"), uint256(0))
            )
        );
    }

    function testFuzz_queue_delegateSetReceiveLibraryTimeout_revertsIfNotBridgeAdminOrAdmin(
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

    function test_queue_delegateSetEndpointConfig_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setEndpointConfig.selector,
                abi.encode(makeAddr("lib"), _emptyConfigParams())
            )
        );
    }

    function test_queue_delegateSetEndpointConfig_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.setEndpointConfig.selector,
                abi.encode(makeAddr("lib"), _emptyConfigParams())
            )
        );
    }

    function testFuzz_queue_delegateSetEndpointConfig_revertsIfNotBridgeAdminOrAdmin(
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

    // ========== delegate: skip ========== //

    function test_queue_delegateSkip_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.skip.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1))
            )
        );
    }

    function test_queue_delegateSkip_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.skip.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1))
            )
        );
    }

    function testFuzz_queue_delegateSkip_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.skip.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1))
            )
        );
    }

    // ========== delegate: nilify ========== //

    function test_queue_delegateNilify_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.nilify.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    function test_queue_delegateNilify_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.nilify.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    function testFuzz_queue_delegateNilify_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.nilify.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    // ========== delegate: burn ========== //

    function test_queue_delegateBurn_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.burn.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    function test_queue_delegateBurn_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.burn.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    function testFuzz_queue_delegateBurn_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.burn.selector,
                abi.encode(NONCANONICAL_EID, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
            )
        );
    }

    // ========== delegate: clear ========== //

    function test_queue_delegateClear_admin() external {
        vm.prank(admin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.clear.selector,
                abi.encode(_clearOrigin(), bytes32(uint256(2)), bytes(""))
            )
        );
    }

    function test_queue_delegateClear_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.clear.selector,
                abi.encode(_clearOrigin(), bytes32(uint256(2)), bytes(""))
            )
        );
    }

    function testFuzz_queue_delegateClear_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _dg(
                ILZEndpointV2Authorized.clear.selector,
                abi.encode(_clearOrigin(), bytes32(uint256(2)), bytes(""))
            )
        );
    }

    // ========== facilitator: setGateway ========== //

    function test_queue_facilitatorSetGateway_admin() external {
        vm.prank(admin);
        config.queue(
            _fac(ILZCrossChainBridge.setGateway.selector, abi.encode(makeAddr("gatewayCandidate")))
        );
    }

    function test_queue_facilitatorSetGateway_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _fac(ILZCrossChainBridge.setGateway.selector, abi.encode(makeAddr("gatewayCandidate")))
        );
    }

    function testFuzz_queue_facilitatorSetGateway_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(
            _fac(ILZCrossChainBridge.setGateway.selector, abi.encode(makeAddr("gatewayCandidate")))
        );
    }

    function test_queue_facilitatorSetGateway_revertsIfZeroAddress() external {
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

    function test_queue_facilitatorSetReEnabler_admin() external {
        vm.prank(admin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setReEnabler.selector,
                abi.encode(makeAddr("reEnablerCandidate"))
            )
        );
    }

    function test_queue_facilitatorSetReEnabler_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(
            _fac(
                ILZCrossChainBridge.setReEnabler.selector,
                abi.encode(makeAddr("reEnablerCandidate"))
            )
        );
    }

    function testFuzz_queue_facilitatorSetReEnabler_revertsIfNotBridgeAdminOrAdmin(
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

    function test_queue_facilitatorSetGracePeriod_admin() external {
        vm.prank(admin);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_facilitatorSetGracePeriod_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function testFuzz_queue_facilitatorSetGracePeriod_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(1))));
    }

    function test_queue_facilitatorSetGracePeriod_revertsIfZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queue(_fac(IGracePeriod.setGracePeriod.selector, abi.encode(uint32(0))));
    }

    // ========== facilitator: setConfigurator ========== //

    function test_queue_facilitatorSetConfigurator_admin() external {
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        vm.prank(admin);
        config.queue(
            _fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(secondary)))
        );
    }

    function testFuzz_queue_facilitatorSetConfigurator_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        _expectAdminRole();
        vm.prank(caller_);
        config.queue(
            _fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(secondary)))
        );
    }

    function test_queue_facilitatorSetConfigurator_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        vm.prank(admin);
        config.queue(_fac(ILZCrossChainBridge.setConfigurator.selector, abi.encode(address(0))));
    }

    function test_queue_facilitatorSetConfigurator_revertsIfErc165Rejects() external {
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
}
