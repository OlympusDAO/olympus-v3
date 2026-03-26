// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

/// @dev Enforced + extra option merging.
contract LZBridgeGatewayTests_CombineOptions is LZBridgeGatewayTestBase {
    function test_combineOptions_enforcedOnly() external view {
        // Enforced options are set for NONCANONICAL_EID, MSG_BRIDGE_OHM in setUp
        bytes memory combined = gateway.combineOptions(
            NONCANONICAL_EID,
            gateway.MSG_BRIDGE_OHM(),
            bytes("")
        );
        assertEq(combined, DEFAULT_OPTIONS, "Should return enforced options");
    }

    function test_combineOptions_extraOnly() external view {
        // No enforced options for eid=42
        bytes memory extra = DEFAULT_OPTIONS;
        bytes memory combined = gateway.combineOptions(uint32(42), uint16(1), extra);
        assertEq(combined, extra, "Should return extra options when no enforced");
    }

    function test_combineOptions_bothCombined() external view {
        // Extra Type 3 options with 100k gas lzReceive
        bytes memory extra = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(100_000)
        );
        bytes memory combined = gateway.combineOptions(
            NONCANONICAL_EID,
            gateway.MSG_BRIDGE_OHM(),
            extra
        );
        // Should be enforced + extra[2:]
        bytes memory expected = bytes.concat(
            DEFAULT_OPTIONS,
            abi.encodePacked(uint8(1), uint16(17), uint8(1), uint128(100_000))
        );
        assertEq(combined, expected, "Should combine enforced + extra");
    }

    function test_combineOptions_noEnforcedNoExtra_returnsEmpty() external view {
        // eid=42 has no enforced options configured, empty extra
        bytes memory combined = gateway.combineOptions(uint32(42), uint16(1), bytes(""));
        assertEq(combined.length, 0, "Should return empty bytes");
    }

    function test_combineOptions_revertsIfExtraNotType3() external {
        bytes memory notType3 = abi.encodePacked(uint16(1), uint128(200_000));

        // combineOptions is a view function, so use try/catch via low-level call
        (bool success, bytes memory returnData) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.combineOptions.selector,
                NONCANONICAL_EID,
                gateway.MSG_BRIDGE_OHM(),
                notType3
            )
        );
        assertFalse(success, "Should revert with invalid options");
        assertEq(
            bytes4(returnData),
            ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
            "Should revert with InvalidOptions"
        );
    }

    function test_combineOptions_revertsIfExtraIs1Byte() external {
        bytes memory oneByte = abi.encodePacked(uint8(3));

        (bool success, bytes memory returnData) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.combineOptions.selector,
                NONCANONICAL_EID,
                gateway.MSG_BRIDGE_OHM(),
                oneByte
            )
        );
        assertFalse(success, "Should revert with 1-byte extra options");
        assertEq(
            bytes4(returnData),
            ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
            "Should revert with InvalidOptions"
        );
    }
}
