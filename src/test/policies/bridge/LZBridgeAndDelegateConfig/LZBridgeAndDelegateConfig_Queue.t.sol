// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @dev Queue-time validation for every `queue*` entry point on `LZBridgeAndDelegateConfig`:
///      proposer-role gates, payload shape, and the target-side `validate*` mirrors. Each
///      function gets a per-role positive test for every role accepted by its gate, plus a
///      `testFuzz_*_revertsIfNot*` fuzz check that any other caller is rejected.
contract LZBridgeAndDelegateConfigTests_Queue is LZBridgeAndDelegateConfigTestBase {
    // ========== HELPERS ========== //

    /// @dev Builds a single-entry outbound/inbound rate-limit configuration array.
    function _rateConfigs()
        internal
        view
        returns (IOffsettingRateLimiter.RateLimitConfig[] memory cfg)
    {
        cfg = new IOffsettingRateLimiter.RateLimitConfig[](1);
        cfg[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 1e9,
            window: 3600
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

    /// @dev Asserts the standard `IPolicyAdmin.NotAuthorised` revert returned by both the
    ///      `bridge_admin`-or-`admin` and the rate-limiter-class proposer gates.
    function _expectNotAuthorized() internal {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
    }

    /// @dev Asserts the strict `ROLES_RequireRole(admin)` revert returned by the admin-only
    ///      proposer gate.
    function _expectAdminRole() internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
    }

    /// @dev Seeds the gateway with bridged supply so that a positive
    ///      `queueDecreaseBridgedSupply` payload does not trip the queue-time underflow guard
    ///      before the role check is exercised.
    function _seedBridgedSupply(uint256 amount_) internal {
        vm.prank(address(config));
        gateway.increaseBridgedSupply(amount_);
    }

    // ========== queueSetEndpointDelegate (gateway setDelegate) ========== //

    function test_queueSetEndpointDelegate_admin() external {
        vm.prank(admin);
        config.queueSetEndpointDelegate(makeAddr("delegateCandidate"));
    }

    function test_queueSetEndpointDelegate_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetEndpointDelegate(makeAddr("delegateCandidate"));
    }

    function testFuzz_queueSetEndpointDelegate_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetEndpointDelegate(makeAddr("delegateCandidate"));
    }

    function test_queueSetEndpointDelegate_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "delegate"
            )
        );
        vm.prank(bridgeAdmin);
        config.queueSetEndpointDelegate(address(0));
    }

    // ========== queueIncreaseBridgedSupply ========== //

    function test_queueIncreaseBridgedSupply_admin() external {
        vm.prank(admin);
        config.queueIncreaseBridgedSupply(1);
    }

    function test_queueIncreaseBridgedSupply_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueIncreaseBridgedSupply(1);
    }

    function testFuzz_queueIncreaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueIncreaseBridgedSupply(1);
    }

    function test_queueIncreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queueIncreaseBridgedSupply(0);
    }

    // ========== queueDecreaseBridgedSupply ========== //

    function test_queueDecreaseBridgedSupply_admin() external {
        _seedBridgedSupply(100);

        vm.prank(admin);
        config.queueDecreaseBridgedSupply(1);
    }

    function test_queueDecreaseBridgedSupply_bridgeAdmin() external {
        _seedBridgedSupply(100);

        vm.prank(bridgeAdmin);
        config.queueDecreaseBridgedSupply(1);
    }

    function testFuzz_queueDecreaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueDecreaseBridgedSupply(1);
    }

    function test_queueDecreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        config.queueDecreaseBridgedSupply(0);
    }

    function test_queueDecreaseBridgedSupply_revertsIfUnderflow() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                5
            )
        );
        vm.prank(bridgeAdmin);
        config.queueDecreaseBridgedSupply(5);
    }

    // ========== queueSetGatewayGracePeriod ========== //

    function test_queueSetGatewayGracePeriod_admin() external {
        vm.prank(admin);
        config.queueSetGatewayGracePeriod(1);
    }

    function test_queueSetGatewayGracePeriod_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetGatewayGracePeriod(1);
    }

    function testFuzz_queueSetGatewayGracePeriod_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetGatewayGracePeriod(1);
    }

    function test_queueSetGatewayGracePeriod_revertsIfZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queueSetGatewayGracePeriod(0);
    }

    // ========== queueSetOutRateLimits ========== //

    function test_queueSetOutRateLimits_admin() external {
        vm.prank(admin);
        config.queueSetOutRateLimits(_rateConfigs());
    }

    function test_queueSetOutRateLimits_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetOutRateLimits(_rateConfigs());
    }

    function test_queueSetOutRateLimits_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queueSetOutRateLimits(_rateConfigs());
    }

    function testFuzz_queueSetOutRateLimits_revertsIfNotRateLimiterClass(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetOutRateLimits(_rateConfigs());
    }

    // ========== queueSetInRateLimits ========== //

    function test_queueSetInRateLimits_admin() external {
        vm.prank(admin);
        config.queueSetInRateLimits(_rateConfigs());
    }

    function test_queueSetInRateLimits_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetInRateLimits(_rateConfigs());
    }

    function test_queueSetInRateLimits_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queueSetInRateLimits(_rateConfigs());
    }

    function testFuzz_queueSetInRateLimits_revertsIfNotRateLimiterClass(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetInRateLimits(_rateConfigs());
    }

    // ========== queueClearOutboundInFlight ========== //

    function test_queueClearOutboundInFlight_admin() external {
        vm.prank(admin);
        config.queueClearOutboundInFlight(_eidList());
    }

    function test_queueClearOutboundInFlight_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueClearOutboundInFlight(_eidList());
    }

    function test_queueClearOutboundInFlight_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queueClearOutboundInFlight(_eidList());
    }

    function testFuzz_queueClearOutboundInFlight_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueClearOutboundInFlight(_eidList());
    }

    // ========== queueClearInboundInFlight ========== //

    function test_queueClearInboundInFlight_admin() external {
        vm.prank(admin);
        config.queueClearInboundInFlight(_eidList());
    }

    function test_queueClearInboundInFlight_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueClearInboundInFlight(_eidList());
    }

    function test_queueClearInboundInFlight_bridgeRateLimiter() external {
        vm.prank(bridgeRateLimiter);
        config.queueClearInboundInFlight(_eidList());
    }

    function testFuzz_queueClearInboundInFlight_revertsIfNotRateLimiterClass(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueClearInboundInFlight(_eidList());
    }

    // ========== queueSetSendLibrary ========== //

    function test_queueSetSendLibrary_admin() external {
        vm.prank(admin);
        config.queueSetSendLibrary(NONCANONICAL_EID, makeAddr("sendLib"));
    }

    function test_queueSetSendLibrary_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetSendLibrary(NONCANONICAL_EID, makeAddr("sendLib"));
    }

    function testFuzz_queueSetSendLibrary_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetSendLibrary(NONCANONICAL_EID, makeAddr("sendLib"));
    }

    // ========== queueSetReceiveLibrary ========== //

    function test_queueSetReceiveLibrary_admin() external {
        vm.prank(admin);
        config.queueSetReceiveLibrary(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    function test_queueSetReceiveLibrary_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetReceiveLibrary(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    function testFuzz_queueSetReceiveLibrary_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetReceiveLibrary(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    // ========== queueSetReceiveLibraryTimeout ========== //

    function test_queueSetReceiveLibraryTimeout_admin() external {
        vm.prank(admin);
        config.queueSetReceiveLibraryTimeout(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    function test_queueSetReceiveLibraryTimeout_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetReceiveLibraryTimeout(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    function testFuzz_queueSetReceiveLibraryTimeout_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetReceiveLibraryTimeout(NONCANONICAL_EID, makeAddr("recvLib"), 0);
    }

    // ========== queueSetEndpointConfig ========== //

    function test_queueSetEndpointConfig_admin() external {
        vm.prank(admin);
        config.queueSetEndpointConfig(makeAddr("lib"), _emptyConfigParams());
    }

    function test_queueSetEndpointConfig_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetEndpointConfig(makeAddr("lib"), _emptyConfigParams());
    }

    function testFuzz_queueSetEndpointConfig_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetEndpointConfig(makeAddr("lib"), _emptyConfigParams());
    }

    // ========== queueSkip ========== //

    function test_queueSkip_admin() external {
        vm.prank(admin);
        config.queueSkip(NONCANONICAL_EID, bytes32(uint256(1)), 1);
    }

    function test_queueSkip_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSkip(NONCANONICAL_EID, bytes32(uint256(1)), 1);
    }

    function testFuzz_queueSkip_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSkip(NONCANONICAL_EID, bytes32(uint256(1)), 1);
    }

    // ========== queueNilify ========== //

    function test_queueNilify_admin() external {
        vm.prank(admin);
        config.queueNilify(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    function test_queueNilify_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueNilify(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    function testFuzz_queueNilify_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueNilify(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    // ========== queueBurn ========== //

    function test_queueBurn_admin() external {
        vm.prank(admin);
        config.queueBurn(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    function test_queueBurn_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueBurn(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    function testFuzz_queueBurn_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueBurn(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(2)));
    }

    // ========== queueClear ========== //

    function _clearOrigin() internal pure returns (Origin memory origin) {
        origin = Origin({srcEid: NONCANONICAL_EID, sender: bytes32(uint256(1)), nonce: 1});
    }

    function test_queueClear_admin() external {
        vm.prank(admin);
        config.queueClear(_clearOrigin(), bytes32(uint256(2)), bytes(""));
    }

    function test_queueClear_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueClear(_clearOrigin(), bytes32(uint256(2)), bytes(""));
    }

    function testFuzz_queueClear_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueClear(_clearOrigin(), bytes32(uint256(2)), bytes(""));
    }

    // ========== queueSetFacilitatorGateway ========== //

    function test_queueSetFacilitatorGateway_admin() external {
        vm.prank(admin);
        config.queueSetFacilitatorGateway(makeAddr("gatewayCandidate"));
    }

    function test_queueSetFacilitatorGateway_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetFacilitatorGateway(makeAddr("gatewayCandidate"));
    }

    function testFuzz_queueSetFacilitatorGateway_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetFacilitatorGateway(makeAddr("gatewayCandidate"));
    }

    function test_queueSetFacilitatorGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        vm.prank(bridgeAdmin);
        config.queueSetFacilitatorGateway(address(0));
    }

    // ========== queueSetFacilitatorReEnabler ========== //

    function test_queueSetFacilitatorReEnabler_admin() external {
        vm.prank(admin);
        config.queueSetFacilitatorReEnabler(makeAddr("reEnablerCandidate"));
    }

    function test_queueSetFacilitatorReEnabler_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetFacilitatorReEnabler(makeAddr("reEnablerCandidate"));
    }

    function testFuzz_queueSetFacilitatorReEnabler_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetFacilitatorReEnabler(makeAddr("reEnablerCandidate"));
    }

    // ========== queueSetFacilitatorGracePeriod ========== //

    function test_queueSetFacilitatorGracePeriod_admin() external {
        vm.prank(admin);
        config.queueSetFacilitatorGracePeriod(1);
    }

    function test_queueSetFacilitatorGracePeriod_bridgeAdmin() external {
        vm.prank(bridgeAdmin);
        config.queueSetFacilitatorGracePeriod(1);
    }

    function testFuzz_queueSetFacilitatorGracePeriod_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        _expectNotAuthorized();
        vm.prank(caller_);
        config.queueSetFacilitatorGracePeriod(1);
    }

    function test_queueSetFacilitatorGracePeriod_revertsIfZero() external {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(bridgeAdmin);
        config.queueSetFacilitatorGracePeriod(0);
    }

    // ========== queueSetFacilitatorConfigurator ========== //

    function test_queueSetFacilitatorConfigurator_admin() external {
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        vm.prank(admin);
        config.queueSetFacilitatorConfigurator(address(secondary));
    }

    function testFuzz_queueSetFacilitatorConfigurator_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);
        LZBridgeAndDelegateConfig secondary = _deploySecondaryConfig();

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetFacilitatorConfigurator(address(secondary));
    }

    function test_queueSetFacilitatorConfigurator_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        vm.prank(admin);
        config.queueSetFacilitatorConfigurator(address(0));
    }

    function test_queueSetFacilitatorConfigurator_revertsIfErc165Rejects() external {
        // The gateway is not an `ILZBridgeAndDelegateConfig`; its ERC-165 will return false
        // for that interface ID, so the configurator validator must reject it.
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidConfigurator.selector,
                address(gateway)
            )
        );
        vm.prank(admin);
        config.queueSetFacilitatorConfigurator(address(gateway));
    }

    // ========== queueSetTargetGateway ========== //

    function test_queueSetTargetGateway_admin() external {
        vm.prank(admin);
        config.queueSetTargetGateway(makeAddr("newGateway"));
    }

    function testFuzz_queueSetTargetGateway_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetGateway(makeAddr("newGateway"));
    }

    function test_queueSetTargetGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "gateway"
            )
        );
        vm.prank(admin);
        config.queueSetTargetGateway(address(0));
    }

    // ========== queueSetTargetDelegate ========== //

    function test_queueSetTargetDelegate_admin() external {
        vm.prank(admin);
        config.queueSetTargetDelegate(makeAddr("newDelegate"));
    }

    function testFuzz_queueSetTargetDelegate_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetDelegate(makeAddr("newDelegate"));
    }

    function test_queueSetTargetDelegate_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "delegate"
            )
        );
        vm.prank(admin);
        config.queueSetTargetDelegate(address(0));
    }

    // ========== queueSetTargetFacilitator ========== //

    function test_queueSetTargetFacilitator_admin() external {
        vm.prank(admin);
        config.queueSetTargetFacilitator(makeAddr("newFacilitator"));
    }

    function testFuzz_queueSetTargetFacilitator_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetFacilitator(makeAddr("newFacilitator"));
    }

    function test_queueSetTargetFacilitator_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "facilitator"
            )
        );
        vm.prank(admin);
        config.queueSetTargetFacilitator(address(0));
    }

    // ========== queueSetTimelockDelay ========== //

    function test_queueSetTimelockDelay_admin() external {
        vm.prank(admin);
        config.queueSetTimelockDelay(INITIAL_TIMELOCK_DELAY);
    }

    function testFuzz_queueSetTimelockDelay_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTimelockDelay(INITIAL_TIMELOCK_DELAY);
    }

    function test_queueSetTimelockDelay_revertsIfDelayBelowMin() external {
        uint48 belowMin = uint48(config.MIN_TIMELOCK_DELAY()) - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                belowMin,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        config.queueSetTimelockDelay(belowMin);
    }

    function test_queueSetTimelockDelay_revertsIfDelayAboveMax() external {
        uint48 aboveMax = uint48(config.MAX_TIMELOCK_DELAY()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                aboveMax,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        config.queueSetTimelockDelay(aboveMax);
    }
}
