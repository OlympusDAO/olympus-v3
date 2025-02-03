// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";
import {LayerZeroConstants} from "src/scripts/LayerZeroConstants.sol";

import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

contract BridgeScript is WithEnvironment {
    function bridge(
        string calldata fromChain_,
        string calldata toChain_,
        address to_,
        uint256 amount_
    ) external {
        _loadEnv(fromChain_);

        address ohmAddress = _envAddressNotZero("olympus.legacy.OHM");
        address bridgeAddress = _envAddressNotZero("olympus.policies.CrossChainBridge");

        // Approve spending of OHM by the bridge
        console2.log("Approving spending of OHM by the MINTR module");
        vm.startBroadcast();
        OlympusERC20Token(ohmAddress).approve(
            _envAddressNotZero("olympus.modules.OlympusMinter"),
            amount_
        );
        vm.stopBroadcast();

        // Look up the destination chain id
        uint16 dstChainId_ = LayerZeroConstants.getRemoteEndpointId(toChain_);

        // Estimate the send fee
        (uint256 nativeFee, ) = CrossChainBridge(bridgeAddress).estimateSendFee(
            dstChainId_,
            to_,
            amount_,
            bytes("")
        );

        console2.log("Bridging");
        console2.log("From chain:", fromChain_);
        console2.log("To chain:", toChain_);
        console2.log("To chain id:", dstChainId_);
        console2.log("Amount:", amount_);
        console2.log("To:", to_);
        console2.log("Native fee:", nativeFee);

        CrossChainBridge bridgeContract = CrossChainBridge(bridgeAddress);

        // Bridge
        vm.startBroadcast();
        bridgeContract.sendOhm{value: nativeFee}(dstChainId_, to_, amount_);
        vm.stopBroadcast();

        console2.log("Bridge complete");
    }
}
