// SPDX-License-Identifier: MIT
// solhint-disable custom-errors, one-contract-per-file
pragma solidity ^0.8.24;

// Scripting
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";

/// @notice The subset of the Chainlink `Router 1.2.0` surface the fee budget reader uses.
/// @dev The interfaces of this file mirror the live deployed ABIs rather than the vendored
///      1.6.0 tree, whose fee structs differ from the deployed `FeeQuoter 2.0.0`; they are
///      script-local on purpose and must not be used by on-chain contracts.
interface ICCIPFeeRouter {
    /// @notice Returns the on-ramp serving a destination chain, or the zero address when the
    ///         local router carries no lane to it.
    /// @param destChainSelector The chain selector of the destination.
    /// @return onRamp The on-ramp address, or the zero address.
    function getOnRamp(uint64 destChainSelector) external view returns (address onRamp);
}

/// @notice The version probe shared by both on-ramp generations.
interface ICCIPFeeTypeAndVersion {
    /// @notice Returns the type and version string of the contract.
    /// @return version The type and version string.
    function typeAndVersion() external view returns (string memory version);
}

/// @notice The subset of the live `OnRamp 1.6.0` surface the fee budget reader uses.
interface ICCIPFeeOnRamp16 {
    /// @param feeQuoter The fee quoter every fee and budget read goes through.
    /// @param reentrancyGuardEntered The transient reentrancy flag.
    /// @param messageInterceptor The optional aggregate rate limiter, or the zero address.
    /// @param feeAggregator The recipient of accumulated fees.
    /// @param allowlistAdmin The optional allowlist administrator.
    struct DynamicConfig {
        address feeQuoter;
        bool reentrancyGuardEntered;
        address messageInterceptor;
        address feeAggregator;
        address allowlistAdmin;
    }

    /// @notice Returns the dynamic configuration of the on-ramp.
    /// @return config The dynamic configuration, whose first member is the fee quoter.
    function getDynamicConfig() external view returns (DynamicConfig memory config);
}

/// @notice The subset of the live `FeeQuoter 2.0.0` surface the fee budget reader uses.
/// @dev The deployed `FeeQuoter 2.0.0` token transfer fee struct has four fields; the vendored
///      1.6.0 tree carries a six-field struct and must not be used here. The layouts follow
///      `smartcontractkit/chainlink-ccip` main, the source with the same `typeAndVersion`.
interface ICCIPFeeQuoter20 {
    /// @param feeUSDCents The minimum fee to charge per token transfer, in 0.01 USD.
    /// @param destGasOverhead The gas charged to execute the token transfer on the destination.
    /// @param destBytesOverhead The data availability bytes returned by the source pool.
    /// @param isEnabled Whether the token has a custom transfer fee entry.
    struct TokenTransferFeeConfig {
        uint32 feeUSDCents;
        uint32 destGasOverhead;
        uint32 destBytesOverhead;
        bool isEnabled;
    }

    /// @param isEnabled Whether the destination chain is enabled.
    /// @param maxDataBytes The maximum message data size.
    /// @param maxPerMsgGasLimit The maximum requestable execution gas.
    /// @param destGasOverhead The fixed message execution overhead (not the token budget).
    /// @param destGasPerPayloadByteBase The per-byte execution gas.
    /// @param chainFamilySelector The chain family identifier.
    /// @param defaultTokenFeeUSDCents The token fee for tokens without an entry.
    /// @param defaultTokenDestGasOverhead The token delivery budget for tokens without an entry.
    /// @param defaultTxGasLimit The default execution gas limit.
    /// @param networkFeeUSDCents The flat network fee.
    /// @param linkFeeMultiplierPercent The LINK fee discount multiplier.
    struct DestChainConfig {
        bool isEnabled;
        uint32 maxDataBytes;
        uint32 maxPerMsgGasLimit;
        uint32 destGasOverhead;
        uint8 destGasPerPayloadByteBase;
        bytes4 chainFamilySelector;
        uint16 defaultTokenFeeUSDCents;
        uint32 defaultTokenDestGasOverhead;
        uint32 defaultTxGasLimit;
        uint16 networkFeeUSDCents;
        uint8 linkFeeMultiplierPercent;
    }

    /// @notice Returns the token transfer fee entry of a token toward a destination chain.
    /// @param destChainSelector The chain selector of the destination.
    /// @param token The local token address.
    /// @return config The fee entry; `isEnabled` false means the chain default applies.
    function getTokenTransferFeeConfig(
        uint64 destChainSelector,
        address token
    ) external view returns (TokenTransferFeeConfig memory config);

    /// @notice Returns the configuration of a destination chain, including the default token
    ///         delivery gas budget.
    /// @param destChainSelector The chain selector of the destination.
    /// @return config The destination chain configuration.
    function getDestChainConfig(
        uint64 destChainSelector
    ) external view returns (DestChainConfig memory config);
}

