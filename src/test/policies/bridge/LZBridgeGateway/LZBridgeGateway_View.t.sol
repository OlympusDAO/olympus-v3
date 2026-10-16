// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";

/// @dev Public view function verification.
contract LZBridgeGatewayTests_View is LZBridgeGatewayTestBase {
    function test_allowInitializePath_validPeer() external view {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertTrue(gateway.allowInitializePath(origin), "Should allow valid peer");
    }

    function test_allowInitializePath_noPeer() external view {
        Origin memory origin = Origin({
            srcEid: uint32(42),
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertFalse(gateway.allowInitializePath(origin), "Should not allow unknown peer");
    }

    function test_allowInitializePath_clearedPeerRejectsZeroSender() external {
        // Clear peer so peers[NONCANONICAL_EID] == bytes32(0)
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        // origin.sender == bytes32(0) would match the cleared slot without the fix
        Origin memory origin = Origin({srcEid: NONCANONICAL_EID, sender: bytes32(0), nonce: 0});
        assertFalse(gateway.allowInitializePath(origin), "Cleared peer must not match zero sender");
    }

    function test_nextNonce_returnsZero() external view {
        assertEq(
            gateway.nextNonce(NONCANONICAL_EID, bytes32(0)),
            0,
            "Should return 0 (unordered messaging)"
        );
    }

    function test_LZ_ENDPOINT() external view {
        assertEq(
            gateway.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[0]),
            "LZ_ENDPOINT should match endpoint"
        );
    }

    function test_IS_CANONICAL() external view {
        assertTrue(gateway.IS_CANONICAL(), "Canonical gateway should return true");
        assertFalse(gateway2.IS_CANONICAL(), "Non-canonical gateway should return false");
    }

    function test_MINTR() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should match deployed module");
    }

    function test_ohm() external view {
        assertEq(gateway.ohm(), address(ohm), "OHM should match token address");
    }

    function test_bridgedSupply() external view {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be zero initially");
    }

    function test_MSG_BRIDGE_OHM() external view {
        assertEq(gateway.MSG_BRIDGE_OHM(), 1, "MSG_BRIDGE_OHM should be 1");
    }

    function test_peers() external view {
        assertEq(
            gateway.peers(NONCANONICAL_EID),
            LZConfigLib.addressToBytes32(address(gateway2)),
            "Peer should match non-canonical gateway"
        );
    }

    function test_isReceiveEnabled_defaultsFalse() external {
        LZBridgeGateway freshGateway = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            GRACE_SECONDS
        );
        assertFalse(freshGateway.isReceiveEnabled(), "isReceiveEnabled should default to false");
    }

    function test_isReceiveEnabled_returnsTrueAfterBridgeEnabling() external {
        LZBridgeGateway freshGateway = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            GRACE_SECONDS
        );
        kernel.executeAction(Actions.ActivatePolicy, address(freshGateway));

        assertFalse(freshGateway.isReceiveEnabled(), "Should be false before enable");

        vm.prank(admin);
        freshGateway.enable(bytes(""));

        assertTrue(freshGateway.isReceiveEnabled(), "isReceiveEnabled should be true after enable");
    }

    function test_sendable() external {
        // Configure outbound rate limit: 10_000e9 over 1 hour, overriding the default.
        uint256 limit = 10_000e9;
        uint32 window = 1 hours;
        _setOutRateLimit(gateway, NONCANONICAL_EID, limit, window);

        (uint256 inFlight, uint256 available) = gateway.sendable(NONCANONICAL_EID);
        assertEq(inFlight, 0, "No outbound amount should be in flight initially");
        assertEq(available, limit, "Full outbound limit should be available");
    }

    function test_receivable() external {
        // Configure inbound rate limit: 10_000e9 over 1 hour, overriding the default.
        uint256 limit = 10_000e9;
        uint32 window = 1 hours;
        _setInRateLimit(gateway, NONCANONICAL_EID, limit, window);

        (uint256 inFlight, uint256 available) = gateway.receivable(NONCANONICAL_EID);
        assertEq(inFlight, 0, "No inbound amount should be in flight initially");
        assertEq(available, limit, "Full inbound limit should be available");
    }

    function test_outRateLimits() external view {
        // Default rate limits are configured by the test base; raw getter returns them.
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway
            .outRateLimits(NONCANONICAL_EID);
        assertEq(inFlight, 0, "Initial outbound in-flight should be zero");
        assertEq(limit, DEFAULT_RATE_LIMIT, "Outbound limit should match the test base default");
        assertEq(window, DEFAULT_RATE_WINDOW, "Outbound window should match the test base default");
        assertGt(lastUpdated, 0, "lastUpdated should be set by the configuration call");
    }

    function test_inRateLimits() external view {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway.inRateLimits(
            NONCANONICAL_EID
        );
        assertEq(inFlight, 0, "Initial inbound in-flight should be zero");
        assertEq(limit, DEFAULT_RATE_LIMIT, "Inbound limit should match the test base default");
        assertEq(window, DEFAULT_RATE_WINDOW, "Inbound window should match the test base default");
        assertGt(lastUpdated, 0, "lastUpdated should be set by the configuration call");
    }

    function test_sendable_whenNonzeroInFlight() external {
        uint256 amount = 1_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);

        (uint256 inFlight, uint256 available) = gateway.sendable(NONCANONICAL_EID);
        assertEq(inFlight, amount, "Outbound in-flight should reflect the sent amount");
        assertEq(
            available,
            DEFAULT_RATE_LIMIT - amount,
            "Outbound available should decrease by the sent amount"
        );
    }

    function test_receivable_whenNonzeroInFlight() external {
        uint256 amount = 1_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);

        (uint256 inFlight, uint256 available) = gateway2.receivable(CANONICAL_EID);
        assertEq(inFlight, amount, "Inbound in-flight should reflect the received amount");
        assertEq(
            available,
            DEFAULT_RATE_LIMIT - amount,
            "Inbound available should decrease by the received amount"
        );
    }

    function test_outRateLimits_whenNonzeroInFlight() external {
        uint256 amount = 1_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);

        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway
            .outRateLimits(NONCANONICAL_EID);
        assertEq(inFlight, amount, "Outbound in-flight raw state should equal the sent amount");
        assertEq(limit, DEFAULT_RATE_LIMIT, "Outbound limit should be unchanged by the send");
        assertEq(window, DEFAULT_RATE_WINDOW, "Outbound window should be unchanged by the send");
        assertEq(
            lastUpdated,
            uint48(vm.getBlockTimestamp()),
            "lastUpdated should be the current timestamp"
        );
    }

    function test_inRateLimits_whenNonzeroInFlight() external {
        uint256 amount = 1_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);

        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway2
            .inRateLimits(CANONICAL_EID);
        assertEq(inFlight, amount, "Inbound in-flight raw state should equal the received amount");
        assertEq(limit, DEFAULT_RATE_LIMIT, "Inbound limit should be unchanged by the receive");
        assertEq(window, DEFAULT_RATE_WINDOW, "Inbound window should be unchanged by the receive");
        assertEq(
            lastUpdated,
            uint48(vm.getBlockTimestamp()),
            "lastUpdated should be the current timestamp"
        );
    }

    // ========= validateSetDelegate ========= //

    function test_validateSetDelegate_acceptsNonzero() external {
        gateway.validateSetDelegate(makeAddr("anyDelegate"));
    }

    function test_validateSetDelegate_revertsIfZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "delegate"
            )
        );
        gateway.validateSetDelegate(address(0));
    }

    // ========= validateIncreaseBridgedSupply ========= //

    function test_validateIncreaseBridgedSupply_acceptsNonzeroOnCanonical() external {
        gateway.validateIncreaseBridgedSupply(1);
    }

    function test_validateIncreaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector);
        gateway2.validateIncreaseBridgedSupply(1);
    }

    function test_validateIncreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        gateway.validateIncreaseBridgedSupply(0);
    }

    // ========= validateDecreaseBridgedSupply ========= //

    function test_validateDecreaseBridgedSupply_acceptsAmountWithinSupply() external {
        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(100e9);

        gateway.validateDecreaseBridgedSupply(50e9);
    }

    function test_validateDecreaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector);
        gateway2.validateDecreaseBridgedSupply(1);
    }

    function test_validateDecreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        gateway.validateDecreaseBridgedSupply(0);
    }

    function test_validateDecreaseBridgedSupply_revertsIfUnderflow() external {
        // Supply is zero in the canonical test base; any positive amount must underflow
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                7
            )
        );
        gateway.validateDecreaseBridgedSupply(7);
    }
}
