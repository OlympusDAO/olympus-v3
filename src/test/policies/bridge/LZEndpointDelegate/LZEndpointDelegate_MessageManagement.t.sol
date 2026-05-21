// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev LZ V2 message management (skip, nilify, burn, clear) forwarded via LZEndpointDelegate.
///      Mock-based verification of the proxy: each external call must land on the LZ endpoint
///      with the gateway as the OApp argument and the caller-supplied recovery parameters,
///      plus role-gated access control. These inbound-channel management primitives are gated
///      directly to `bridge_admin` / `admin`. For end-to-end recovery scenarios against
///      the real mock EndpointV2 see the gateway-level recovery tests.
contract LZEndpointDelegateTests_MessageManagement is LZEndpointDelegateTestBase {
    bytes32 constant SENDER = bytes32(uint256(0x1234));
    uint64 constant NONCE = 7;
    bytes32 constant PAYLOAD_HASH = bytes32(uint256(0xABCDEF));

    // ========== SKIP ========== //

    function _mockAndExpectSkip() private {
        bytes memory call = abi.encodeWithSignature(
            "skip(address,uint32,bytes32,uint64)",
            gateway,
            CANONICAL_EID,
            SENDER,
            NONCE
        );
        vm.mockCall(lzEndpoint, call, bytes(""));
        vm.expectCall(lzEndpoint, call);
    }

    function test_skip_bridgeAdminCanCall() external {
        _mockAndExpectSkip();
        vm.prank(bridgeAdmin);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    function test_skip_adminCanCall() external {
        _mockAndExpectSkip();
        vm.prank(admin);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    function testFuzz_skip_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != bridgeAdmin && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    function test_skip_revertsWhenDisabled() external {
        _disableDelegate();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeAdmin);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    // ========== NILIFY ========== //

    function _mockAndExpectNilify() private {
        bytes memory call = abi.encodeWithSignature(
            "nilify(address,uint32,bytes32,uint64,bytes32)",
            gateway,
            CANONICAL_EID,
            SENDER,
            NONCE,
            PAYLOAD_HASH
        );
        vm.mockCall(lzEndpoint, call, bytes(""));
        vm.expectCall(lzEndpoint, call);
    }

    function test_nilify_bridgeAdminCanCall() external {
        _mockAndExpectNilify();
        vm.prank(bridgeAdmin);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function test_nilify_adminCanCall() external {
        _mockAndExpectNilify();
        vm.prank(admin);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function testFuzz_nilify_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != bridgeAdmin && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function test_nilify_revertsWhenDisabled() external {
        _disableDelegate();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeAdmin);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== BURN ========== //

    function _mockAndExpectBurn() private {
        bytes memory call = abi.encodeWithSignature(
            "burn(address,uint32,bytes32,uint64,bytes32)",
            gateway,
            CANONICAL_EID,
            SENDER,
            NONCE,
            PAYLOAD_HASH
        );
        vm.mockCall(lzEndpoint, call, bytes(""));
        vm.expectCall(lzEndpoint, call);
    }

    function test_burn_bridgeAdminCanCall() external {
        _mockAndExpectBurn();
        vm.prank(bridgeAdmin);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function test_burn_adminCanCall() external {
        _mockAndExpectBurn();
        vm.prank(admin);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function testFuzz_burn_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != bridgeAdmin && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function test_burn_revertsWhenDisabled() external {
        _disableDelegate();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeAdmin);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== CLEAR ========== //

    function _buildOrigin() private pure returns (Origin memory) {
        return Origin({srcEid: CANONICAL_EID, sender: SENDER, nonce: NONCE});
    }

    function _mockAndExpectClear(Origin memory origin, bytes32 guid, bytes memory message) private {
        bytes memory call = abi.encodeWithSignature(
            "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
            gateway,
            origin,
            guid,
            message
        );
        vm.mockCall(lzEndpoint, call, bytes(""));
        vm.expectCall(lzEndpoint, call);
    }

    function test_clear_bridgeAdminCanCall() external {
        Origin memory origin = _buildOrigin();
        bytes32 guid = bytes32(uint256(0x55));
        bytes memory message = hex"deadbeef";

        _mockAndExpectClear(origin, guid, message);
        vm.prank(bridgeAdmin);
        lzDelegate.clear(origin, guid, message);
    }

    function test_clear_adminCanCall() external {
        Origin memory origin = _buildOrigin();
        bytes32 guid = bytes32(uint256(0x55));
        bytes memory message = hex"deadbeef";

        _mockAndExpectClear(origin, guid, message);
        vm.prank(admin);
        lzDelegate.clear(origin, guid, message);
    }

    function testFuzz_clear_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != bridgeAdmin && caller_ != admin);

        Origin memory origin = _buildOrigin();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        lzDelegate.clear(origin, bytes32(0), bytes(""));
    }

    function test_clear_revertsWhenDisabled() external {
        _disableDelegate();

        Origin memory origin = _buildOrigin();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(bridgeAdmin);
        lzDelegate.clear(origin, bytes32(0), bytes(""));
    }
}