/// @notice The subset of the live `EVM2EVMOnRamp 1.5.0` surface the fee budget reader uses.
/// @dev The 1.5 lanes (every lane touching Optimism or Berachain) have no fee quoter; both the
///      per-token entry and the default sit on the lane's dedicated on-ramp. The layouts follow
///      `smartcontractkit/ccip` release/contracts-ccip-1.5.0; the 1.5 sources are not vendored.
interface ICCIPFeeOnRamp15 {
    /// @param minFeeUSDCents The minimum fee per token transfer, in 0.01 USD.
    /// @param maxFeeUSDCents The maximum fee per token transfer, in 0.01 USD.
    /// @param deciBps The basis point fee in 0.1 bps.
    /// @param destGasOverhead The gas charged to execute the token transfer on the destination.
    /// @param destBytesOverhead The data availability bytes returned by the source pool.
    /// @param aggregateRateLimitEnabled Whether the transfer counts toward the aggregate limiter.
    /// @param isEnabled Whether the token has a custom transfer fee entry.
    struct TokenTransferFeeConfig {
        uint32 minFeeUSDCents;
        uint32 maxFeeUSDCents;
        uint16 deciBps;
        uint32 destGasOverhead;
        uint32 destBytesOverhead;
        bool aggregateRateLimitEnabled;
        bool isEnabled;
    }

    /// @param router The local router.
    /// @param maxNumberOfTokensPerMsg The token count cap per message.
    /// @param destGasOverhead The fixed message execution overhead (not the token budget).
    /// @param destGasPerPayloadByte The per-byte execution gas.
    /// @param destDataAvailabilityOverheadGas The data availability overhead.
    /// @param destGasPerDataAvailabilityByte The per-byte data availability gas.
    /// @param destDataAvailabilityMultiplierBps The data availability multiplier.
    /// @param priceRegistry The 1.2.0 price registry quoting this lane.
    /// @param maxDataBytes The maximum message data size.
    /// @param maxPerMsgGasLimit The maximum requestable execution gas.
    /// @param defaultTokenFeeUSDCents The token fee for tokens without an entry.
    /// @param defaultTokenDestGasOverhead The token delivery budget for tokens without an entry.
    /// @param enforceOutOfOrder Whether out-of-order execution is mandatory.
    struct DynamicConfig {
        address router;
        uint16 maxNumberOfTokensPerMsg;
        uint32 destGasOverhead;
        uint16 destGasPerPayloadByte;
        uint32 destDataAvailabilityOverheadGas;
        uint16 destGasPerDataAvailabilityByte;
        uint16 destDataAvailabilityMultiplierBps;
        address priceRegistry;
        uint32 maxDataBytes;
        uint32 maxPerMsgGasLimit;
        uint16 defaultTokenFeeUSDCents;
        uint32 defaultTokenDestGasOverhead;
        bool enforceOutOfOrder;
    }

    /// @notice Returns the token transfer fee entry of a token on this lane.
    /// @param token The local token address.
    /// @return config The fee entry; `isEnabled` false means the lane default applies.
    function getTokenTransferFeeConfig(
        address token
    ) external view returns (TokenTransferFeeConfig memory config);

    /// @notice Returns the dynamic configuration of the on-ramp, including the default token
    ///         delivery gas budget.
    /// @return config The dynamic configuration.
    function getDynamicConfig() external view returns (DynamicConfig memory config);
}

