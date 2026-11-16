// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

contract LZCrossChainBridgeTests_EstimateSendFee is LZCrossChainBridgeTestBase {
    function test_estimateSendFee_proxiesToGateway() external view {
        // Bridge estimate should match gateway estimate
        MessagingFee memory bridgeFee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, 1000e9);
        MessagingFee memory gatewayFee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1000e9,
            bytes("")
        );

        assertEq(bridgeFee.nativeFee, gatewayFee.nativeFee, "Native fee should match gateway");
        assertEq(bridgeFee.lzTokenFee, gatewayFee.lzTokenFee, "LZ token fee should match gateway");
    }
}
