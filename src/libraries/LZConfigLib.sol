// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILayerZeroDVNState {
    function vid() external view returns (uint32);
}

/// @title LZConfigLib
/// @notice Shared LayerZero V2 EndpointV2 constants and struct mirrors used by the
///         LZ Bridge Security Upgrade proposal, LZ Bridge MS batches and its tests.
library LZConfigLib {
    // ========== LZ V2 ENDPOINTS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    address internal constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant ARB_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant OPT_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant BASE_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // ========== MESSAGE LIBRARIES (SendUln302 / ReceiveUln302) ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // Ethereum
    address internal constant ETH_SEND_ULN_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address internal constant ETH_RECEIVE_ULN_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    // Arbitrum
    address internal constant ARB_SEND_ULN_302 = 0x975bcD720be66659e3EB3C0e4F1866a3020E493A;
    address internal constant ARB_RECEIVE_ULN_302 = 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6;

    // Optimism
    address internal constant OPT_SEND_ULN_302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
    address internal constant OPT_RECEIVE_ULN_302 = 0x3C4962fF6258DCfCAFd23A814237571571899985;

    // Base
    address internal constant BASE_SEND_ULN_302 = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
    address internal constant BASE_RECEIVE_ULN_302 = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;

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

    // ========== ULN302 CONFIG TYPES ========== //

    // Source: https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config

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

    // ========== CHAIN LZ V2 ENDPOINT IDs (EIDs) ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    uint32 internal constant ETH_EID = 30101;
    uint32 internal constant ARB_EID = 30110;
    uint32 internal constant OPT_EID = 30111;
    uint32 internal constant BASE_EID = 30184;

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

    /// @notice Converts an address to bytes32 for V2 peer encoding.
    function addressToBytes32(address addr_) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr_)));
    }
}