/// @title CCIPFeeBudgetLib
/// @notice Reads the OHM token delivery gas budget of a CCIP lane from the live fee contracts of
///         the source chain: the fee quoter of a 1.6 lane, or the dedicated on-ramp of a 1.5
///         lane. The budget must cover the destination `releaseOrMint` sequence; on a burn/mint
///         chain that sequence runs two MINTR calls and does not fit the 90000 default, so every
///         lane toward a burn/mint chain must carry an enabled OHM entry of at least
///         `OHM_MIN_DEST_GAS_OVERHEAD` before the route opens.
library CCIPFeeBudgetLib {
    // ========== CONSTANTS ========== //

    VmSafe internal constant _VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice The minimum OHM delivery gas budget of a lane toward a burn/mint chain.
    /// @dev The destination sequence (`balanceOf`, `releaseOrMint` with both MINTR calls,
    ///      `balanceOf`) exceeds the 90000 chain default; 175000 covers it with headroom. Only
    ///      Chainlink can write the entry, so the deployment is gated on an external request per
    ///      lane.
    uint32 internal constant OHM_MIN_DEST_GAS_OVERHEAD = 175_000;

    string internal constant _ROUTER_KEY = "external.ccip.Router";
    string internal constant _ONRAMP_16 = "OnRamp 1.6.0";
    string internal constant _ONRAMP_15 = "EVM2EVMOnRamp 1.5.0";

    // ========== READS ========== //

    /// @notice Reads the OHM delivery gas budget of the lane from `localChain_` to
    ///         `remoteChain_`, together with a description of where the value came from.
    /// @dev Fails closed: reverts when the local router carries no lane to the destination or
    ///      when the on-ramp reports an unsupported version.
    /// @param env_ The contents of `env.json`.
    /// @param localChain_ The source chain of the lane.
    /// @param remoteChain_ The destination chain of the lane.
    /// @return overhead The applicable `destGasOverhead` in gas units.
    /// @return source A description of the read (token entry or chain default, and the version).
    function readOhmDestGasOverhead(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) internal view returns (uint32 overhead, string memory source) {
        address router = _envAddress(env_, localChain_, _ROUTER_KEY);
        address ohm = _envAddress(env_, localChain_, "olympus.legacy.OHM");
        uint64 destSelector = CCIPConfigLib.chainSelector(env_, remoteChain_);

        address onRamp = ICCIPFeeRouter(router).getOnRamp(destSelector);
        require(
            onRamp != address(0),
            string.concat(
                "CCIPFeeBudgetLib: the ",
                localChain_,
                " router has no on-ramp for ",
                remoteChain_
            )
        );

        string memory version = ICCIPFeeTypeAndVersion(onRamp).typeAndVersion();
        bytes32 versionHash = keccak256(bytes(version));
        if (versionHash == keccak256(bytes(_ONRAMP_16))) {
            return _read16(onRamp, destSelector, ohm);
        }
        if (versionHash == keccak256(bytes(_ONRAMP_15))) {
            return _read15(onRamp, ohm);
        }
        revert(
            string.concat(
                "CCIPFeeBudgetLib: unsupported on-ramp version '",
                version,
                "' on the lane ",
                localChain_,
                " -> ",
                remoteChain_
            )
        );
    }

    /// @notice Reverts unless the lane from `localChain_` to `remoteChain_` carries an enabled
    ///         OHM entry (or default) of at least `OHM_MIN_DEST_GAS_OVERHEAD`.
    /// @dev Intended for lanes whose destination is a burn/mint chain; the caller selects them.
    function requireOhmFeeBudget(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) internal view {
        (uint32 overhead, string memory source) = readOhmDestGasOverhead(
            env_,
            localChain_,
            remoteChain_
        );
        require(
            overhead >= OHM_MIN_DEST_GAS_OVERHEAD,
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                localChain_,
                " -> ",
                remoteChain_,
                " is ",
                _VM.toString(overhead),
                " (",
                source,
                "), below the required ",
                _VM.toString(uint256(OHM_MIN_DEST_GAS_OVERHEAD)),
                "; request an enabled OHM fee entry from Chainlink before opening the route"
            )
        );
    }

    // ========== INTERNAL ========== //

    function _read16(
        address onRamp_,
        uint64 destSelector_,
        address ohm_
    ) private view returns (uint32 overhead, string memory source) {
        address feeQuoter = ICCIPFeeOnRamp16(onRamp_).getDynamicConfig().feeQuoter;
        require(feeQuoter != address(0), "CCIPFeeBudgetLib: the 1.6 on-ramp has no fee quoter");
        ICCIPFeeQuoter20.TokenTransferFeeConfig memory entry = ICCIPFeeQuoter20(feeQuoter)
            .getTokenTransferFeeConfig(destSelector_, ohm_);
        if (entry.isEnabled) {
            return (entry.destGasOverhead, "OHM token entry, FeeQuoter 2.0.0");
        }
        return (
            ICCIPFeeQuoter20(feeQuoter).getDestChainConfig(destSelector_).defaultTokenDestGasOverhead,
            "chain default, FeeQuoter 2.0.0 (no OHM entry)"
        );
    }

    function _read15(
        address onRamp_,
        address ohm_
    ) private view returns (uint32 overhead, string memory source) {
        ICCIPFeeOnRamp15.TokenTransferFeeConfig memory entry = ICCIPFeeOnRamp15(onRamp_)
            .getTokenTransferFeeConfig(ohm_);
        if (entry.isEnabled) {
            return (entry.destGasOverhead, "OHM token entry, EVM2EVMOnRamp 1.5.0");
        }
        return (
            ICCIPFeeOnRamp15(onRamp_).getDynamicConfig().defaultTokenDestGasOverhead,
            "chain default, EVM2EVMOnRamp 1.5.0 (no OHM entry)"
        );
    }

    function _envAddress(
        string memory env_,
        string memory chain_,
        string memory key_
    ) private view returns (address value) {
        string memory path = string.concat(".current.", chain_, ".", key_);
        require(
            _VM.keyExistsJson(env_, path),
            string.concat("CCIPFeeBudgetLib: missing env.json key ", path)
        );
        value = _VM.parseJsonAddress(env_, path);
        require(value != address(0), string.concat("CCIPFeeBudgetLib: zero address for ", path));
    }
}
