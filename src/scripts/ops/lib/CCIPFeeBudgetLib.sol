// SPDX-License-Identifier: MIT
// solhint-disable custom-errors, one-contract-per-file
// forge-lint: disable-start(require-revert-in-loop, boolean-cst, multi-contract-file)
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

/// @notice The version probe shared by every ramp and fee quoter generation.
interface ICCIPFeeTypeAndVersion {
    /// @notice Returns the type and version string of the contract, `<family> <major>.<minor>.<patch>`.
    /// @return version The type and version string.
    function typeAndVersion() external view returns (string memory version);
}

/// @notice The dynamic configuration getter of the `OnRamp` family (1.6.0 and 2.0.0).
/// @dev Declared without return values on purpose: the layout differs by generation, five
///      words on 1.6.0 (`feeQuoter, reentrancyGuardEntered, messageInterceptor, feeAggregator,
///      allowlistAdmin`) and three on 2.0.0 (`feeQuoter, reentrancyGuardEntered,
///      feeAggregator`), and the reader only needs the fee quoter, which is word zero of both.
///      The return data is read raw and validated by `CCIPFeeBudgetLib`.
interface ICCIPFeeOnRampConfig {
    /// @notice Returns the dynamic configuration of the on-ramp; word zero is the fee quoter.
    function getDynamicConfig() external view;
}

