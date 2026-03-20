// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

/// @title LZBridgeBatchScript
/// @notice Abstract base for LZ bridge batch scripts.
///         Contains shared constants, structs, and helpers for LZ V2 configuration.
///         All LZ endpoint config is done through the gateway's ILZEndpointV2Admin
///         functions, which are gated by bridge_admin role.
abstract contract LZBridgeBatchScript is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeBatchScript_UnsupportedChain();

    // =========== CONSTANTS =========== //

    /// @dev Number of remote chains per deployment (each chain has 3 remotes).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

    // TODO: Set before execution
    uint256 internal constant INITIAL_BRIDGED_SUPPLY = 0;

    // =========== LZ CONFIGURATION HELPERS =========== //

    /// @notice Configures LZ libraries and ULN/Executor config for all remote chains
    ///         via the gateway's ILZEndpointV2Admin functions.
    function _configureLZ(LZBridgeGateway gateway_) internal {
        uint32[] memory remoteEids = _getRemoteEids();
        address sendLib = _getSendUln302();
        address recvLib = _getRecvUln302();
        address[] memory dvns = _getDVNs();
        uint64 localConf = _outboundConfirmations();
        address gatewayAddr = address(gateway_);

        console2.log("\nConfiguring LZ - sendLib:", sendLib, "recvLib:", recvLib);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            uint32 remoteEid = remoteEids[i];
            console2.log("  Configuring remote EID:", remoteEid);

            // Pin send library via gateway
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setSendLibrary, (remoteEid, sendLib))
            );

            // Pin receive library via gateway
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setReceiveLibrary, (remoteEid, recvLib, 0))
            );

            // Send ULN + Executor config
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(localConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig()
            });
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (sendLib, sendParams))
            );

            // Receive ULN config (inbound = remote chain's outbound confirmations)
            uint64 remoteConf = LZConfigLib.outboundConfirmationsForEid(remoteEid);
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConf, dvns)
            });
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (recvLib, recvParams))
            );
        }
    }

    /// @notice Sets peers for all remote chains from env.json addresses.
    function _setPeers(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        string[_REMOTE_CHAIN_COUNT] memory remoteChains = _getRemoteChainNames();
        uint32[] memory remoteEids = _getRemoteEids();

        console2.log("\nSetting peers");

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            address remoteGateway = _envAddressNotZero(
                remoteChains[i],
                "olympus.policies.LZBridgeGateway"
            );
            bytes32 peer = LZConfigLib.addressToBytes32(remoteGateway);
            console2.log("  EID", remoteEids[i], "->", remoteGateway);

            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZBridgeGateway.setPeer, (remoteEids[i], peer))
            );
        }
    }

    /// @notice Sets enforced options for all remote chains.
    function _setEnforcedOptions(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        uint32[] memory remoteEids = _getRemoteEids();
        uint8 msgBridgeOhm = gateway_.MSG_BRIDGE_OHM();

        console2.log("\nSetting enforced options");

        EnforcedOptionParam[]
            memory opts = new EnforcedOptionParam[](remoteEids.length);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
            bytes memory options = abi.encodePacked(
                uint16(3),
                uint8(1),
                uint16(17),
                uint8(1),
                uint128(200_000)
            );
            opts[i] = EnforcedOptionParam({
                eid: remoteEids[i],
                msgType: msgBridgeOhm,
                options: options
            });
        }

        addToBatch(
            gatewayAddr,
            abi.encodeCall(ILZBridgeGateway.setEnforcedOptions, (opts))
        );
    }

    // =========== CHAIN-SPECIFIC HELPERS =========== //

    /// @notice Returns the local LZ DVN address for the current chain.
    function _getLocalLzDVN() internal view returns (address) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_LZ_DVN;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_LZ_DVN;
        if (_isChain("optimism")) return LZConfigLib.OPT_LZ_DVN;
        if (_isChain("base")) return LZConfigLib.BASE_LZ_DVN;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the local EID for the current chain.
    function _getLocalEid() internal view returns (uint32) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_EID;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_EID;
        if (_isChain("optimism")) return LZConfigLib.OPT_EID;
        if (_isChain("base")) return LZConfigLib.BASE_EID;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the 3 remote EIDs for the current chain.
    function _getRemoteEids() internal view returns (uint32[] memory eids) {
        eids = new uint32[](_REMOTE_CHAIN_COUNT);
        if (_isChain("mainnet")) {
            eids[0] = LZConfigLib.ARB_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
        } else if (_isChain("arbitrum")) {
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
        } else if (_isChain("optimism")) {
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.BASE_EID;
        } else if (_isChain("base")) {
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.OPT_EID;
        } else {
            revert LZBridgeBatchScript_UnsupportedChain();
        }
    }

    /// @notice Returns the 3 remote chain names (env.json keys) for the current chain.
    function _getRemoteChainNames()
        internal
        view
        returns (string[_REMOTE_CHAIN_COUNT] memory names)
    {
        if (_isChain("mainnet")) return ["arbitrum", "optimism", "base"];
        if (_isChain("arbitrum")) return ["mainnet", "optimism", "base"];
        if (_isChain("optimism")) return ["mainnet", "arbitrum", "base"];
        if (_isChain("base")) return ["mainnet", "arbitrum", "optimism"];
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the SendUln302 address for the current chain.
    function _getSendUln302() internal view returns (address) {
        return LZConfigLib.sendUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the ReceiveUln302 address for the current chain.
    function _getRecvUln302() internal view returns (address) {
        return LZConfigLib.recvUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the outbound confirmation count for the current chain.
    function _outboundConfirmations() internal view returns (uint64) {
        return LZConfigLib.outboundConfirmationsForEid(_getLocalEid());
    }

    /// @notice Returns [localLzDVN, GCLOUD_DVN] sorted ascending.
    function _getDVNs() internal view returns (address[] memory) {
        return LZConfigLib.dvnsForEid(_getLocalEid());
    }

    /// @notice Checks if the current chain matches the given name.
    function _isChain(string memory name_) internal view returns (bool) {
        return keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked(name_));
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
