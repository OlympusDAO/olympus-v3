// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";

interface ILayerZeroDVNState {
    function vid() external view returns (uint32);
}

/// @title LZConfigLib
/// @notice Shared LayerZero V2 constants and struct mirrors used by the
///         LZ Bridge Security Upgrade proposal, LZ Bridge MS batches and its tests.
library LZConfigLib {
    // ========== LZ ENDPOINTS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // LZ Endpoint (same CREATE2 address on all EVM chains)
    address internal constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // ========== LZ MESSAGE LIBRARIES ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // Ethereum
    address internal constant ETH_SEND_ULN_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address internal constant ETH_RECV_ULN_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    // Arbitrum
    address internal constant ARB_SEND_ULN_302 = 0x975bcD720be66659e3EB3C0e4F1866a3020E493A;
    address internal constant ARB_RECV_ULN_302 = 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6;

    // Optimism
    address internal constant OPT_SEND_ULN_302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
    address internal constant OPT_RECV_ULN_302 = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;

    // Base
    address internal constant BASE_SEND_ULN_302 = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
    address internal constant BASE_RECV_ULN_302 = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;

    // ========== EXECUTORS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // LZ Executor (same EOA on all EVM chains)
    address internal constant LZ_EXECUTOR = 0xe93685f3bBA03016F02bD1828BaDD6195988D950;

    // ========== DVNS ========== //

    // Source: https://docs.layerzero.network/contracts/dvn-addresses

    // LayerZero Labs DVN (chain-specific)
    address internal constant ETH_LZ_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address internal constant ARB_LZ_DVN = 0x2f55C492897526677C5B68fb199ea31E2c126416;
    address internal constant OPT_LZ_DVN = 0x6A02D83e8d433304bba74EF1c427913958187142;
    address internal constant BASE_LZ_DVN = 0x9e059a54699a285714207b43B055483E78FAac25;

    // Google Cloud DVN (same CREATE2 address on all EVM chains)
    address internal constant GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    // ========== CONFIG TYPES (EndpointV2 / SetConfigParam.configType) ========== //

    // Source: https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    //   SendUln302.sol: configType 1 = Executor, 2 = ULN
    //   ReceiveUln302.sol: configType 2 = ULN

    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;

    // ========== BRIDGE CONSTANTS ========== //

    // Source: LayerZero default maxMessageSize used in OFT/OApp examples
    // https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config

    uint32 internal constant MAX_MESSAGE_SIZE = 10_000;

    // ========== CONFIRMATIONS ========== //

    // Source: LayerZero Scan Default Checker and OFT Quickstart guides
    //
    // LayerZero Scan Default Checker: https://layerzeroscan.com/tools/defaults
    // Ethereum Mainnet OFT Quickstart: https://docs.layerzero.network/v2/deployments/evm-chains/ethereum-mainnet-oft-quickstart
    // Arbitrum Mainnet OFT Quickstart: https://docs.layerzero.network/v2/deployments/evm-chains/arbitrum-mainnet-oft-quickstart

    // Ethereum outbound confirmations
    uint64 internal constant ETH_OUTBOUND_CONFIRMATIONS = 15;

    // Remote chain outbound confirmations (used as inbound on Ethereum)
    uint64 internal constant ARB_OUTBOUND_CONFIRMATIONS = 20;
    uint64 internal constant OPT_OUTBOUND_CONFIRMATIONS = 20;
    uint64 internal constant BASE_OUTBOUND_CONFIRMATIONS = 10;

    // ========== CHAIN LZ IDS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts (Endpoint ID)

    uint16 internal constant ETH_CHAIN_ID = 101;
    uint16 internal constant ARB_CHAIN_ID = 110;
    uint16 internal constant OPT_CHAIN_ID = 111;
    uint16 internal constant BASE_CHAIN_ID = 184;

    // ========== LZ EIDs ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    uint32 internal constant ETH_EID = 30101;
    uint32 internal constant ARB_EID = 30110;
    uint32 internal constant OPT_EID = 30111;
    uint32 internal constant BASE_EID = 30184;

    // ========== ADDRESS HELPERS ========== //

    /// @notice Converts an address to a bytes32 value left-padded with zeros.
    /// @dev    Used by LayerZero V2 for peer addressing (OApp.setPeer, etc.).
    function addressToBytes32(address addr_) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr_)));
    }

    // ========== ENCODING HELPERS ========== //

    /// @notice ABI-encodes a UlnConfig struct.
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
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: requiredDVNs_,
                    optionalDVNs: empty
                })
            );
    }

    /// @notice ABI-encodes an ExecutorConfig struct using library constants.
    function encodeExecutorConfig() internal pure returns (bytes memory) {
        return
            abi.encode(ExecutorConfig({maxMessageSize: MAX_MESSAGE_SIZE, executor: LZ_EXECUTOR}));
    }

    // ========== EID HELPERS ========== //

    /// @notice Returns the SendUln302 address for a given V2 EID.
    function sendUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_SEND_ULN_302;
        if (eid_ == ARB_EID) return ARB_SEND_ULN_302;
        if (eid_ == OPT_EID) return OPT_SEND_ULN_302;
        if (eid_ == BASE_EID) return BASE_SEND_ULN_302;
        revert("LZConfigLib: unsupported EID");
    }

    /// @notice Returns the ReceiveUln302 address for a given V2 EID.
    function recvUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_RECV_ULN_302;
        if (eid_ == ARB_EID) return ARB_RECV_ULN_302;
        if (eid_ == OPT_EID) return OPT_RECV_ULN_302;
        if (eid_ == BASE_EID) return BASE_RECV_ULN_302;
        revert("LZConfigLib: unsupported EID");
    }

    /// @notice Returns the outbound confirmation count for a given V2 EID.
    function outboundConfirmationsForEid(uint32 eid_) internal pure returns (uint64) {
        if (eid_ == ETH_EID) return ETH_OUTBOUND_CONFIRMATIONS;
        if (eid_ == ARB_EID) return ARB_OUTBOUND_CONFIRMATIONS;
        if (eid_ == OPT_EID) return OPT_OUTBOUND_CONFIRMATIONS;
        if (eid_ == BASE_EID) return BASE_OUTBOUND_CONFIRMATIONS;
        revert("LZConfigLib: unsupported EID");
    }

    /// @notice Returns the LZ DVN address for a given V2 EID.
    function lzDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_LZ_DVN;
        if (eid_ == ARB_EID) return ARB_LZ_DVN;
        if (eid_ == OPT_EID) return OPT_LZ_DVN;
        if (eid_ == BASE_EID) return BASE_LZ_DVN;
        revert("LZConfigLib: unsupported EID");
    }

    /// @notice Returns [localLzDVN, GCLOUD_DVN] sorted ascending for a given V2 EID.
    function dvnsForEid(uint32 eid_) internal pure returns (address[] memory dvns) {
        address localDvn = lzDvnForEid(eid_);
        dvns = new address[](2);
        // All chain-specific LZ DVN addresses are below GCLOUD_DVN (0xD56e...)
        if (localDvn < GCLOUD_DVN) {
            dvns[0] = localDvn;
            dvns[1] = GCLOUD_DVN;
        } else {
            dvns[0] = GCLOUD_DVN;
            dvns[1] = localDvn;
        }
    }
}