/// @notice The subset of the live `FeeQuoter 2.0.0` surface the fee budget reader uses. It
///         serves the 1.6.0 and the 2.0.0 on-ramps alike.
/// @dev The deployed `FeeQuoter 2.0.0` token transfer fee struct has four fields; the vendored
///      1.6.0 tree carries a six-field struct and must not be used here. The layouts follow
///      `smartcontractkit/chainlink-ccip`, tag `contracts-ccip-v2.0.0`, and are checked against
///      the return data before any field is read.
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
/// @dev A 1.5 lane has no fee quoter; both the per-token entry and the default sit on the
///      lane's dedicated on-ramp. The layouts follow
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
///         the source chain: the fee quoter of an `OnRamp` lane (1.6 or 2.0), or the dedicated
///         on-ramp of a 1.5 lane. The budget must cover the destination `releaseOrMint` sequence;
///         on a burn/mint chain that sequence runs two MINTR calls and does not fit the 90000
///         default, so every lane toward a burn/mint chain must carry an enabled OHM entry of at
///         least `OHM_MIN_DEST_GAS_OVERHEAD` before the route opens.
/// @dev Chainlink migrates lanes between ramp generations and bumps `typeAndVersion` per contract
///      change, so the reader does not pin exact version strings. It dispatches on the contract
///      family and the major version of the on-ramp and of its fee quoter, then checks the form
///      of every return it reads (the word count, and the range of each word it consumes) before
///      taking a value. A patch or minor release that keeps the layouts passes; a new family, a
///      new major, a moved fee quoter or a changed layout fails closed with a message naming the
///      lane and what was read. The residual risk of matching on the major is noted at
///      `_readFeeQuoter`.
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
    string internal constant _OHM_KEY = "olympus.legacy.OHM";

    /// @notice The on-ramp family whose dynamic config names the fee quoter in word zero;
    ///         majors 1 (`OnRamp 1.6.x`) and 2 (`OnRamp 2.x`) are accepted.
    string internal constant _ON_RAMP_FAMILY = "OnRamp";
    uint256 internal constant _ON_RAMP_MIN_MAJOR = 1;
    uint256 internal constant _ON_RAMP_MAX_MAJOR = 2;

    /// @notice The dedicated 1.5 on-ramp family; a frozen line, matched on major and minor.
    string internal constant _LEGACY_ON_RAMP_FAMILY = "EVM2EVMOnRamp";
    uint256 internal constant _LEGACY_ON_RAMP_MAJOR = 1;
    uint256 internal constant _LEGACY_ON_RAMP_MINOR = 5;

    /// @notice The fee quoter family and major whose layouts `ICCIPFeeQuoter20` mirrors.
    string internal constant _FEE_QUOTER_FAMILY = "FeeQuoter";
    uint256 internal constant _FEE_QUOTER_MAJOR = 2;

    /// @notice The `chainFamilySelector` of an EVM destination in the fee quoter config.
    bytes4 internal constant _EVM_CHAIN_FAMILY_SELECTOR = 0x2812d52c;

    // Return shapes, in 32-byte words
    uint256 internal constant _FEE_QUOTER_TOKEN_ENTRY_WORDS = 4;
    uint256 internal constant _FEE_QUOTER_DEST_CONFIG_WORDS = 11;
    uint256 internal constant _LEGACY_TOKEN_ENTRY_WORDS = 7;
    uint256 internal constant _LEGACY_DYNAMIC_CONFIG_WORDS = 13;

    // Positions of the words read, within those returns
    uint256 internal constant _ON_RAMP_FEE_QUOTER_WORD = 0;
    uint256 internal constant _FEE_QUOTER_ENTRY_GAS_WORD = 1;
    uint256 internal constant _FEE_QUOTER_ENTRY_ENABLED_WORD = 3;
    uint256 internal constant _FEE_QUOTER_DEST_FAMILY_WORD = 5;
    uint256 internal constant _FEE_QUOTER_DEST_DEFAULT_GAS_WORD = 7;
    uint256 internal constant _LEGACY_ENTRY_GAS_WORD = 3;
    uint256 internal constant _LEGACY_ENTRY_ENABLED_WORD = 6;
    uint256 internal constant _LEGACY_DYNAMIC_DEFAULT_GAS_WORD = 11;

    // ABI encoding
    uint256 internal constant _WORD_BYTES = 32;
    uint256 internal constant _MIN_STRING_RETURN_BYTES = 64;
    uint256 internal constant _ADDRESS_BITS = 160;
    uint256 internal constant _UINT32_BITS = 32;
    uint256 internal constant _BOOL_BITS = 1;
    uint256 internal constant _TRUE_WORD = 1;

    // ASCII of a `typeAndVersion` string, and the digit bound of a version component (the width
    // of a `uint32`)
    bytes1 internal constant _SPACE = 0x20;
    bytes1 internal constant _DOT = 0x2e;
    uint8 internal constant _DIGIT_ZERO = 0x30;
    uint8 internal constant _DIGIT_NINE = 0x39;
    uint256 internal constant _DECIMAL_BASE = 10;
    uint256 internal constant _MAX_VERSION_DIGITS = 10;

    // ========== DATA STRUCTURES ========== //

    /// @notice A parsed `typeAndVersion` string.
    /// @param raw The string as returned by the contract.
    /// @param family The name part, everything before the last space.
    /// @param major The major version.
    /// @param minor The minor version.
    struct TypeAndVersion {
        string raw;
        string family;
        uint256 major;
        uint256 minor;
    }

    // ========== READS ========== //

    /// @notice Reads the OHM delivery gas budget of the lane from `localChain_` to
    ///         `remoteChain_`, together with whether it comes from an enabled OHM token entry
    ///         and a description of where the value came from.
    /// @dev Fails closed: reverts when the local router carries no lane to the destination, when
    ///      the on-ramp or its fee quoter is of an unsupported family or major version, or when
    ///      a return does not have the expected form.
    /// @param env_ The contents of `env.json`.
    /// @param localChain_ The source chain of the lane.
    /// @param remoteChain_ The destination chain of the lane.
    /// @return overhead The applicable `destGasOverhead` in gas units.
    /// @return isTokenEntry True when the value comes from an enabled OHM token entry, false
    ///         when it is the chain default.
    /// @return source A description of the read: token entry or chain default, and the
    ///         `typeAndVersion` strings of the contracts it came from.
    function readOhmDestGasOverhead(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) internal view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        string memory lane = string.concat(localChain_, " -> ", remoteChain_);
        address router = _envAddress(env_, localChain_, _ROUTER_KEY);
        address ohm = _envAddress(env_, localChain_, _OHM_KEY);
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

        TypeAndVersion memory onRampVersion = _readTypeAndVersion(onRamp, "on-ramp", lane);
        if (
            _isFamily(onRampVersion, _ON_RAMP_FAMILY) &&
            onRampVersion.major >= _ON_RAMP_MIN_MAJOR &&
            onRampVersion.major <= _ON_RAMP_MAX_MAJOR
        ) {
            return _readViaFeeQuoter(onRamp, onRampVersion.raw, destSelector, ohm, lane);
        }
        if (
            _isFamily(onRampVersion, _LEGACY_ON_RAMP_FAMILY) &&
            onRampVersion.major == _LEGACY_ON_RAMP_MAJOR &&
            onRampVersion.minor == _LEGACY_ON_RAMP_MINOR
        ) {
            return _read15(onRamp, onRampVersion.raw, ohm, lane);
        }
        revert(
            string.concat(
                "CCIPFeeBudgetLib: unsupported on-ramp version '",
                onRampVersion.raw,
                "' on the lane ",
                lane
            )
        );
    }

    /// @notice Reverts unless the lane from `localChain_` to `remoteChain_` carries an enabled
    ///         OHM token entry of at least `OHM_MIN_DEST_GAS_OVERHEAD`.
    /// @dev Intended for lanes whose destination is a burn/mint chain; the caller selects them.
    ///      A raised chain default is not accepted: the default is shared by every token of the
    ///      destination and gives no per-token guarantee, so only an enabled OHM entry passes.
    function requireOhmFeeBudget(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) internal view {
        (uint32 overhead, bool isTokenEntry, string memory source) = readOhmDestGasOverhead(
            env_,
            localChain_,
            remoteChain_
        );
        require(
            isTokenEntry,
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane ",
                localChain_,
                " -> ",
                remoteChain_,
                " has no enabled OHM token entry (the applicable value is the chain default ",
                _VM.toString(overhead),
                "; ",
                source,
                "); request an enabled OHM fee entry of at least ",
                _VM.toString(uint256(OHM_MIN_DEST_GAS_OVERHEAD)),
                " from Chainlink before opening the route"
            )
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

    // ========== VERSION PARSING ========== //

    /// @notice Parses a `typeAndVersion` string of the form `<family> <major>.<minor>[.<patch>][-<suffix>]`.
    /// @dev The family is everything before the last space; the major and the minor are the
    ///      decimal runs before and after the first dot of the rest. The patch and any suffix
    ///      (`1.6.1-dev`) are ignored. Returns `ok` false when the string has no space, no
    ///      family, no major digits, no dot or no minor digits.
    /// @param raw_ The string to parse.
    /// @return version The parsed string; meaningless when `ok` is false.
    /// @return ok Whether the string had the expected form.
    // forge-lint: disable-next-item(internal-function-used-once)
    function parseTypeAndVersion(
        string memory raw_
    ) internal pure returns (TypeAndVersion memory version, bool ok) {
        bytes memory raw = bytes(raw_);
        uint256 length = raw.length;

        // The last space separates the family from the version
        uint256 split = length;
        for (uint256 i = length; i > 0; --i) {
            if (raw[i - 1] == _SPACE) {
                split = i - 1;
                break;
            }
        }
        if (split == length || split == 0) return (version, false);

        (uint256 major, uint256 majorDigits, uint256 next) = _parseDigits(raw, split + 1);
        if (majorDigits == 0 || next >= length || raw[next] != _DOT) return (version, false);
        (uint256 minor, uint256 minorDigits, ) = _parseDigits(raw, next + 1);
        if (minorDigits == 0) return (version, false);

        bytes memory family = new bytes(split);
        for (uint256 i = 0; i < split; ++i) {
            family[i] = raw[i];
        }

        return (
            TypeAndVersion({raw: raw_, family: string(family), major: major, minor: minor}),
            true
        );
    }

    // ========== INTERNAL ========== //

    /// @dev Reads and parses `typeAndVersion()` of a contract; reverts when the call fails or
    ///      the string does not parse.
    function _readTypeAndVersion(
        address target_,
        string memory label_,
        string memory lane_
    ) private view returns (TypeAndVersion memory version) {
        require(
            target_.code.length != 0,
            string.concat("CCIPFeeBudgetLib: the ", label_, " of the lane ", lane_, " has no code")
        );
        // The return is measured and decoded by hand
        // forge-lint: disable-next-item(low-level-calls)
        (bool ok, bytes memory data) = target_.staticcall(
            abi.encodeCall(ICCIPFeeTypeAndVersion.typeAndVersion, ())
        );
        require(
            ok && data.length >= _MIN_STRING_RETURN_BYTES,
            string.concat(
                "CCIPFeeBudgetLib: the ",
                label_,
                " of the lane ",
                lane_,
                " does not answer typeAndVersion()"
            )
        );
        string memory raw = abi.decode(data, (string));
        bool parsed;
        (version, parsed) = parseTypeAndVersion(raw);
        require(
            parsed,
            string.concat(
                "CCIPFeeBudgetLib: the ",
                label_,
                " of the lane ",
                lane_,
                " reports typeAndVersion '",
                raw,
                "', not a '<family> <major>.<minor>' string"
            )
        );
    }

    /// @dev Reads the fee quoter named by word zero of the on-ramp's dynamic config, requires
    ///      it to be a `FeeQuoter` of the supported major, and reads the budget from it. Only
    ///      word zero of the on-ramp config is read, so a generation that appends members keeps
    ///      working; one that moves the fee quoter out of word zero resolves to a contract that
    ///      fails the version check and fails closed.
    function _readViaFeeQuoter(
        address onRamp_,
        string memory onRampVersion_,
        uint64 destSelector_,
        address ohm_,
        string memory lane_
    ) private view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        // The return is read raw: its length differs by generation
        // forge-lint: disable-next-item(low-level-calls)
        (bool ok, bytes memory data) = onRamp_.staticcall(
            abi.encodeCall(ICCIPFeeOnRampConfig.getDynamicConfig, ())
        );
        require(
            ok && data.length >= _WORD_BYTES,
            string.concat(
                "CCIPFeeBudgetLib: the on-ramp of the lane ",
                lane_,
                " does not answer getDynamicConfig()"
            )
        );
        _requireWordFits(
            data,
            _ON_RAMP_FEE_QUOTER_WORD,
            _ADDRESS_BITS,
            "getDynamicConfig().feeQuoter",
            lane_
        );
        // casting to 'address' is safe because the word is checked to fit 160 bits above
        // forge-lint: disable-next-line(unsafe-typecast)
        address feeQuoter = address(uint160(_word(data, _ON_RAMP_FEE_QUOTER_WORD)));
        require(
            feeQuoter != address(0),
            string.concat("CCIPFeeBudgetLib: the on-ramp of the lane ", lane_, " has no fee quoter")
        );

        TypeAndVersion memory quoterVersion = _readTypeAndVersion(feeQuoter, "fee quoter", lane_);
        require(
            _isFamily(quoterVersion, _FEE_QUOTER_FAMILY) &&
                quoterVersion.major == _FEE_QUOTER_MAJOR,
            string.concat(
                "CCIPFeeBudgetLib: unsupported fee quoter version '",
                quoterVersion.raw,
                "' on the lane ",
                lane_
            )
        );

        return
            _readFeeQuoter(
                feeQuoter,
                destSelector_,
                ohm_,
                string.concat(quoterVersion.raw, " via ", onRampVersion_),
                lane_
            );
    }

    /// @dev Reads the OHM entry, then the chain default, from a `FeeQuoter` of major 2, checking
    ///      the form of each return before reading a word of it: the token entry must be four
    ///      words with `uint32` values and a `bool`, the destination config eleven words with
    ///      the EVM chain family selector in word five.
    ///
    ///      Residual risk of matching on the major rather than on the exact version: a
    ///      `FeeQuoter 2.x` that reordered the four-word token entry while keeping its word
    ///      count would pass this check. Within that entry the only numeric fields besides
    ///      `destGasOverhead` are a fee in USD cents and a byte count, so a reorder can only
    ///      lower the value read and the budget check fails closed; the chain default read
    ///      here is reported but never accepted by `requireOhmFeeBudget`, so a misread of it
    ///      cannot open the gate either. A change that adds or removes a word, or bumps the
    ///      major, fails closed on the checks above.
    function _readFeeQuoter(
        address feeQuoter_,
        uint64 destSelector_,
        address ohm_,
        string memory versions_,
        string memory lane_
    ) private view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        // The returns are shape-checked word by word before a field is read
        // forge-lint: disable-next-item(low-level-calls)
        (bool ok, bytes memory data) = feeQuoter_.staticcall(
            abi.encodeCall(ICCIPFeeQuoter20.getTokenTransferFeeConfig, (destSelector_, ohm_))
        );
        _requireWords(ok, data, _FEE_QUOTER_TOKEN_ENTRY_WORDS, "getTokenTransferFeeConfig", lane_);
        _requireWordFits(
            data,
            _FEE_QUOTER_ENTRY_GAS_WORD,
            _UINT32_BITS,
            "getTokenTransferFeeConfig().destGasOverhead",
            lane_
        );
        _requireWordFits(
            data,
            _FEE_QUOTER_ENTRY_ENABLED_WORD,
            _BOOL_BITS,
            "getTokenTransferFeeConfig().isEnabled",
            lane_
        );
        if (_word(data, _FEE_QUOTER_ENTRY_ENABLED_WORD) == _TRUE_WORD) {
            // casting to 'uint32' is safe because the word is checked to fit 32 bits above
            return (
                // forge-lint: disable-next-line(unsafe-typecast)
                uint32(_word(data, _FEE_QUOTER_ENTRY_GAS_WORD)),
                true,
                string.concat("OHM token entry, ", versions_)
            );
        }

        // forge-lint: disable-next-item(low-level-calls)
        (ok, data) = feeQuoter_.staticcall(
            abi.encodeCall(ICCIPFeeQuoter20.getDestChainConfig, (destSelector_))
        );
        _requireWords(ok, data, _FEE_QUOTER_DEST_CONFIG_WORDS, "getDestChainConfig", lane_);
        _requireChainFamily(data, _FEE_QUOTER_DEST_FAMILY_WORD, lane_);
        _requireWordFits(
            data,
            _FEE_QUOTER_DEST_DEFAULT_GAS_WORD,
            _UINT32_BITS,
            "getDestChainConfig().defaultTokenDestGasOverhead",
            lane_
        );
        // casting to 'uint32' is safe because the word is checked to fit 32 bits above
        return (
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32(_word(data, _FEE_QUOTER_DEST_DEFAULT_GAS_WORD)),
            false,
            string.concat("chain default, ", versions_, " (no OHM entry)")
        );
    }

    /// @dev Reads the OHM entry, then the lane default, from a dedicated `EVM2EVMOnRamp 1.5`,
    ///      checking the form of each return: seven words for the token entry, thirteen for the
    ///      dynamic config.
    function _read15(
        address onRamp_,
        string memory onRampVersion_,
        address ohm_,
        string memory lane_
    ) private view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        // The returns are shape-checked word by word before a field is read
        // forge-lint: disable-next-item(low-level-calls)
        (bool ok, bytes memory data) = onRamp_.staticcall(
            abi.encodeCall(ICCIPFeeOnRamp15.getTokenTransferFeeConfig, (ohm_))
        );
        _requireWords(ok, data, _LEGACY_TOKEN_ENTRY_WORDS, "getTokenTransferFeeConfig", lane_);
        _requireWordFits(
            data,
            _LEGACY_ENTRY_GAS_WORD,
            _UINT32_BITS,
            "getTokenTransferFeeConfig().destGasOverhead",
            lane_
        );
        _requireWordFits(
            data,
            _LEGACY_ENTRY_ENABLED_WORD,
            _BOOL_BITS,
            "getTokenTransferFeeConfig().isEnabled",
            lane_
        );
        if (_word(data, _LEGACY_ENTRY_ENABLED_WORD) == _TRUE_WORD) {
            // casting to 'uint32' is safe because the word is checked to fit 32 bits above
            return (
                // forge-lint: disable-next-line(unsafe-typecast)
                uint32(_word(data, _LEGACY_ENTRY_GAS_WORD)),
                true,
                string.concat("OHM token entry, ", onRampVersion_)
            );
        }

        // forge-lint: disable-next-item(low-level-calls)
        (ok, data) = onRamp_.staticcall(abi.encodeCall(ICCIPFeeOnRamp15.getDynamicConfig, ()));
        _requireWords(ok, data, _LEGACY_DYNAMIC_CONFIG_WORDS, "getDynamicConfig", lane_);
        _requireWordFits(
            data,
            _LEGACY_DYNAMIC_DEFAULT_GAS_WORD,
            _UINT32_BITS,
            "getDynamicConfig().defaultTokenDestGasOverhead",
            lane_
        );
        // casting to 'uint32' is safe because the word is checked to fit 32 bits above
        return (
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32(_word(data, _LEGACY_DYNAMIC_DEFAULT_GAS_WORD)),
            false,
            string.concat("chain default, ", onRampVersion_, " (no OHM entry)")
        );
    }

    /// @dev Reverts unless the call succeeded and returned exactly `words_` words.
    function _requireWords(
        bool ok_,
        bytes memory data_,
        uint256 words_,
        string memory call_,
        string memory lane_
    ) private pure {
        require(
            ok_,
            string.concat("CCIPFeeBudgetLib: ", call_, " reverted on the lane ", lane_)
        );
        require(
            data_.length == words_ * _WORD_BYTES,
            string.concat(
                "CCIPFeeBudgetLib: ",
                call_,
                " on the lane ",
                lane_,
                " returned ",
                _VM.toString(data_.length / _WORD_BYTES),
                " words, expected ",
                _VM.toString(words_)
            )
        );
    }

    /// @dev Reverts unless word `index_` of `data_` fits in `bits_` bits (a `bool` is one bit).
    function _requireWordFits(
        bytes memory data_,
        uint256 index_,
        uint256 bits_,
        string memory field_,
        string memory lane_
    ) private pure {
        require(
            _word(data_, index_) >> bits_ == 0,
            string.concat(
                "CCIPFeeBudgetLib: ",
                field_,
                " on the lane ",
                lane_,
                " does not fit its type; the layout differs from the supported one"
            )
        );
    }

    /// @dev Reverts unless word `index_` of `data_` is the left-aligned EVM chain family selector.
    function _requireChainFamily(
        bytes memory data_,
        uint256 index_,
        string memory lane_
    ) private pure {
        bytes32 word = bytes32(_word(data_, index_));
        // casting to 'bytes4' is intended: the selector is the left-aligned first four bytes,
        // and the second clause requires the remaining bytes to be zero
        require(
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4(word) == _EVM_CHAIN_FAMILY_SELECTOR && (uint256(word) << 32) == 0,
            string.concat(
                "CCIPFeeBudgetLib: getDestChainConfig().chainFamilySelector on the lane ",
                lane_,
                " is ",
                _VM.toString(word),
                ", expected the EVM family; the layout or the destination differs from the supported one"
            )
        );
    }

    function _word(bytes memory data_, uint256 index_) private pure returns (uint256 word) {
        // A word read past the length word of the array; the caller has checked the length
        // solhint-disable-next-line no-inline-assembly
        // forge-lint: disable-next-item(inline-assembly)
        assembly {
            word := mload(add(add(data_, _WORD_BYTES), mul(index_, _WORD_BYTES)))
        }
    }

    function _isFamily(
        TypeAndVersion memory version_,
        string memory family_
    ) private pure returns (bool same) {
        return keccak256(bytes(version_.family)) == keccak256(bytes(family_));
    }

    /// @dev Parses the run of ASCII digits starting at `from_`.
    /// @return value The parsed value.
    /// @return digits The number of digits consumed.
    /// @return next The index after the last digit.
    function _parseDigits(
        bytes memory raw_,
        uint256 from_
    ) private pure returns (uint256 value, uint256 digits, uint256 next) {
        next = from_;
        while (next < raw_.length) {
            uint8 char = uint8(raw_[next]);
            if (char < _DIGIT_ZERO || char > _DIGIT_NINE) break;
            // A version component longer than the digit bound is not a version
            if (digits == _MAX_VERSION_DIGITS) return (0, 0, from_);
            value = value * _DECIMAL_BASE + (char - _DIGIT_ZERO);
            ++digits;
            ++next;
        }
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
