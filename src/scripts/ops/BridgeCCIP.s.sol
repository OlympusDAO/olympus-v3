// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {Base58} from "@base58-solidity-1.0.3/Base58.sol";

import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

contract BridgeCCIPScript is WithEnvironment {
    function _getSVMAddress(string memory to_) internal pure returns (bytes32) {
        bytes memory toBytes = Base58.decodeFromString(to_);
        if (toBytes.length != 32) {
            // solhint-disable-next-line gas-custom-errors
            revert("Invalid address length");
        }

        return bytes32(toBytes);
    }

    function bridgeToSVM(string calldata toChain_, string calldata to_, uint256 amount_) external {
        string memory fromChain = ChainUtils._getChainName(block.chainid);
        _loadEnv(fromChain);

        // Validate that the destination chain is an SVM chain
        if (!ChainUtils._isSVMChain(toChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("Destination chain is not an SVM chain");
        }

        address ohmAddress = _envAddressNotZero("olympus.legacy.OHM");
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 dstChainId = uint64(_envUintNotZero(toChain_, "external.ccip.ChainSelector"));
        bytes32 toAddress = _getSVMAddress(to_);

        // Approve spending of OHM by the bridge
        console2.log("Approving spending of OHM by the bridge");
        vm.startBroadcast();
        OlympusERC20Token(ohmAddress).approve(bridgeAddress, amount_);
        vm.stopBroadcast();

        // Estimate the send fee
        ICCIPCrossChainBridge bridgeContract = ICCIPCrossChainBridge(bridgeAddress);
        uint256 nativeFee = bridgeContract.getFeeSVM(dstChainId, toAddress, amount_);

        console2.log("Bridging");
        console2.log("From chain:", chain);
        console2.log("To chain:", toChain_);
        console2.log("To chain id:", dstChainId);
        console2.log("Amount:", amount_);
        console2.log("To:", to_);
        console2.log("Native fee:", nativeFee);

        // Bridge
        vm.startBroadcast();
        bytes32 messageId = bridgeContract.sendToSVM{value: nativeFee}(
            dstChainId,
            toAddress,
            amount_
        );
        console2.log("Message ID:", vm.toString(messageId));
        vm.stopBroadcast();

        console2.log("Bridge complete");
    }

    function bridgeToEVM(string calldata toChain_, address to_, uint256 amount_) external {
        string memory fromChain = ChainUtils._getChainName(block.chainid);
        _loadEnv(fromChain);

        // Validate that the destination chain is an EVM chain
        if (ChainUtils._isSVMChain(toChain_)) {
            // solhint-disable-next-line gas-custom-errors
            revert("Destination chain is not an EVM chain");
        }

        address ohmAddress = _envAddressNotZero("olympus.legacy.OHM");
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 dstChainId = uint64(_envUintNotZero(toChain_, "external.ccip.ChainSelector"));

        // Approve spending of OHM by the bridge
        console2.log("Approving spending of OHM by the bridge");
        vm.startBroadcast();
        OlympusERC20Token(ohmAddress).approve(bridgeAddress, amount_);
        vm.stopBroadcast();

        // Estimate the send fee
        ICCIPCrossChainBridge bridgeContract = ICCIPCrossChainBridge(bridgeAddress);
        uint256 nativeFee = bridgeContract.getFeeEVM(dstChainId, to_, amount_);

        console2.log("Bridging");
        console2.log("From chain:", chain);
        console2.log("To chain:", toChain_);
        console2.log("To chain id:", dstChainId);
        console2.log("Amount:", amount_);
        console2.log("To:", to_);
        console2.log("Native fee:", nativeFee);

        // Bridge
        vm.startBroadcast();
        bytes32 messageId = bridgeContract.sendToEVM{value: nativeFee}(dstChainId, to_, amount_);
        console2.log("Message ID:", vm.toString(messageId));
        vm.stopBroadcast();

        console2.log("Bridge complete");
    }
}
