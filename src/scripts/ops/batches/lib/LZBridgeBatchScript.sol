// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.142/interfaces/IMessageLibManager.sol";

/// @title LZBridgeBatchScript
/// @notice Abstract base for LZ bridge batch scripts (Ethereum).
///         Contains shared constants, structs, and helpers for LZ V2 configuration.
abstract contract LZBridgeBatchScript is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeBatchScript_UnsupportedChain();

    // =========== CONSTANTS =========== //

    /// @dev Number of remote chains per deployment (each chain has 3 remotes).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

    // TODO: Set before execution
    uint256 internal constant INITIAL_BRIDGED_SUPPLY = 0;

    // =========== LZ V2 CONFIGURATION HELPERS =========== //

    /// @notice Configures LZ V2 libraries and per-remote ULN/Executor config for the current chain.
    function _configureLZ(LZBridgeGateway gateway_) internal {
        address sendLib = _getSendLib();
        address recvLib = _getReceiveLib();
        address gatewayAddr = address(gateway_);

        console2.log("\nConfiguring LZ V2 libraries");
        console2.log("  Send library:", sendLib);
        console2.log("  Receive library:", recvLib);

        // Set send and receive libraries for each remote
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = _getRemoteEids();
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setSendLibrary.selector,
                    remoteEids[i],
                    sendLib
                )
            );
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setReceiveLibrary.selector,
                    remoteEids[i],
                    recvLib,
                    0 // no grace period
                )
            );
        }

        // Configure per-remote chain ULN and Executor config
        uint64 outConf = _outboundConfirmations();
        address[] memory dvns = _getDVNs();

        // Build send config params (ULN + Executor) for all remotes
        {
            SetConfigParam[] memory sendParams = new SetConfigParam[](_REMOTE_CHAIN_COUNT * 2);
            for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
                uint32 remoteEid = remoteEids[i];
                console2.log("  Configuring remote EID:", remoteEid);

                // Send ULN config (outbound confirmations from this chain)
                sendParams[i * 2] = SetConfigParam({
                    eid: remoteEid,
                    configType: LZConfigLib.CONFIG_TYPE_ULN,
                    config: LZConfigLib.encodeUlnConfig(outConf, dvns)
                });

                // Executor config (send side only)
                sendParams[i * 2 + 1] = SetConfigParam({
                    eid: remoteEid,
                    configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                    config: LZConfigLib.encodeExecutorConfig()
                });
            }
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setLZConfig.selector,
                    sendLib,
                    abi.encode(sendParams)
                )
            );
        }

        // Build receive config params (ULN only) for all remotes
        {
            SetConfigParam[] memory recvParams = new SetConfigParam[](_REMOTE_CHAIN_COUNT);
            for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
                uint32 remoteEid = remoteEids[i];
                uint64 remoteOutConf = _outboundConfirmationsForEid(remoteEid);
                recvParams[i] = SetConfigParam({
                    eid: remoteEid,
                    configType: LZConfigLib.CONFIG_TYPE_ULN,
                    config: LZConfigLib.encodeUlnConfig(remoteOutConf, dvns)
                });
            }
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setLZConfig.selector,
                    recvLib,
                    abi.encode(recvParams)
                )
            );
        }
    }

    /// @notice Sets peers for all remote chains from env.json addresses.
    function _setPeers(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        string[_REMOTE_CHAIN_COUNT] memory remoteChains = _getRemoteChainNames();
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = _getRemoteEids();

        console2.log("\nSetting peers");

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            address remoteGateway = _envAddressNotZero(
                remoteChains[i],
                "olympus.policies.LZBridgeGateway"
            );
            console2.log("  EID", remoteEids[i], "->", remoteGateway);

            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setPeer.selector,
                    remoteEids[i],
                    remoteGateway
                )
            );
        }
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

    /// @notice Returns the send library address for the current chain.
    function _getSendLib() internal view returns (address) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_SEND_ULN_302;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_SEND_ULN_302;
        if (_isChain("optimism")) return LZConfigLib.OPT_SEND_ULN_302;
        if (_isChain("base")) return LZConfigLib.BASE_SEND_ULN_302;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the receive library address for the current chain.
    function _getReceiveLib() internal view returns (address) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_RECEIVE_ULN_302;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_RECEIVE_ULN_302;
        if (_isChain("optimism")) return LZConfigLib.OPT_RECEIVE_ULN_302;
        if (_isChain("base")) return LZConfigLib.BASE_RECEIVE_ULN_302;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the 3 remote LZ V2 endpoint IDs for the current chain.
    function _getRemoteEids() internal view returns (uint32[_REMOTE_CHAIN_COUNT] memory ids) {
        if (_isChain("mainnet"))
            return [LZConfigLib.ARB_EID, LZConfigLib.OPT_EID, LZConfigLib.BASE_EID];
        if (_isChain("arbitrum"))
            return [LZConfigLib.ETH_EID, LZConfigLib.OPT_EID, LZConfigLib.BASE_EID];
        if (_isChain("optimism"))
            return [LZConfigLib.ETH_EID, LZConfigLib.ARB_EID, LZConfigLib.BASE_EID];
        if (_isChain("base"))
            return [LZConfigLib.ETH_EID, LZConfigLib.ARB_EID, LZConfigLib.OPT_EID];
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the 3 remote chain names (env.json keys) for the current chain.
    function _getRemoteChainNames() internal view returns (string[_REMOTE_CHAIN_COUNT] memory names) {
        if (_isChain("mainnet")) return ["arbitrum", "optimism", "base"];
        if (_isChain("arbitrum")) return ["mainnet", "optimism", "base"];
        if (_isChain("optimism")) return ["mainnet", "arbitrum", "base"];
        if (_isChain("base")) return ["mainnet", "arbitrum", "optimism"];
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the outbound confirmation count for the current chain.
    function _outboundConfirmations() internal view returns (uint64) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS;
        if (_isChain("optimism")) return LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS;
        if (_isChain("base")) return LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns the outbound confirmation count for a given LZ V2 endpoint ID.
    function _outboundConfirmationsForEid(uint32 eid_) internal pure returns (uint64) {
        if (eid_ == LZConfigLib.ETH_EID) return LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS;
        if (eid_ == LZConfigLib.ARB_EID) return LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS;
        if (eid_ == LZConfigLib.OPT_EID) return LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS;
        if (eid_ == LZConfigLib.BASE_EID) return LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS;
        revert LZBridgeBatchScript_UnsupportedChain();
    }

    /// @notice Returns [localLzDVN, LZConfigLib.GCLOUD_DVN] sorted ascending.
    function _getDVNs() internal view returns (address[] memory dvns) {
        address localDvn = _getLocalLzDVN();
        dvns = new address[](2);
        // All the chain-specific LZ DVN addresses are below LZConfigLib.GCLOUD_DVN (0xD56e...)
        if (localDvn < LZConfigLib.GCLOUD_DVN) {
            dvns[0] = localDvn;
            dvns[1] = LZConfigLib.GCLOUD_DVN;
        } else {
            dvns[0] = LZConfigLib.GCLOUD_DVN;
            dvns[1] = localDvn;
        }
    }

    /// @notice Checks if the current chain matches the given name.
    function _isChain(string memory name_) internal view returns (bool) {
        return keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked(name_));
    }

}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
