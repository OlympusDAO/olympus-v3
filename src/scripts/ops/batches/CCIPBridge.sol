// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";

contract CCIPBridgeBatch is BatchScriptV2 {
    // TODOs
    // [ ] Declarative configuration of a bridge

    bytes32 public constant SOLANA_RECEIVER =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    function setTrustedRemoteEVM(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        address remoteBridgeAddress = _envAddressNotZero(
            remoteChain_,
            "olympus.periphery.CCIPCrossChainBridge"
        );

        // Set the trusted remote
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.setTrustedRemoteEVM.selector,
                remoteChainSelector,
                remoteBridgeAddress
            )
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }

    function setTrustedRemoteSolana(
        string calldata chain_,
        bool useDaoMS_,
        string calldata remoteChain_
    ) external setUp(chain_, useDaoMS_) {
        address bridgeAddress = _envAddressNotZero("olympus.periphery.CCIPCrossChainBridge");
        uint64 remoteChainSelector = uint64(
            _envUintNotZero(remoteChain_, "external.ccip.ChainSelector")
        );
        bytes32 remotePubKey = SOLANA_RECEIVER;

        // Set the trusted remote
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.setTrustedRemoteSVM.selector,
                remoteChainSelector,
                remotePubKey
            )
        );

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
