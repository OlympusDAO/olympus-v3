// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

/// @dev Fee quoting for cross-chain sends.
contract LZBridgeGatewayTests_EstimateSendFee is LZBridgeGatewayTestBase {
    function test_estimateSendFee() external view {
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1000e9,
            bytes("")
        );
        assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
    }

    function test_estimateSendFee_revertsIfZeroRecipient() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        gateway.estimateSendFee(NONCANONICAL_EID, address(0), 1000e9, bytes(""));
    }

    function test_estimateSendFee_revertsIfNoPeer() external {
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_NoPeer.selector,
                NONCANONICAL_EID
            )
        );
        gateway.estimateSendFee(NONCANONICAL_EID, recipient, 1000e9, bytes(""));
    }
}
