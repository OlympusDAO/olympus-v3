// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILayerZeroEndpointLatestVersion {
    function latestVersion() external view returns (uint16);
}

interface ILayerZeroDVNVID {
    function vid() external view returns (uint32);
}

/// @title LZConfigLib
/// @notice Shared LayerZero V1 ULN301 constants and struct mirrors used by the
///         LZ Bridge Security Upgrade proposal, LZ Bridge MS batches and its tests.
library LZConfigLib {
    // ========== LZ ENDPOINTS ========== //

    // Source: src/scripts/env.json

    // LZ V1 Endpoints:
    address internal constant LZ_ENDPOINT = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address internal constant ARB_LZ_ENDPOINT = 0x3c2269811836af69497E5F486A85D7316753cf62;
    address internal constant OPT_LZ_ENDPOINT = 0x3c2269811836af69497E5F486A85D7316753cf62;
    address internal constant BASE_LZ_ENDPOINT = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;

    // ========== DVNs ========== //

    // Source: https://docs.layerzero.network/contracts/dvn-addresses

    // LayerZero Labs DVN (chain-specific)
    address internal constant ETH_LZ_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address internal constant ARB_LZ_DVN = 0x2f55C492897526677C5B68fb199ea31E2c126416;
    address internal constant OPT_LZ_DVN = 0x6A02D83e8d433304bba74EF1c427913958187142;
    address internal constant BASE_LZ_DVN = 0x9e059a54699a285714207b43B055483E78FAac25;

    // Google Cloud DVN (same CREATE2 address on all EVM chains)
    address internal constant GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    // ========== EXECUTOR ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // LZ Executor (same EOA on all EVM chains)
    address internal constant LZ_EXECUTOR = 0xe93685f3bBA03016F02bD1828BaDD6195988D950;

    // ========== ULN301 CONFIG TYPES ========== //

    // Source: https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    // Also, LayerZero-v2 repo
    //   SendUln301.sol: https://github.com/LayerZero-Labs/LayerZero-v2/blob/592625b9e5967643853476445ffe0e777360b906/packages/layerzero-v2/evm/messagelib/contracts/uln/uln301/SendUln301.sol
    //   ReceiveUln301.sol: https://github.com/LayerZero-Labs/LayerZero-v2/blob/592625b9e5967643853476445ffe0e777360b906/packages/layerzero-v2/evm/messagelib/contracts/uln/uln301/ReceiveUln301.sol

    uint256 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint256 internal constant CONFIG_TYPE_ULN = 2;

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

    // ========== STRUCTS ========== //

    // Source: https://docs.layerzero.network/v2/developers/evm/create-lz-oapp/configuring-pathways

    struct UlnConfig {
        uint64 confirmations;
        uint8 requiredDVNCount;
        uint8 optionalDVNCount;
        uint8 optionalDVNThreshold;
        address[] requiredDVNs;
        address[] optionalDVNs;
    }

    struct ExecutorConfig {
        uint32 maxMessageSize;
        address executor;
    }

    // ========== ENDPOINT QUERIES ========== //

    /// @notice Returns the latest messaging library version from the LZ Endpoint.
    /// @param endpoint_ The LZ V1 Endpoint address.
    /// @return The latest version number.
    function getLatestVersion(address endpoint_) internal view returns (uint16) {
        return ILayerZeroEndpointLatestVersion(endpoint_).latestVersion();
    }

    /// @notice Returns the V1 endpoint ID (`vid`) reported by a DVN contract.
    /// @param dvn_ The DVN contract address.
    /// @return The V1 endpoint ID.
    function getDVNVid(address dvn_) internal view returns (uint32) {
        return ILayerZeroDVNVID(dvn_).vid();
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
}
