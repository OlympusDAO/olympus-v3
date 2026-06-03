// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";

/// @title LZTestnetConfig
/// @notice LayerZero V2 testnet constants and encoding helpers for the testnet LZ bridge
///         deploy and wire script. This is the testnet counterpart of the production
///         `LZConfigLib`: it covers Ethereum Sepolia, Base Sepolia and Arbitrum Sepolia and
///         exposes the same shaped helpers so the wiring code reads the same way.
/// @dev Addresses were sourced from the LayerZero metadata API
///      (https://metadata.layerzero-api.com/v1/metadata). The three target testnets share
///      exactly three V2 DVN providers (LayerZero Labs, Nethermind and Horizen), so every
///      route pins three required DVNs.
library LZTestnetConfig {
    // ========== ERRORS ========== //

    error LZTestnetConfig_UnsupportedEid(uint32 eid);
    error LZTestnetConfig_UnsupportedChain(string chain);

    // ========== LZ ENDPOINT ========== //

    /// @notice LayerZero V2 endpoint. The same address is deployed on every supported EVM testnet.
    address internal constant TESTNET_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // ========== LZ ENDPOINT IDS (V2 testnet) ========== //

    uint32 internal constant SEPOLIA_EID = 40161;
    uint32 internal constant BASE_SEPOLIA_EID = 40245;
    uint32 internal constant ARB_SEPOLIA_EID = 40231;

    // ========== MESSAGE LIBRARIES (SendUln302 / ReceiveUln302) ========== //

    // Ethereum Sepolia
    address internal constant SEPOLIA_SEND_ULN_302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    address internal constant SEPOLIA_RECV_ULN_302 = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;

    // Base Sepolia
    address internal constant BASE_SEPOLIA_SEND_ULN_302 =
        0xC1868e054425D378095A003EcbA3823a5D0135C9;
    address internal constant BASE_SEPOLIA_RECV_ULN_302 =
        0x12523de19dc41c91F7d2093E0CFbB76b17012C8d;

    // Arbitrum Sepolia
    address internal constant ARB_SEPOLIA_SEND_ULN_302 = 0x4f7cd4DA19ABB31b0eC98b9066B9e857B1bf9C0E;
    address internal constant ARB_SEPOLIA_RECV_ULN_302 = 0x75Db67CDab2824970131D5aa9CECfC9F69c69636;

    // ========== EXECUTORS ========== //

    address internal constant SEPOLIA_LZ_EXECUTOR = 0x718B92b5CB0a5552039B593faF724D182A881eDA;
    address internal constant BASE_SEPOLIA_LZ_EXECUTOR = 0x8A3D588D9f6AC041476b094f97FF94ec30169d3D;
    address internal constant ARB_SEPOLIA_LZ_EXECUTOR = 0x5Df3a1cEbBD9c8BA7F8dF51Fd632A9aef8308897;

    // ========== DVNS ========== //

    // LayerZero Labs DVN
    address internal constant SEPOLIA_LZ_DVN = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
    address internal constant BASE_SEPOLIA_LZ_DVN = 0xbf6FF58f60606EdB2F190769B951D825BCb214E2;
    address internal constant ARB_SEPOLIA_LZ_DVN = 0x5C8C267174e1F345234FF5315D6cfd6716763BaC;

    // Nethermind DVN
    address internal constant SEPOLIA_NETHERMIND_DVN = 0x68802e01D6321D5159208478f297d7007A7516Ed;
    address internal constant BASE_SEPOLIA_NETHERMIND_DVN =
        0xd9222CC3Ccd1DF7c070d700EA377D4aDA2B86Eb5;
    address internal constant ARB_SEPOLIA_NETHERMIND_DVN =
        0x3a74F7174709842d3b8a14ce60B4AA2499F2A2F2;

    // Horizen DVN
    address internal constant SEPOLIA_HORIZEN_DVN = 0x843139c725c2FB9814dE6A12fB890D8dBf3e1698;
    address internal constant BASE_SEPOLIA_HORIZEN_DVN = 0xe1cdD37c13450bc256A39D27B1e1B5d1BC26ddE2;
    address internal constant ARB_SEPOLIA_HORIZEN_DVN = 0xc6cec4e6b8F3DC87E676D06A24864081311EDa15;

    // ========== CONFIG TYPES (EndpointV2 / SetConfigParam.configType) ========== //

    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;

    // ========== BRIDGE CONSTANTS ========== //

    uint32 internal constant MAX_MESSAGE_SIZE = 10_000;

    /// @notice Block confirmations required on every testnet route. A single low value is used
    ///         on all routes to keep cross-chain delivery fast during testing.
    uint64 internal constant TESTNET_CONFIRMATIONS = 2;

    // ========== RATE LIMITS ========== //

    /// @notice Sliding-window length applied to every outbound and inbound rate limit, in seconds.
    uint32 internal constant RATE_LIMIT_WINDOW = 1 days;

    /// @notice Generous per-endpoint OHM rate limit (9 decimals) applied in both directions on
    ///         every route, so testing is not throttled.
    uint256 internal constant TESTNET_RATE_LIMIT = 1_000_000e9;

    // ========== ADDRESS HELPERS ========== //

    /// @notice Converts an address to a bytes32 value left-padded with zeros.
    /// @dev Used by LayerZero V2 for peer addressing (OApp.setPeer, etc.).
    function addressToBytes32(address addr_) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr_)));
    }

    // ========== ENCODING HELPERS ========== //

    /// @notice ABI-encodes a UlnConfig with no optional DVNs pinned to the app.
    /// @dev `optionalDVNCount` uses the LayerZero NIL sentinel (`type(uint8).max`) so that the
    ///      OApp-level config explicitly declares "no optional DVNs" instead of inheriting the
    ///      EID-level default, matching the production `LZConfigLib` behaviour.
    /// @param confirmations_ The number of block confirmations required.
    /// @param requiredDVNs_ Sorted ascending array of required DVN addresses.
    function encodeUlnConfig(
        uint64 confirmations_,
        address[] memory requiredDVNs_
    ) internal pure returns (bytes memory) {
        address[] memory empty = new address[](0);
        return
            abi.encode(
                UlnConfig({
                    confirmations: confirmations_,
                    requiredDVNCount: uint8(requiredDVNs_.length),
                    optionalDVNCount: type(uint8).max,
                    optionalDVNThreshold: 0,
                    requiredDVNs: requiredDVNs_,
                    optionalDVNs: empty
                })
            );
    }

    /// @notice ABI-encodes an ExecutorConfig using the executor for the given local EID.
    function encodeExecutorConfig(uint32 localEid_) internal pure returns (bytes memory) {
        return
            abi.encode(
                ExecutorConfig({
                    maxMessageSize: MAX_MESSAGE_SIZE,
                    executor: executorForEid(localEid_)
                })
            );
    }

    // ========== EID HELPERS ========== //

    /// @notice Returns the SendUln302 address for a given testnet EID.
    function sendUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_SEND_ULN_302;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_SEND_ULN_302;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_SEND_ULN_302;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the ReceiveUln302 address for a given testnet EID.
    function recvUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_RECV_ULN_302;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_RECV_ULN_302;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_RECV_ULN_302;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the executor address for a given testnet EID.
    function executorForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_LZ_EXECUTOR;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_LZ_EXECUTOR;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_LZ_EXECUTOR;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the LayerZero V2 endpoint for a given testnet EID.
    /// @dev The same endpoint is deployed on every supported testnet. The EID is validated so
    ///      that an unsupported route fails loudly.
    function endpointForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID || eid_ == BASE_SEPOLIA_EID || eid_ == ARB_SEPOLIA_EID) {
            return TESTNET_LZ_ENDPOINT;
        }
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the LayerZero Labs DVN address for a given testnet EID.
    function lzDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_LZ_DVN;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_LZ_DVN;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_LZ_DVN;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the Nethermind DVN address for a given testnet EID.
    function nethermindDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_NETHERMIND_DVN;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_NETHERMIND_DVN;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_NETHERMIND_DVN;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the Horizen DVN address for a given testnet EID.
    function horizenDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == SEPOLIA_EID) return SEPOLIA_HORIZEN_DVN;
        if (eid_ == BASE_SEPOLIA_EID) return BASE_SEPOLIA_HORIZEN_DVN;
        if (eid_ == ARB_SEPOLIA_EID) return ARB_SEPOLIA_HORIZEN_DVN;
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the block confirmations required for a given testnet EID.
    /// @dev Constant across testnets; the parameter is validated for symmetry with the
    ///      production helpers and to fail on an unsupported EID.
    function confirmationsForEid(uint32 eid_) internal pure returns (uint64) {
        if (eid_ == SEPOLIA_EID || eid_ == BASE_SEPOLIA_EID || eid_ == ARB_SEPOLIA_EID) {
            return TESTNET_CONFIRMATIONS;
        }
        revert LZTestnetConfig_UnsupportedEid(eid_);
    }

    /// @notice Returns the three required DVNs for a route, sorted ascending by address.
    /// @dev All three testnets share the LayerZero Labs, Nethermind and Horizen DVNs, so the
    ///      same three providers are pinned on every route. The returned addresses are local to
    ///      `localEid_`. `remoteEid_` is validated so an unsupported route fails loudly.
    /// @param localEid_ The local chain's V2 testnet EID.
    /// @param remoteEid_ The remote chain's V2 testnet EID.
    function dvnsForRoute(
        uint32 localEid_,
        uint32 remoteEid_
    ) internal pure returns (address[] memory dvns) {
        // Validate the remote EID even though the DVN set does not depend on it, so callers
        // cannot configure a route to an unsupported chain.
        endpointForEid(remoteEid_);

        dvns = new address[](3);
        dvns[0] = lzDvnForEid(localEid_);
        dvns[1] = nethermindDvnForEid(localEid_);
        dvns[2] = horizenDvnForEid(localEid_);

        // Insertion sort to produce the ascending order required by the ULN config.
        for (uint256 i = 1; i < dvns.length; ++i) {
            address key = dvns[i];
            uint256 j = i;
            while (j > 0 && dvns[j - 1] > key) {
                dvns[j] = dvns[j - 1];
                unchecked {
                    --j;
                }
            }
            dvns[j] = key;
        }
    }

    // ========== CHAIN-NAME HELPERS ========== //

    /// @notice Returns the local testnet EID for a given env.json chain name.
    function eidForChain(string memory chain_) internal pure returns (uint32) {
        bytes32 h = keccak256(bytes(chain_));
        if (h == keccak256("sepolia")) return SEPOLIA_EID;
        if (h == keccak256("base-sepolia")) return BASE_SEPOLIA_EID;
        if (h == keccak256("arbitrum-sepolia")) return ARB_SEPOLIA_EID;
        revert LZTestnetConfig_UnsupportedChain(chain_);
    }

    /// @notice Returns the two remote chain names (env.json keys) for a given chain, forming a
    ///         full mesh across the three testnets.
    function remoteChainsForChain(
        string memory chain_
    ) internal pure returns (string[] memory names) {
        bytes32 h = keccak256(bytes(chain_));
        names = new string[](2);
        if (h == keccak256("sepolia")) {
            names[0] = "base-sepolia";
            names[1] = "arbitrum-sepolia";
        } else if (h == keccak256("base-sepolia")) {
            names[0] = "sepolia";
            names[1] = "arbitrum-sepolia";
        } else if (h == keccak256("arbitrum-sepolia")) {
            names[0] = "sepolia";
            names[1] = "base-sepolia";
        } else {
            revert LZTestnetConfig_UnsupportedChain(chain_);
        }
    }

    /// @notice Returns true if the given chain name is one of the three supported testnets.
    function isSupportedChain(string memory chain_) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(chain_));
        return
            h == keccak256("sepolia") ||
            h == keccak256("base-sepolia") ||
            h == keccak256("arbitrum-sepolia");
    }
}
