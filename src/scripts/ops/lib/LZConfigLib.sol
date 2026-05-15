// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";

/// @title LZConfigLib
/// @notice Shared LayerZero V2 constants and encoding helpers used by the
///         LZ Bridge Security Upgrade proposal, LZ Bridge MS batches and their tests.
library LZConfigLib {
    // ========== ERRORS ========== //

    error LZConfigLib_UnsupportedEid(uint32 eid);

    // ========== LZ ENDPOINTS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts
    // Source 2: https://docs.layerzero.network/v2/deployments/chains/ethereum
    // Same address on most EVM chains

    address internal constant ETH_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant ARB_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant BASE_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant BERA_LZ_ENDPOINT = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address internal constant OPT_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // ========== LZ MESSAGE LIBRARIES ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    // Ethereum
    address internal constant ETH_SEND_ULN_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address internal constant ETH_RECV_ULN_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    // Arbitrum
    address internal constant ARB_SEND_ULN_302 = 0x975bcD720be66659e3EB3C0e4F1866a3020E493A;
    address internal constant ARB_RECV_ULN_302 = 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6;

    // Base
    address internal constant BASE_SEND_ULN_302 = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
    address internal constant BASE_RECV_ULN_302 = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;

    // Berachain
    address internal constant BERA_SEND_ULN_302 = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    address internal constant BERA_RECV_ULN_302 = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;

    // Optimism
    address internal constant OPT_SEND_ULN_302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
    address internal constant OPT_RECV_ULN_302 = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;

    // ========== EXECUTORS ========== //

    // Source: https://layerzeroscan.com/tools/defaults
    // Source 2: https://docs.layerzero.network/v2/deployments/deployed-contracts

    address internal constant ETH_LZ_EXECUTOR = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    address internal constant ARB_LZ_EXECUTOR = 0x31CAe3B7fB82d847621859fb1585353c5720660D;
    address internal constant BASE_LZ_EXECUTOR = 0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4;
    address internal constant BERA_LZ_EXECUTOR = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
    address internal constant OPT_LZ_EXECUTOR = 0x2D2ea0697bdbede3F01553D2Ae4B8d0c486B666e;

    // ========== DVNS ========== //

    // Source: https://docs.layerzero.network/contracts/dvn-addresses
    // Source 2: https://layerzeroscan.com/tools/defaults

    // LayerZero Labs DVN
    address internal constant ETH_LZ_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address internal constant ARB_LZ_DVN = 0x2f55C492897526677C5B68fb199ea31E2c126416;
    address internal constant BASE_LZ_DVN = 0x9e059a54699a285714207b43B055483E78FAac25;
    address internal constant BERA_LZ_DVN = 0x282b3386571f7f794450d5789911a9804FA346b4;
    address internal constant OPT_LZ_DVN = 0x6A02D83e8d433304bba74EF1c427913958187142;

    // Canary DVN
    address internal constant ETH_CANARY_DVN = 0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd;
    address internal constant ARB_CANARY_DVN = 0xf2E380c90e6c09721297526dbC74f870e114dfCb;
    address internal constant BASE_CANARY_DVN = 0x554833698Ae0FB22ECC90B01222903fD62CA4B47;
    address internal constant BERA_CANARY_DVN = 0x06e8042729CeF3aE6D6DB5350f48F9D736C3675d;
    address internal constant OPT_CANARY_DVN = 0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f;

    // Nethermind DVN
    address internal constant ETH_NETHERMIND_DVN = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address internal constant ARB_NETHERMIND_DVN = 0xa7b5189bcA84Cd304D8553977c7C614329750d99;
    address internal constant BASE_NETHERMIND_DVN = 0xcd37CA043f8479064e10635020c65FfC005d36f6;
    address internal constant BERA_NETHERMIND_DVN = 0xDd7B5E1dB4AaFd5C8EC3b764eFB8ed265Aa5445B;
    address internal constant OPT_NETHERMIND_DVN = 0xa7b5189bcA84Cd304D8553977c7C614329750d99;

    // Google Cloud DVN (same CREATE2 address on supported chains; NOT available on Berachain).
    // Used as the fourth required DVN on routes that do not touch Berachain.
    address internal constant ETH_GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
    address internal constant ARB_GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
    address internal constant BASE_GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
    address internal constant OPT_GCLOUD_DVN = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    // Horizen DVN (used as the fourth required DVN on routes that touch Berachain, since the
    // Google Cloud DVN is not available there).
    address internal constant ETH_HORIZEN_DVN = 0x380275805876Ff19055EA900CDb2B46a94ecF20D;
    address internal constant ARB_HORIZEN_DVN = 0x19670Df5E16bEa2ba9b9e68b48C054C5bAEa06B8;
    address internal constant BASE_HORIZEN_DVN = 0xa7b5189bcA84Cd304D8553977c7C614329750d99;
    address internal constant BERA_HORIZEN_DVN = 0xeCbaA45c33ce6Fa284995e5F8314f5bC7F1C2008;
    address internal constant OPT_HORIZEN_DVN = 0x9E930731cb4A6bf7eCc11F695A295c60bDd212eB;

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

    // ========== OHM BRIDGE RATE LIMITS ========== //

    /// @notice Sliding-window length applied to every outbound and inbound rate limit on
    ///         the LZ bridge gateway, in seconds.
    /// @dev Matches the `window` field in `IOffsettingRateLimiter.RateLimitConfig`.
    uint32 internal constant RATE_LIMIT_WINDOW = 1 days;

    /// @notice Outbound OHM rate limit (9 decimals) per remote endpoint when the local
    ///         chain is canonical (Ethereum). Applies to every non-canonical peer.
    uint256 internal constant ETH_OUT_RATE_LIMIT = 100_000e9;

    /// @notice Inbound OHM rate limit (9 decimals) per remote endpoint when the local
    ///         chain is canonical (Ethereum). Applies to every non-canonical peer.
    uint256 internal constant ETH_IN_RATE_LIMIT = 55_000e9;

    /// @notice Outbound OHM rate limit (9 decimals) when the local chain is
    ///         non-canonical and the remote endpoint is Ethereum (canonical).
    uint256 internal constant L2_OUT_TO_ETH_RATE_LIMIT = 50_000e9;

    /// @notice Outbound OHM rate limit (9 decimals) when the local chain is
    ///         non-canonical and the remote endpoint is another non-canonical peer.
    uint256 internal constant L2_OUT_TO_L2_RATE_LIMIT = 100_000e9;

    /// @notice Inbound OHM rate limit (9 decimals) per remote endpoint when the local
    ///         chain is non-canonical (Arbitrum, Optimism, Base, Berachain). Applies
    ///         to deliveries from Ethereum and from every other non-canonical peer.
    uint256 internal constant L2_IN_RATE_LIMIT = 110_000e9;

    // ========== CONFIRMATIONS ========== //

    // Source: LayerZero Scan Default Checker and OFT Quickstart guides
    //
    // LayerZero Scan Default Checker: https://layerzeroscan.com/tools/defaults
    // Ethereum Mainnet OFT Quickstart: https://docs.layerzero.network/v2/deployments/evm-chains/ethereum-mainnet-oft-quickstart
    // Arbitrum Mainnet OFT Quickstart: https://docs.layerzero.network/v2/deployments/evm-chains/arbitrum-mainnet-oft-quickstart

    uint64 internal constant ETH_OUTBOUND_CONFIRMATIONS = 15;
    uint64 internal constant ARB_OUTBOUND_CONFIRMATIONS = 20;
    uint64 internal constant BASE_OUTBOUND_CONFIRMATIONS = 10;
    uint64 internal constant BERA_OUTBOUND_CONFIRMATIONS = 20;
    uint64 internal constant OPT_OUTBOUND_CONFIRMATIONS = 20;

    // ========== LZ CHAIN IDS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    uint16 internal constant ETH_CHAIN_ID = 101;
    uint16 internal constant ARB_CHAIN_ID = 110;
    uint16 internal constant BASE_CHAIN_ID = 184;
    uint16 internal constant BERA_CHAIN_ID = 362;
    uint16 internal constant OPT_CHAIN_ID = 111;

    // ========== LZ ENDPOINT IDS ========== //

    // Source: https://docs.layerzero.network/v2/deployments/deployed-contracts

    uint32 internal constant ETH_EID = 30101;
    uint32 internal constant ARB_EID = 30110;
    uint32 internal constant BASE_EID = 30184;
    uint32 internal constant BERA_EID = 30362;
    uint32 internal constant OPT_EID = 30111;

    // ========== ADDRESS HELPERS ========== //

    /// @notice Converts an address to a bytes32 value left-padded with zeros.
    /// @dev Used by LayerZero V2 for peer addressing (OApp.setPeer, etc.).
    function addressToBytes32(address addr_) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr_)));
    }

    // ========== ENCODING HELPERS ========== //

    /// @notice ABI-encodes a UlnConfig struct with no optional DVNs pinned to the app.
    /// @dev `optionalDVNCount` uses the LayerZero NIL sentinel (`type(uint8).max`) so that the
    ///      OApp-level config explicitly declares "no optional DVNs" instead of inheriting the
    ///      EID-level default. In `UlnBase.sol`, `0` means DEFAULT (inherit) and
    ///      `type(uint8).max` means NIL/NONE; using `0` would let a future change to the
    ///      LayerZero default silently add an optional DVN requirement on verified messages.
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

    /// @notice Returns the SendUln302 address for a given V2 EID.
    function sendUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_SEND_ULN_302;
        if (eid_ == ARB_EID) return ARB_SEND_ULN_302;
        if (eid_ == OPT_EID) return OPT_SEND_ULN_302;
        if (eid_ == BASE_EID) return BASE_SEND_ULN_302;
        if (eid_ == BERA_EID) return BERA_SEND_ULN_302;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the ReceiveUln302 address for a given V2 EID.
    function recvUln302ForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_RECV_ULN_302;
        if (eid_ == ARB_EID) return ARB_RECV_ULN_302;
        if (eid_ == OPT_EID) return OPT_RECV_ULN_302;
        if (eid_ == BASE_EID) return BASE_RECV_ULN_302;
        if (eid_ == BERA_EID) return BERA_RECV_ULN_302;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the outbound confirmation count for a given V2 EID.
    function outboundConfirmationsForEid(uint32 eid_) internal pure returns (uint64) {
        if (eid_ == ETH_EID) return ETH_OUTBOUND_CONFIRMATIONS;
        if (eid_ == ARB_EID) return ARB_OUTBOUND_CONFIRMATIONS;
        if (eid_ == OPT_EID) return OPT_OUTBOUND_CONFIRMATIONS;
        if (eid_ == BASE_EID) return BASE_OUTBOUND_CONFIRMATIONS;
        if (eid_ == BERA_EID) return BERA_OUTBOUND_CONFIRMATIONS;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the outbound OHM rate limit for the given (local, remote) EID
    ///         pair.
    /// @dev On canonical Ethereum every remote shares the same outbound ceiling. On a
    ///      non-canonical chain the ceiling depends on whether the remote is Ethereum
    ///      or another non-canonical peer.
    function outRateLimitForRoute(
        uint32 localEid_,
        uint32 remoteEid_
    ) internal pure returns (uint256) {
        if (localEid_ == ETH_EID) {
            if (
                remoteEid_ == ARB_EID ||
                remoteEid_ == OPT_EID ||
                remoteEid_ == BASE_EID ||
                remoteEid_ == BERA_EID
            ) return ETH_OUT_RATE_LIMIT;
            revert LZConfigLib_UnsupportedEid(remoteEid_);
        }
        if (
            localEid_ == ARB_EID ||
            localEid_ == OPT_EID ||
            localEid_ == BASE_EID ||
            localEid_ == BERA_EID
        ) {
            if (remoteEid_ == ETH_EID) return L2_OUT_TO_ETH_RATE_LIMIT;
            if (
                remoteEid_ == ARB_EID ||
                remoteEid_ == OPT_EID ||
                remoteEid_ == BASE_EID ||
                remoteEid_ == BERA_EID
            ) return L2_OUT_TO_L2_RATE_LIMIT;
            revert LZConfigLib_UnsupportedEid(remoteEid_);
        }
        revert LZConfigLib_UnsupportedEid(localEid_);
    }

    /// @notice Returns the inbound OHM rate limit for the given (local, remote) EID
    ///         pair.
    /// @dev Inbound limits do not differ by remote on non-canonical chains; the same
    ///      ceiling applies to deliveries from Ethereum and from every other
    ///      non-canonical peer. The `remoteEid_` argument is validated for symmetry
    ///      with `outRateLimitForRoute`.
    function inRateLimitForRoute(
        uint32 localEid_,
        uint32 remoteEid_
    ) internal pure returns (uint256) {
        if (localEid_ == ETH_EID) {
            if (
                remoteEid_ == ARB_EID ||
                remoteEid_ == OPT_EID ||
                remoteEid_ == BASE_EID ||
                remoteEid_ == BERA_EID
            ) return ETH_IN_RATE_LIMIT;
            revert LZConfigLib_UnsupportedEid(remoteEid_);
        }
        if (
            localEid_ == ARB_EID ||
            localEid_ == OPT_EID ||
            localEid_ == BASE_EID ||
            localEid_ == BERA_EID
        ) {
            if (
                remoteEid_ == ETH_EID ||
                remoteEid_ == ARB_EID ||
                remoteEid_ == OPT_EID ||
                remoteEid_ == BASE_EID ||
                remoteEid_ == BERA_EID
            ) return L2_IN_RATE_LIMIT;
            revert LZConfigLib_UnsupportedEid(remoteEid_);
        }
        revert LZConfigLib_UnsupportedEid(localEid_);
    }

    /// @notice Returns the executor address for a given V2 EID.
    function executorForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_LZ_EXECUTOR;
        if (eid_ == ARB_EID) return ARB_LZ_EXECUTOR;
        if (eid_ == OPT_EID) return OPT_LZ_EXECUTOR;
        if (eid_ == BASE_EID) return BASE_LZ_EXECUTOR;
        if (eid_ == BERA_EID) return BERA_LZ_EXECUTOR;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the LZ Endpoint address for a given V2 EID.
    function endpointForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_LZ_ENDPOINT;
        if (eid_ == ARB_EID) return ARB_LZ_ENDPOINT;
        if (eid_ == OPT_EID) return OPT_LZ_ENDPOINT;
        if (eid_ == BASE_EID) return BASE_LZ_ENDPOINT;
        if (eid_ == BERA_EID) return BERA_LZ_ENDPOINT;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the LZ DVN address for a given V2 EID.
    function lzDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_LZ_DVN;
        if (eid_ == ARB_EID) return ARB_LZ_DVN;
        if (eid_ == OPT_EID) return OPT_LZ_DVN;
        if (eid_ == BASE_EID) return BASE_LZ_DVN;
        if (eid_ == BERA_EID) return BERA_LZ_DVN;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the Canary DVN address for a given V2 EID.
    function canaryDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_CANARY_DVN;
        if (eid_ == ARB_EID) return ARB_CANARY_DVN;
        if (eid_ == OPT_EID) return OPT_CANARY_DVN;
        if (eid_ == BASE_EID) return BASE_CANARY_DVN;
        if (eid_ == BERA_EID) return BERA_CANARY_DVN;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the Nethermind DVN address for a given V2 EID.
    function nethermindDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_NETHERMIND_DVN;
        if (eid_ == ARB_EID) return ARB_NETHERMIND_DVN;
        if (eid_ == OPT_EID) return OPT_NETHERMIND_DVN;
        if (eid_ == BASE_EID) return BASE_NETHERMIND_DVN;
        if (eid_ == BERA_EID) return BERA_NETHERMIND_DVN;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the Google Cloud DVN address for a given V2 EID.
    /// @dev Not available on Berachain. Use the Horizen DVN for routes touching Berachain.
    function gcloudDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_GCLOUD_DVN;
        if (eid_ == ARB_EID) return ARB_GCLOUD_DVN;
        if (eid_ == OPT_EID) return OPT_GCLOUD_DVN;
        if (eid_ == BASE_EID) return BASE_GCLOUD_DVN;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the Horizen DVN address for a given V2 EID.
    /// @dev Used as the fourth required DVN on routes touching Berachain, where the Google
    ///      Cloud DVN is unavailable.
    function horizenDvnForEid(uint32 eid_) internal pure returns (address) {
        if (eid_ == ETH_EID) return ETH_HORIZEN_DVN;
        if (eid_ == ARB_EID) return ARB_HORIZEN_DVN;
        if (eid_ == OPT_EID) return OPT_HORIZEN_DVN;
        if (eid_ == BASE_EID) return BASE_HORIZEN_DVN;
        if (eid_ == BERA_EID) return BERA_HORIZEN_DVN;
        revert LZConfigLib_UnsupportedEid(eid_);
    }

    /// @notice Returns the four required DVNs for a specific route, sorted ascending.
    /// @dev Every route requires four DVNs: LayerZero Labs, Canary and Nethermind, plus a
    ///      fourth DVN selected per route. Routes that touch Berachain (either as the local
    ///      or remote chain) use the Horizen DVN as the fourth member, since the Google
    ///      Cloud DVN is not deployed on Berachain. All other routes use the Google Cloud
    ///      DVN as the fourth member. The returned addresses are local to `localEid_`.
    /// @param localEid_ The local chain's V2 EID.
    /// @param remoteEid_ The remote chain's V2 EID.
    function dvnsForRoute(
        uint32 localEid_,
        uint32 remoteEid_
    ) internal pure returns (address[] memory dvns) {
        bool involvesBerachain = (localEid_ == BERA_EID || remoteEid_ == BERA_EID);

        dvns = new address[](4);
        dvns[0] = lzDvnForEid(localEid_);
        dvns[1] = canaryDvnForEid(localEid_);
        dvns[2] = nethermindDvnForEid(localEid_);
        dvns[3] = involvesBerachain ? horizenDvnForEid(localEid_) : gcloudDvnForEid(localEid_);

        // Insertion sort to produce an ascending order required by the ULN config.
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
}
