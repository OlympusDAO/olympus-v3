// SPDX-License-Identifier: Unlicensed
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";

/// @title LZBridgeBatchScript
/// @notice Abstract base for LZ bridge batch scripts (Ethereum).
///         Contains shared constants, structs, and helpers for LZ configuration.
abstract contract LZBridgeBatchScript is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeBatchScript_UnsupportedChain();

    // =========== CONSTANTS =========== //

    /// @dev Number of remote chains per deployment (each chain has 3 remotes).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

    // TODO: Set before execution
    uint256 internal constant INITIAL_BRIDGED_SUPPLY = 0;

    // =========== LZ CONFIGURATION HELPERS =========== //

    /// @notice Configures LZ versions and per-remote ULN/Executor config for the current chain.
    function _configureLZ(LZBridgeGateway gateway_) internal {
        (uint16 sendVer, uint16 recvVer) = _getLocalVersions();
        address gatewayAddr = address(gateway_);

        console2.log("\nConfiguring LZ versions - send:", sendVer, "recv:", recvVer);

        // Pin send and receive versions
        addToBatch(
            gatewayAddr,
            abi.encodeWithSelector(LZBridgeGateway.setSendVersion.selector, sendVer)
        );
        addToBatch(
            gatewayAddr,
            abi.encodeWithSelector(LZBridgeGateway.setReceiveVersion.selector, recvVer)
        );

        // Configure per-remote chain
        uint16[_REMOTE_CHAIN_COUNT] memory remoteChainIds = _getRemoteChainIds();
        uint64 outConf = _outboundConfirmations();
        address[] memory dvns = _getDVNs();

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint16 remoteId = remoteChainIds[i];
            console2.log("  Configuring remote chain:", remoteId);

            // Send ULN config (outbound confirmations from this chain)
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    sendVer,
                    remoteId,
                    LZConfigLib.CONFIG_TYPE_ULN,
                    LZConfigLib.encodeUlnConfig(outConf, dvns)
                )
            );

            // Executor config (send side only)
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    sendVer,
                    remoteId,
                    LZConfigLib.CONFIG_TYPE_EXECUTOR,
                    LZConfigLib.encodeExecutorConfig()
                )
            );

            // Receive ULN config (inbound confirmations = outbound from remote chain)
            uint64 remoteOutConf = _outboundConfirmationsForChain(remoteId);
            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    recvVer,
                    remoteId,
                    LZConfigLib.CONFIG_TYPE_ULN,
                    LZConfigLib.encodeUlnConfig(remoteOutConf, dvns)
                )
            );
        }
    }

    /// @notice Sets trusted remotes for all remote chains from env.json addresses.
    function _setTrustedRemotes(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        string[_REMOTE_CHAIN_COUNT] memory remoteChains = _getRemoteChainNames();
        uint16[_REMOTE_CHAIN_COUNT] memory remoteChainIds = _getRemoteChainIds();

        console2.log("\nSetting trusted remotes");

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            address remoteGateway = _envAddressNotZero(
                remoteChains[i],
                "olympus.policies.LZBridgeGateway"
            );
            console2.log("  Chain", remoteChainIds[i], "->", remoteGateway);

            addToBatch(
                gatewayAddr,
                abi.encodeWithSelector(
                    LZBridgeGateway.setTrustedRemote.selector,
                    remoteChainIds[i],
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

    /// @notice Returns (sendVersion, receiveVersion) for the current chain.
    /// @dev receiveUln301 = latestVersion, sendUln301 = latestVersion - 1.
    function _getLocalVersions() internal view returns (uint16 sendVer, uint16 recvVer) {
        address endpoint = _envAddressNotZero("external.layerzero.endpoint");
        uint16 latest = LZConfigLib.getLatestVersion(endpoint);
        return (latest - 1, latest);
    }

    /// @notice Returns the 3 remote LZ chain IDs for the current chain.
    function _getRemoteChainIds() internal view returns (uint16[_REMOTE_CHAIN_COUNT] memory ids) {
        if (_isChain("mainnet"))
            return [LZConfigLib.ARB_CHAIN_ID, LZConfigLib.OPT_CHAIN_ID, LZConfigLib.BASE_CHAIN_ID];
        if (_isChain("arbitrum"))
            return [LZConfigLib.ETH_CHAIN_ID, LZConfigLib.OPT_CHAIN_ID, LZConfigLib.BASE_CHAIN_ID];
        if (_isChain("optimism"))
            return [LZConfigLib.ETH_CHAIN_ID, LZConfigLib.ARB_CHAIN_ID, LZConfigLib.BASE_CHAIN_ID];
        if (_isChain("base"))
            return [LZConfigLib.ETH_CHAIN_ID, LZConfigLib.ARB_CHAIN_ID, LZConfigLib.OPT_CHAIN_ID];
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

    /// @notice Returns the outbound confirmation count for a given LZ chain ID.
    function _outboundConfirmationsForChain(uint16 chainId_) internal pure returns (uint64) {
        if (chainId_ == LZConfigLib.ETH_CHAIN_ID) return LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS;
        if (chainId_ == LZConfigLib.ARB_CHAIN_ID) return LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS;
        if (chainId_ == LZConfigLib.OPT_CHAIN_ID) return LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS;
        if (chainId_ == LZConfigLib.BASE_CHAIN_ID) return LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS;
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
