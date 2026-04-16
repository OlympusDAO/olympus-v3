// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StdConfig} from "forge-std/StdConfig.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IAaveV3DataProvider} from "src/external/interfaces/IAaveV3DataProvider.sol";
import {IAaveV3Pool} from "src/external/interfaces/IAaveV3Pool.sol";
import {FullMath} from "src/libraries/FullMath.sol";

/// @title SUSDeAaveLoop
/// @notice Batch script to execute sUSDe Aave loop yield strategy
/// @dev    Strategy: Supply sUSDe → Borrow USDT → Swap to USDe → Supply USDe → Borrow USDT → Swap to sUSDe
///         Single function builds one full loop iteration batch
///
///         Aave Pool: Ethereum Core Pool (includes sUSDe, USDe, USDT, and many other assets)
///         Pool Address: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
///
///         DECIMAL SCALE ASSUMPTIONS:
///         - sUSDe: 18 decimals
///         - USDe:  18 decimals
///         - USDT:  6 decimals
///         - Aave base currency (USD): 8 decimals
///
///         KEY CONVERSIONS:
///         - Aave returns `availableBorrowsBase` in 8 decimals (USD)
///         - borrow() expects amount in asset's native decimals (6 for USDT)
///         - For USDT ~$1: USDT_amount = base_amount / 100 (8 dec → 6 dec)
///         - For sUSDe ~$1: base_amount = sUSDe_amount * 10^8 / 10^18 (18 dec → 8 dec)
///         - eMode category 2 LTV: 90% = 9000 bps (sUSDe reserve LTV is 0, only usable in eMode)
contract SUSDeAaveLoop is BatchScriptV2 {
    using stdJson for string;
    using Surl for *;

    enum CacheMode {
        None,
        ExecuteLoop,
        ExecuteUnwind,
        ExecuteRebalance
    }

    // Hardcoded protocol addresses (specific to this script)
    IAaveV3Pool internal constant AAVE_POOL =
        IAaveV3Pool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IAaveV3DataProvider internal constant AAVE_DATA_PROVIDER =
        IAaveV3DataProvider(0x41393e5e337606dc3821075Af65AeE84D7688CBD);
    address internal constant KYBERSWAP_ROUTER_FALLBACK =
        0x6131B37d65fE405d9820C9B10FBb9a118BA031B3;

    // Token addresses (loaded from env.json)
    IERC20 internal _susde;
    IERC20 internal _usde;
    IERC20 internal _usdt;

    // Expected post-batch state for validation
    uint256 internal _expectedMinSusdeOut;
    uint256 internal _initialSusdeBalance;
    uint256 internal _sweepWalletUsdeAmount;
    uint256 internal _sweepInitialWalletUsdeBalance;
    uint256 internal _sweepInitialWalletSusdeBalance;
    uint256 internal _susdeSuppliedAmount;
    uint256 internal _usdeSuppliedAmount;
    uint256 internal _plannedUsdeSweepToSusdeAmount;
    uint256 internal _initialTotalCollateralBase;
    uint256 internal _initialTotalDebtBase;
    uint256 internal _initialNetAccountValueBase;
    uint256 internal _expectedMinHealthFactor;
    uint256 internal _expectedMaxDebtBase;
    uint256 internal _unwindSlippageBps;
    uint256 internal _unwindMinHealthFactor;
    uint256 internal _unwindMinSwap1ValueRatioBps;
    uint256 internal _unwindMinSwap2ValueRatioBps;
    uint256 internal _unwindMaxSusdeSwapIn;
    uint256 internal _loopActionsBaseStep;
    uint256 internal _loopTargetSusdeShareBps;
    bool internal _loopImbalanceBeforeSusdeOverweight;
    uint256 internal _loopImbalanceBeforeAbsUsde;
    uint256 internal _loopSusdeCollateralValueUsdeBefore;
    uint256 internal _loopUsdeCollateralValueUsdeBefore;
    bool internal _loopImbalancePostSusdeSupplySusdeOverweight;
    uint256 internal _loopImbalancePostSusdeSupplyAbsUsde;
    uint256 internal _loopUsdeSupplyCapTarget;
    bool internal _loopProjectedImbalanceSusdeOverweight;
    uint256 internal _loopProjectedImbalanceAbsUsde;
    bool internal _rebalanceImbalanceBeforeSusdeOverweight;
    uint256 internal _rebalanceImbalanceBeforeAbsUsde;
    uint256 internal _rebalanceImbalanceToleranceUsde;
    uint256 internal _rebalanceTargetSusdeShareBps;
    uint256 internal _rebalanceTargetShiftUsde;
    uint256 internal _rebalancePlannedShiftUsde;
    string internal _rebalancePartialReason;
    string internal _kyberExcludedSources;
    BalanceSheetSnapshot internal _initialBalanceSheet;

    struct UnwindConfig {
        uint256 slippageBps;
        uint256 minHealthFactor;
        uint256 minSwap1ValueRatioBps;
        uint256 minSwap2ValueRatioBps;
        uint256 maxSusdeSwapIn;
    }

    struct UnwindPlan {
        uint256 conservativeRepay0;
        uint256 conservativeRepay1;
        uint256 conservativeRepay2;
        uint256 walletSusdeSwapAmount;
        uint256 usdeWithdrawAmount1;
        uint256 susdeSwapAmount;
        uint256 usdeWithdrawAmountFinal;
        uint256 susdeWithdrawAmountFinal;
        uint256 debtAfterStep2;
        address routerWalletSusdeToUsdt;
        bytes swapCalldataWalletSusdeToUsdt;
        address routerUsdeToUsdt;
        bytes swapCalldataUsdeToUsdt;
        address routerSusdeToUsdt;
        bytes swapCalldataSusdeToUsdt;
    }

    struct UnwindStep2Inputs {
        uint256 collateralAfterStep1;
        uint256 debtAfterStep1;
        uint256 usdtDebtAfterStep1;
        uint256 currentLiquidationThreshold;
        uint256 usdeATokenBalance;
        uint256 susdeATokenBalance;
        uint256 usdeWithdrawAmount1;
    }

    struct UnwindStep1Outputs {
        uint256 currentLiquidationThreshold;
        uint256 usdeATokenBalance;
        uint256 susdeATokenBalance;
        uint256 walletSusdeSwapAmount;
        uint256 conservativeRepay0;
        uint256 usdeWithdrawAmount1;
        uint256 conservativeRepay1;
        uint256 collateralAfterStep1;
        uint256 debtAfterStep1;
        uint256 usdtDebtAfterStep1;
        address routerWalletSusdeToUsdt;
        bytes swapCalldataWalletSusdeToUsdt;
        address routerUsdeToUsdt;
        bytes swapCalldataUsdeToUsdt;
    }

    struct UnwindWalletRepayOutputs {
        uint256 walletSusdeSwapAmount;
        uint256 conservativeRepay0;
        uint256 totalDebtBaseAfterWalletRepay;
        uint256 usdtDebtAfterWalletRepay;
        address routerWalletSusdeToUsdt;
        bytes swapCalldataWalletSusdeToUsdt;
    }

    struct UnwindActionSteps {
        uint256 walletSwap;
        uint256 walletRepay;
        uint256 usdeWithdraw;
        uint256 usdeSwap;
        uint256 usdeRepay;
        uint256 susdeWithdraw;
    }

    struct BalanceSheetSnapshot {
        uint256 walletSusdeAmount;
        uint256 walletUsdeAmount;
        uint256 walletUsdtAmount;
        uint256 aaveSusdeCollateralAmount;
        uint256 aaveUsdeCollateralAmount;
        uint256 aaveUsdtCollateralAmount;
        uint256 aaveUsdtDebtAmount;
        uint256 walletSusdeValueBase;
        uint256 walletUsdeValueBase;
        uint256 walletUsdtValueBase;
        uint256 aaveSusdeCollateralValueBase;
        uint256 aaveUsdeCollateralValueBase;
        uint256 aaveUsdtCollateralValueBase;
        uint256 aaveDebtTotalBase;
        uint256 totalAssetsBase;
        bool netAssetsPositive;
        uint256 netAssetsAbsBase;
    }

    // Aave interest rate mode
    uint256 internal constant VARIABLE_RATE = 2;

    // Default values
    uint256 internal constant DEFAULT_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 5; // 0.05%
    uint256 internal constant DEFAULT_USDE_SUPPLY_PERCENTAGE_BPS = 10_000; // 100%
    uint256 internal constant DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS = 9990; // 99.90% (USDT -> USDe)
    uint256 internal constant DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS = 9990; // 99.90% (USDT -> sUSDe value)
    uint256 internal constant DEFAULT_MIN_HEALTH_FACTOR = 1.02e18;
    uint256 internal constant DEFAULT_MAX_SUSDE_SWAP_IN = 0;
    uint256 internal constant DEFAULT_TARGET_SUSDE_SHARE_BPS = 5000;
    uint256 internal constant DEFAULT_RATIO_TOLERANCE_BPS = 100; // 1%
    uint256 internal constant LOOP_IMBALANCE_DRIFT_TOLERANCE_USDE = 1e18; // 1 USDe
    uint256 internal constant MAX_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant DEBT_VALIDATION_TOLERANCE_BASE = 100 * BASE_CURRENCY_SCALE; // $100

    // Set to true to skip heartbeat validation during batch simulation
    bool internal constant SKIP_HEARTBEAT = true;

    // Aave eMode category for sUSDe/USDe/USDT stablecoins (hardcoded)
    // Category 2 on Aave Ethereum Core Pool
    uint8 internal constant EMODE_CATEGORY = 2;
    // eMode category 2 LTV (90% = 9000 bps)
    uint256 internal constant EMODE_LTV = 9000;
    // Reporting wallet (Yield MS on mainnet)
    address internal constant REPORTING_MS = 0x2075e3b46470cfcE124Daaf52b46Dcf965727Dd1;

    // KyberSwap API
    string internal constant KYBERSWAP_BASE_URL = "https://aggregator-api.kyberswap.com/ethereum";
    string internal constant KYBERSWAP_CLIENT_ID = "OlympusDAO";

    uint256 internal constant CACHE_TTL_SECONDS = 300;
    string internal constant CACHE_VERSION = "1";
    string internal constant CACHE_ERROR_PREFIX = "cache failed";
    string internal constant CACHE_FUNCTION_LOOP = "executeLoop";
    string internal constant CACHE_FUNCTION_UNWIND = "executeUnwindLoop";
    string internal constant CACHE_FUNCTION_REBALANCE = "executeRebalanceWallet";
    string internal constant CACHE_ERROR_RECOVERY =
        "rerun with --signonly then reuse the same signature, or clear cache files in ./cache";

    string internal constant LOOP_CACHE_FILE_PATH = "./cache/SUSDeAaveLoop-loop.toml";
    string internal constant UNWIND_CACHE_FILE_PATH = "./cache/SUSDeAaveLoop-unwind.toml";
    string internal constant REBALANCE_CACHE_FILE_PATH = "./cache/SUSDeAaveLoop-rebalance.toml";

    string internal constant CACHE_KEY_CREATED_AT = "createdAt";
    string internal constant CACHE_KEY_ARGS_FINGERPRINT = "argsFingerprint";
    string internal constant CACHE_KEY_CHAIN_ID = "chainId";
    string internal constant CACHE_KEY_OWNER = "owner";
    string internal constant CACHE_KEY_VERSION = "version";
    string internal constant CACHE_KEY_FUNCTION = "function";
    string internal constant CACHE_KEY_LOOP_SUSDE_SUPPLY_AMOUNT = "susdeSupplyAmount";
    string internal constant CACHE_KEY_LOOP_BORROW_PERCENTAGE = "borrowPercentage";
    string internal constant CACHE_KEY_LOOP_TARGET_SUSDE_SHARE_BPS = "targetSusdeShareBps";
    string internal constant CACHE_KEY_LOOP_SLIPPAGE_BPS = "slippageBps";
    string internal constant CACHE_KEY_LOOP_EXCLUDED_SOURCES = "kyberExcludedSources";
    string internal constant CACHE_KEY_UNWIND_SLIPPAGE_BPS = "slippageBps";
    string internal constant CACHE_KEY_UNWIND_MIN_HEALTH_FACTOR = "minHealthFactor";
    string internal constant CACHE_KEY_UNWIND_MIN_SWAP1_VALUE_RATIO_BPS = "minSwap1ValueRatioBps";
    string internal constant CACHE_KEY_UNWIND_MIN_SWAP2_VALUE_RATIO_BPS = "minSwap2ValueRatioBps";
    string internal constant CACHE_KEY_UNWIND_MAX_SUSDE_SWAP_IN = "maxSusdeSwapIn";
    string internal constant CACHE_KEY_UNWIND_EXCLUDED_SOURCES = "kyberExcludedSources";
    string internal constant CACHE_KEY_UNWIND_INITIAL_SUSDE_BALANCE = "initialSusdeBalance";
    string internal constant CACHE_KEY_REBALANCE_SLIPPAGE_BPS = "slippageBps";
    string internal constant CACHE_KEY_REBALANCE_TARGET_SUSDE_SHARE_BPS = "targetSusdeShareBps";
    string internal constant CACHE_KEY_REBALANCE_RATIO_TOLERANCE_BPS = "ratioToleranceBps";
    string internal constant CACHE_KEY_REBALANCE_MAX_SHIFT_USDE = "maxRebalanceValueUsde";
    string internal constant CACHE_KEY_REBALANCE_EXCLUDED_SOURCES = "kyberExcludedSources";
    string internal constant CACHE_KEY_LOOP_ACCOUNT_EMODE = "account.currentEMode";
    string internal constant CACHE_KEY_LOOP_ACCOUNT_AVAILABLE_BORROWS =
        "account.availableBorrowsBase";
    string internal constant CACHE_KEY_LOOP_ACCOUNT_CURRENT_LT =
        "account.currentLiquidationThreshold";
    string internal constant CACHE_KEY_LOOP_ACCOUNT_HEALTH_FACTOR = "account.healthFactor";
    string internal constant CACHE_KEY_LOOP_COLLATERAL_SIDE = "loop.collateral.side";
    string internal constant CACHE_KEY_LOOP_COLLATERAL_ABS = "loop.collateral.abs";
    string internal constant CACHE_KEY_LOOP_COLLATERAL_SUSDE_VALUE = "loop.collateral.susdeValue";
    string internal constant CACHE_KEY_LOOP_COLLATERAL_USDE_VALUE = "loop.collateral.usdeValue";
    string internal constant CACHE_KEY_UNWIND_ACCOUNT_COLLATERAL = "account.totalCollateralBase";
    string internal constant CACHE_KEY_UNWIND_ACCOUNT_DEBT = "account.totalDebtBase";
    string internal constant CACHE_KEY_UNWIND_ACCOUNT_CURRENT_LT =
        "account.currentLiquidationThreshold";
    string internal constant CACHE_KEY_UNWIND_ACCOUNT_HEALTH_FACTOR = "account.healthFactor";
    string internal constant CACHE_KEY_UNWIND_RESERVE_USDE_ATOKEN = "reserve.usde.aTokenBalance";
    string internal constant CACHE_KEY_UNWIND_RESERVE_SUSDE_ATOKEN = "reserve.susde.aTokenBalance";
    string internal constant CACHE_KEY_UNWIND_RESERVE_USDT_STABLE_DEBT = "reserve.usdt.stableDebt";
    string internal constant CACHE_KEY_UNWIND_RESERVE_USDT_VARIABLE_DEBT =
        "reserve.usdt.variableDebt";
    string internal constant CACHE_KEY_REPORTING_INITIAL_COLLATERAL_BASE =
        "reporting.initialCollateralBase";
    string internal constant CACHE_KEY_REPORTING_INITIAL_DEBT_BASE = "reporting.initialDebtBase";
    string internal constant CACHE_KEY_REPORTING_INITIAL_NET_BASE = "reporting.initialNetBase";
    string internal constant CACHE_KEY_LOOP_SWAP1_PREFIX = "swaps.loop.swap1";
    string internal constant CACHE_KEY_LOOP_SWAP2_PREFIX = "swaps.loop.swap2";
    string internal constant CACHE_KEY_UNWIND_SWAP1_PREFIX = "swaps.unwind.swap1";
    string internal constant CACHE_KEY_UNWIND_SWAP3_PREFIX = "swaps.unwind.swap3";
    string internal constant CACHE_KEY_UNWIND_SWAP5_PREFIX = "swaps.unwind.swap5";
    string internal constant CACHE_KEY_REBALANCE_SWAP1_PREFIX = "swaps.rebalance.swap1";
    string internal constant CACHE_KEY_LOOP_4626_SUPPLY_VALUE = "erc4626.loop.susdeSupplyValue";
    string internal constant CACHE_KEY_LOOP_4626_SWAP2_VALUE = "erc4626.loop.swap2Value";
    string internal constant CACHE_KEY_UNWIND_4626_STEP1_DEBT_SHARES =
        "erc4626.unwind.step1DebtShares";
    string internal constant CACHE_KEY_UNWIND_4626_STEP2_DEBT_SHARES =
        "erc4626.unwind.step2DebtShares";
    string internal constant CACHE_KEY_UNWIND_4626_STEP1_INPUT_VALUE =
        "erc4626.unwind.step1InputValue";
    string internal constant CACHE_KEY_UNWIND_4626_STEP5_INPUT_VALUE =
        "erc4626.unwind.step5InputValue";

    CacheMode internal _cacheMode;
    bool internal _cacheModeWrite;
    bytes32 internal _cacheArgsFingerprint;
    string internal _cacheFilePath;
    StdConfig internal _cacheConfig;

    // Aave base currency decimals (USD = 8 decimals)
    uint256 internal constant BASE_CURRENCY_DECIMALS = 8;
    uint256 internal constant BASE_CURRENCY_SCALE = 10 ** BASE_CURRENCY_DECIMALS;

    function _initCacheMode(CacheMode mode_) internal {
        _cacheMode = mode_;
        _cacheModeWrite = _signOnly && mode_ != CacheMode.None;
        _cacheArgsFingerprint = bytes32(0);

        if (mode_ == CacheMode.ExecuteLoop) {
            _cacheFilePath = LOOP_CACHE_FILE_PATH;
        } else if (mode_ == CacheMode.ExecuteUnwind) {
            _cacheFilePath = UNWIND_CACHE_FILE_PATH;
        } else if (mode_ == CacheMode.ExecuteRebalance) {
            _cacheFilePath = REBALANCE_CACHE_FILE_PATH;
        } else {
            _cacheFilePath = "";
        }

        if (mode_ != CacheMode.None && !_cacheModeWrite && !_hasSignature()) {
            _cacheFilePath = "";
        }

        if (_isCacheReplay() && !vm.exists(_cacheFilePath)) {
            _revertCacheFailure(string.concat("cache file does not exist ", _cacheFilePath));
        }

        console2.log(
            "  Cache mode",
            _cacheModeWrite ? "write" : (_isCacheReplay() ? "replay" : "none")
        );
        if (_cacheMode != CacheMode.None && bytes(_cacheFilePath).length > 0) {
            console2.log("  Cache file", _cacheFilePath);
        }

        if (_cacheModeWrite) {
            _prepareCacheDir();
            if (!vm.exists(_cacheFilePath)) {
                _initializeCacheTomlFile(_cacheFilePath);
            }
            _cacheConfig = new StdConfig(_cacheFilePath, true);
        } else if (_isCacheReplay()) {
            _cacheConfig = new StdConfig(_cacheFilePath, false);
        }
    }

    function _isCacheReplay() internal view returns (bool) {
        return _cacheMode != CacheMode.None && !_cacheModeWrite && _hasSignature();
    }

    function _prepareCacheDir() internal {
        if (!vm.isDir("./cache")) {
            string[] memory inputs = new string[](3);
            inputs[0] = "mkdir";
            inputs[1] = "-p";
            inputs[2] = "./cache";
            /// forge-lint: disable-next-line(unsafe-cheatcode)
            vm.ffi(inputs);
        }
    }

    function _initializeCacheTomlFile(string memory path_) internal {
        string memory chainIdKey = vm.toString(block.chainid);
        // StdConfig requires each chain section to include an endpoint URL.
        // This cache file never uses RPC routing from StdConfig, so this is a
        // schema placeholder only.
        string memory fileContents = string.concat(
            "[",
            chainIdKey,
            "]\n",
            'endpoint_url = "https://example.invalid"\n'
        );
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path_, fileContents);
    }

    function _validateReplayCacheMetadata(
        string memory expectedFunctionName_,
        bytes32 expectedArgsFingerprint_
    ) internal view {
        if (!_isCacheReplay()) return;

        uint256 createdAt = _cacheReadUint(CACHE_KEY_CREATED_AT);
        if (createdAt == 0) {
            _revertCacheFailure("cache createdAt is missing or zero");
        }
        if (createdAt + CACHE_TTL_SECONDS < block.timestamp) {
            _revertCacheFailure("cache expired");
        }

        if (_cacheReadUint(CACHE_KEY_CHAIN_ID) != block.chainid) {
            _revertCacheFailure("cache chainId mismatch");
        }

        if (_cacheReadAddress(CACHE_KEY_OWNER) != _owner) {
            _revertCacheFailure("cache owner mismatch");
        }

        if (
            keccak256(bytes(_cacheReadString(CACHE_KEY_VERSION))) != keccak256(bytes(CACHE_VERSION))
        ) {
            _revertCacheFailure("cache version mismatch");
        }

        if (
            keccak256(bytes(_cacheReadString(CACHE_KEY_FUNCTION))) !=
            keccak256(bytes(expectedFunctionName_))
        ) {
            _revertCacheFailure("cache function mismatch");
        }

        if (_cacheReadBytes32(CACHE_KEY_ARGS_FINGERPRINT) != expectedArgsFingerprint_) {
            _revertCacheFailure("cache argsFingerprint mismatch");
        }
    }

    function _cacheReadUint(string memory key_) internal view returns (uint256) {
        string memory storageKey = _cacheStorageKey(key_);
        if (!_cacheConfig.exists(storageKey)) {
            _revertCacheFailure(string.concat("missing cache uint key ", key_));
        }

        bytes memory encoded = _cacheConfig.get(storageKey).toBytes();
        if (encoded.length != 32) {
            _revertCacheFailure(string.concat("invalid encoded uint key ", key_));
        }
        return abi.decode(encoded, (uint256));
    }

    function _cacheReadString(string memory key_) internal view returns (string memory) {
        string memory storageKey = _cacheStorageKey(key_);
        if (!_cacheConfig.exists(storageKey)) {
            _revertCacheFailure(string.concat("missing cache string key ", key_));
        }
        return _cacheConfig.get(storageKey).toString();
    }

    function _cacheReadBytes32(string memory key_) internal view returns (bytes32) {
        string memory storageKey = _cacheStorageKey(key_);
        if (!_cacheConfig.exists(storageKey)) {
            _revertCacheFailure(string.concat("missing cache bytes32 key ", key_));
        }
        return _cacheConfig.get(storageKey).toBytes32();
    }

    function _cacheReadAddress(string memory key_) internal view returns (address) {
        string memory storageKey = _cacheStorageKey(key_);
        if (!_cacheConfig.exists(storageKey)) {
            _revertCacheFailure(string.concat("missing cache address key ", key_));
        }
        return _cacheConfig.get(storageKey).toAddress();
    }

    function _cacheReadBytes(string memory key_) internal view returns (bytes memory) {
        string memory storageKey = _cacheStorageKey(key_);
        if (!_cacheConfig.exists(storageKey)) {
            _revertCacheFailure(string.concat("missing cache bytes key ", key_));
        }
        return _cacheConfig.get(storageKey).toBytes();
    }

    function _cacheStorageKey(string memory key_) internal pure returns (string memory) {
        bytes memory rawKey = bytes(key_);
        uint256 dotCount;
        for (uint256 i = 0; i < rawKey.length; i++) {
            if (rawKey[i] == ".") dotCount++;
        }

        // Replace '.' with '__' so StdConfig does not interpret dotted keys as
        // nested TOML objects.
        bytes memory storageKey = new bytes(rawKey.length + dotCount);
        uint256 j;
        for (uint256 i = 0; i < rawKey.length; i++) {
            if (rawKey[i] == ".") {
                storageKey[j] = "_";
                storageKey[j + 1] = "_";
                j += 2;
            } else {
                storageKey[j] = rawKey[i];
                j++;
            }
        }

        return string(storageKey);
    }

    function _cacheSetUint(string memory key_, uint256 value_) internal {
        if (_cacheModeWrite) {
            _cacheConfig.set(_cacheStorageKey(key_), abi.encode(value_));
        }
    }

    function _cacheSetAddress(string memory key_, address value_) internal {
        if (_cacheModeWrite) {
            _cacheConfig.set(_cacheStorageKey(key_), value_);
        }
    }

    function _cacheSetBytes(string memory key_, bytes memory value_) internal {
        if (_cacheModeWrite) {
            _cacheConfig.set(_cacheStorageKey(key_), value_);
        }
    }

    function _cacheSetString(string memory key_, string memory value_) internal {
        if (_cacheModeWrite) {
            _cacheConfig.set(_cacheStorageKey(key_), value_);
        }
    }

    function _cacheSetBytes32(string memory key_, bytes32 value_) internal {
        if (_cacheModeWrite) {
            _cacheConfig.set(_cacheStorageKey(key_), value_);
        }
    }

    function _getLoopPlanningAccountData()
        internal
        returns (
            uint256 currentEMode_,
            uint256 availableBorrowsBase_,
            uint256 currentLiquidationThreshold_,
            uint256 healthFactor_
        )
    {
        if (_isCacheReplay()) {
            currentEMode_ = _cacheReadUint(CACHE_KEY_LOOP_ACCOUNT_EMODE);
            availableBorrowsBase_ = _cacheReadUint(CACHE_KEY_LOOP_ACCOUNT_AVAILABLE_BORROWS);
            currentLiquidationThreshold_ = _cacheReadUint(CACHE_KEY_LOOP_ACCOUNT_CURRENT_LT);
            healthFactor_ = _cacheReadUint(CACHE_KEY_LOOP_ACCOUNT_HEALTH_FACTOR);
            return (
                currentEMode_,
                availableBorrowsBase_,
                currentLiquidationThreshold_,
                healthFactor_
            );
        }

        currentEMode_ = AAVE_POOL.getUserEMode(_owner);
        (, , availableBorrowsBase_, currentLiquidationThreshold_, , healthFactor_) = AAVE_POOL
            .getUserAccountData(_owner);

        _cacheSetUint(CACHE_KEY_LOOP_ACCOUNT_EMODE, currentEMode_);
        _cacheSetUint(CACHE_KEY_LOOP_ACCOUNT_AVAILABLE_BORROWS, availableBorrowsBase_);
        _cacheSetUint(CACHE_KEY_LOOP_ACCOUNT_CURRENT_LT, currentLiquidationThreshold_);
        _cacheSetUint(CACHE_KEY_LOOP_ACCOUNT_HEALTH_FACTOR, healthFactor_);
    }

    function _getUnwindPlanningAccountData()
        internal
        returns (
            uint256 totalCollateralBase_,
            uint256 totalDebtBase_,
            uint256 currentLiquidationThreshold_,
            uint256 healthFactor_
        )
    {
        if (_isCacheReplay()) {
            totalCollateralBase_ = _cacheReadUint(CACHE_KEY_UNWIND_ACCOUNT_COLLATERAL);
            totalDebtBase_ = _cacheReadUint(CACHE_KEY_UNWIND_ACCOUNT_DEBT);
            currentLiquidationThreshold_ = _cacheReadUint(CACHE_KEY_UNWIND_ACCOUNT_CURRENT_LT);
            healthFactor_ = _cacheReadUint(CACHE_KEY_UNWIND_ACCOUNT_HEALTH_FACTOR);
            return (
                totalCollateralBase_,
                totalDebtBase_,
                currentLiquidationThreshold_,
                healthFactor_
            );
        }

        (
            totalCollateralBase_,
            totalDebtBase_,
            ,
            currentLiquidationThreshold_,
            ,
            healthFactor_
        ) = AAVE_POOL.getUserAccountData(_owner);

        _cacheSetUint(CACHE_KEY_UNWIND_ACCOUNT_COLLATERAL, totalCollateralBase_);
        _cacheSetUint(CACHE_KEY_UNWIND_ACCOUNT_DEBT, totalDebtBase_);
        _cacheSetUint(CACHE_KEY_UNWIND_ACCOUNT_CURRENT_LT, currentLiquidationThreshold_);
        _cacheSetUint(CACHE_KEY_UNWIND_ACCOUNT_HEALTH_FACTOR, healthFactor_);
    }

    function _getLoopPreSupplyCollateralSnapshot(
        uint256 targetSusdeShareBps_
    )
        internal
        returns (
            bool susdeAboveTarget_,
            uint256 absGapUsde_,
            uint256 susdeCollateralValueUsde_,
            uint256 usdeCollateralValueUsde_
        )
    {
        if (_isCacheReplay()) {
            susdeAboveTarget_ = _cacheReadUint(CACHE_KEY_LOOP_COLLATERAL_SIDE) == 1;
            absGapUsde_ = _cacheReadUint(CACHE_KEY_LOOP_COLLATERAL_ABS);
            susdeCollateralValueUsde_ = _cacheReadUint(CACHE_KEY_LOOP_COLLATERAL_SUSDE_VALUE);
            usdeCollateralValueUsde_ = _cacheReadUint(CACHE_KEY_LOOP_COLLATERAL_USDE_VALUE);
            return (
                susdeAboveTarget_,
                absGapUsde_,
                susdeCollateralValueUsde_,
                usdeCollateralValueUsde_
            );
        }

        (susdeCollateralValueUsde_, usdeCollateralValueUsde_) = _getAaveCollateralValuesUsde(
            _owner
        );
        (susdeAboveTarget_, absGapUsde_) = _getCollateralTargetGapFromValues(
            susdeCollateralValueUsde_,
            usdeCollateralValueUsde_,
            targetSusdeShareBps_
        );

        _cacheSetUint(CACHE_KEY_LOOP_COLLATERAL_SIDE, susdeAboveTarget_ ? 1 : 0);
        _cacheSetUint(CACHE_KEY_LOOP_COLLATERAL_ABS, absGapUsde_);
        _cacheSetUint(CACHE_KEY_LOOP_COLLATERAL_SUSDE_VALUE, susdeCollateralValueUsde_);
        _cacheSetUint(CACHE_KEY_LOOP_COLLATERAL_USDE_VALUE, usdeCollateralValueUsde_);
    }

    function _getUnwindReserveData()
        internal
        returns (
            uint256 usdeATokenBalance_,
            uint256 susdeATokenBalance_,
            uint256 usdtStableDebt_,
            uint256 usdtVariableDebt_
        )
    {
        if (_isCacheReplay()) {
            usdeATokenBalance_ = _cacheReadUint(CACHE_KEY_UNWIND_RESERVE_USDE_ATOKEN);
            susdeATokenBalance_ = _cacheReadUint(CACHE_KEY_UNWIND_RESERVE_SUSDE_ATOKEN);
            usdtStableDebt_ = _cacheReadUint(CACHE_KEY_UNWIND_RESERVE_USDT_STABLE_DEBT);
            usdtVariableDebt_ = _cacheReadUint(CACHE_KEY_UNWIND_RESERVE_USDT_VARIABLE_DEBT);
            return (usdeATokenBalance_, susdeATokenBalance_, usdtStableDebt_, usdtVariableDebt_);
        }

        (usdeATokenBalance_, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_usde),
            _owner
        );
        (susdeATokenBalance_, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_susde),
            _owner
        );
        (, usdtStableDebt_, usdtVariableDebt_, , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_usdt),
            _owner
        );

        _cacheSetUint(CACHE_KEY_UNWIND_RESERVE_USDE_ATOKEN, usdeATokenBalance_);
        _cacheSetUint(CACHE_KEY_UNWIND_RESERVE_SUSDE_ATOKEN, susdeATokenBalance_);
        _cacheSetUint(CACHE_KEY_UNWIND_RESERVE_USDT_STABLE_DEBT, usdtStableDebt_);
        _cacheSetUint(CACHE_KEY_UNWIND_RESERVE_USDT_VARIABLE_DEBT, usdtVariableDebt_);
    }

    function _writeLoopMetadataCache(
        uint256 susdeSupplyAmount_,
        uint256 borrowPercentage_,
        uint256 targetSusdeShareBps_,
        uint256 slippageBps_,
        string memory excludedSources_
    ) internal {
        if (_cacheMode != CacheMode.ExecuteLoop || !_cacheModeWrite) return;

        _cacheSetUint(CACHE_KEY_CREATED_AT, block.timestamp);
        _cacheSetBytes32(CACHE_KEY_ARGS_FINGERPRINT, _cacheArgsFingerprint);
        _cacheSetUint(CACHE_KEY_CHAIN_ID, block.chainid);
        _cacheSetAddress(CACHE_KEY_OWNER, _owner);
        _cacheSetString(CACHE_KEY_VERSION, CACHE_VERSION);
        _cacheSetString(CACHE_KEY_FUNCTION, CACHE_FUNCTION_LOOP);
        _cacheSetUint(CACHE_KEY_LOOP_SUSDE_SUPPLY_AMOUNT, susdeSupplyAmount_);
        _cacheSetUint(CACHE_KEY_LOOP_BORROW_PERCENTAGE, borrowPercentage_);
        _cacheSetUint(CACHE_KEY_LOOP_TARGET_SUSDE_SHARE_BPS, targetSusdeShareBps_);
        _cacheSetUint(CACHE_KEY_LOOP_SLIPPAGE_BPS, slippageBps_);
        _cacheSetString(CACHE_KEY_LOOP_EXCLUDED_SOURCES, excludedSources_);
    }

    function _writeUnwindMetadataCache(
        uint256 slippageBps_,
        uint256 minHealthFactor_,
        uint256 minSwap1ValueRatioBps_,
        uint256 minSwap2ValueRatioBps_,
        uint256 maxSusdeSwapIn_,
        string memory excludedSources_,
        uint256 initialSusdeBalance_
    ) internal {
        if (_cacheMode != CacheMode.ExecuteUnwind || !_cacheModeWrite) return;

        _cacheSetUint(CACHE_KEY_CREATED_AT, block.timestamp);
        _cacheSetBytes32(CACHE_KEY_ARGS_FINGERPRINT, _cacheArgsFingerprint);
        _cacheSetUint(CACHE_KEY_CHAIN_ID, block.chainid);
        _cacheSetAddress(CACHE_KEY_OWNER, _owner);
        _cacheSetString(CACHE_KEY_VERSION, CACHE_VERSION);
        _cacheSetString(CACHE_KEY_FUNCTION, CACHE_FUNCTION_UNWIND);
        _cacheSetUint(CACHE_KEY_UNWIND_SLIPPAGE_BPS, slippageBps_);
        _cacheSetUint(CACHE_KEY_UNWIND_MIN_HEALTH_FACTOR, minHealthFactor_);
        _cacheSetUint(CACHE_KEY_UNWIND_MIN_SWAP1_VALUE_RATIO_BPS, minSwap1ValueRatioBps_);
        _cacheSetUint(CACHE_KEY_UNWIND_MIN_SWAP2_VALUE_RATIO_BPS, minSwap2ValueRatioBps_);
        _cacheSetUint(CACHE_KEY_UNWIND_MAX_SUSDE_SWAP_IN, maxSusdeSwapIn_);
        _cacheSetString(CACHE_KEY_UNWIND_EXCLUDED_SOURCES, excludedSources_);
        _cacheSetUint(CACHE_KEY_UNWIND_INITIAL_SUSDE_BALANCE, initialSusdeBalance_);
    }

    function _writeRebalanceMetadataCache(
        uint256 targetSusdeShareBps_,
        uint256 slippageBps_,
        uint256 ratioToleranceBps_,
        uint256 maxRebalanceValueUsde_,
        string memory excludedSources_
    ) internal {
        if (_cacheMode != CacheMode.ExecuteRebalance || !_cacheModeWrite) return;

        _cacheSetUint(CACHE_KEY_CREATED_AT, block.timestamp);
        _cacheSetBytes32(CACHE_KEY_ARGS_FINGERPRINT, _cacheArgsFingerprint);
        _cacheSetUint(CACHE_KEY_CHAIN_ID, block.chainid);
        _cacheSetAddress(CACHE_KEY_OWNER, _owner);
        _cacheSetString(CACHE_KEY_VERSION, CACHE_VERSION);
        _cacheSetString(CACHE_KEY_FUNCTION, CACHE_FUNCTION_REBALANCE);
        _cacheSetUint(CACHE_KEY_REBALANCE_TARGET_SUSDE_SHARE_BPS, targetSusdeShareBps_);
        _cacheSetUint(CACHE_KEY_REBALANCE_SLIPPAGE_BPS, slippageBps_);
        _cacheSetUint(CACHE_KEY_REBALANCE_RATIO_TOLERANCE_BPS, ratioToleranceBps_);
        _cacheSetUint(CACHE_KEY_REBALANCE_MAX_SHIFT_USDE, maxRebalanceValueUsde_);
        _cacheSetString(CACHE_KEY_REBALANCE_EXCLUDED_SOURCES, excludedSources_);
    }

    function _computeLoopArgsFingerprint(
        uint256 effectiveSusdeSupplyAmount_
    ) internal view returns (bytes32) {
        uint256 borrowPercentage = _readOptionalUint256(
            "executeLoop",
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );
        uint256 targetSusdeShareBps = _readOptionalUint256(
            "executeLoop",
            "targetSusdeShareBps",
            DEFAULT_TARGET_SUSDE_SHARE_BPS
        );
        uint256 slippageBps = _readOptionalUint256(
            "executeLoop",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        uint256 minSwap1ValueRatioBps = _getLoopMinSwapUsdtUsdeValueRatioBps();
        uint256 minSwap2ValueRatioBps = _getLoopMinSwapUsdtSusdeValueRatioBps();
        string memory excludedSources = _readOptionalString(
            "executeLoop",
            "kyberExcludedSources",
            ""
        );

        /// forge-lint: disable-start(asm-keccak256)
        bytes32 fingerprint = keccak256(
            abi.encode(
                effectiveSusdeSupplyAmount_,
                borrowPercentage,
                targetSusdeShareBps,
                slippageBps,
                minSwap1ValueRatioBps,
                minSwap2ValueRatioBps,
                excludedSources
            )
        );
        /// forge-lint: disable-end(asm-keccak256)
        return fingerprint;
    }

    function _computeUnwindArgsFingerprint() internal view returns (bytes32) {
        uint256 slippageBps = _readOptionalUint256(
            "executeUnwindLoop",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        uint256 minHealthFactor = _readOptionalUint256(
            "executeUnwindLoop",
            "minHealthFactor",
            DEFAULT_MIN_HEALTH_FACTOR
        );
        uint256 minSwap1ValueRatioBps = _getUnwindMinSwapUsdeUsdtValueRatioBps();
        uint256 minSwap2ValueRatioBps = _getUnwindMinSwapSusdeUsdtValueRatioBps();
        uint256 maxSusdeSwapIn = _readOptionalUint256(
            "executeUnwindLoop",
            "maxSusdeSwapIn",
            DEFAULT_MAX_SUSDE_SWAP_IN
        );
        string memory excludedSources = _readOptionalString(
            "executeUnwindLoop",
            "kyberExcludedSources",
            ""
        );

        /// forge-lint: disable-start(asm-keccak256)
        bytes32 fingerprint = keccak256(
            abi.encode(
                slippageBps,
                minHealthFactor,
                minSwap1ValueRatioBps,
                minSwap2ValueRatioBps,
                maxSusdeSwapIn,
                excludedSources,
                _initialSusdeBalance
            )
        );
        /// forge-lint: disable-end(asm-keccak256)
        return fingerprint;
    }

    function _computeRebalanceArgsFingerprint() internal view returns (bytes32) {
        uint256 targetSusdeShareBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "targetSusdeShareBps",
            DEFAULT_TARGET_SUSDE_SHARE_BPS
        );
        uint256 ratioToleranceBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "ratioToleranceBps",
            DEFAULT_RATIO_TOLERANCE_BPS
        );
        uint256 maxRebalanceValueUsde = _readOptionalUint256(
            "executeRebalanceWallet",
            "maxRebalanceValueUsde",
            0
        );
        uint256 slippageBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        string memory excludedSources = _readOptionalString(
            "executeRebalanceWallet",
            "kyberExcludedSources",
            ""
        );

        /// forge-lint: disable-start(asm-keccak256)
        bytes32 fingerprint = keccak256(
            abi.encode(
                targetSusdeShareBps,
                ratioToleranceBps,
                maxRebalanceValueUsde,
                slippageBps,
                excludedSources,
                _susde.balanceOf(_owner),
                _usde.balanceOf(_owner)
            )
        );
        /// forge-lint: disable-end(asm-keccak256)
        return fingerprint;
    }

    function _revertCacheFailure(string memory detail_) internal pure {
        revert(string.concat(CACHE_ERROR_PREFIX, ": ", detail_, " | ", CACHE_ERROR_RECOVERY));
    }

    /// @notice Load token addresses from env.json
    function _loadTokens() internal {
        _susde = IERC20(_envAddressNotZero("external.tokens.sUSDE"));
        _usde = IERC20(_envAddressNotZero("external.tokens.USDE"));
        _usdt = IERC20(_envAddressNotZero("external.tokens.USDT"));
    }

    /// @notice Execute one full sUSDe Aave loop iteration in a single multisig batch
    /// @dev    Two-phase design:
    ///         1. CALC PHASE (off-chain simulation): fetches on-chain state, queries KyberSwap for
    ///            swap quotes, and computes all amounts. No state changes occur during this phase.
    ///         2. BATCH ASSEMBLY PHASE: encodes all actions (supply, borrow, swap, approve) into a
    ///            single multisig batch transaction. The batch is proposed and must be signed/executed
    ///            on-chain by the multisig.
    ///
    ///         If susdeSupplyAmount is 0 or not provided, uses full sUSDe balance
    function executeLoop(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithYieldMS(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
    {
        _loadTokens();
        _initCacheMode(CacheMode.ExecuteLoop);

        _initialSusdeBalance = _susde.balanceOf(_owner);

        uint256 susdeSupplyAmount = _readOptionalUint256("executeLoop", "susdeSupplyAmount", 0);
        uint256 borrowPercentage = _readOptionalUint256(
            "executeLoop",
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );
        _loopTargetSusdeShareBps = _readOptionalUint256(
            "executeLoop",
            "targetSusdeShareBps",
            DEFAULT_TARGET_SUSDE_SHARE_BPS
        );

        if (borrowPercentage > MAX_BORROW_PERCENTAGE) revert("Borrow percentage exceeds max");
        if (_loopTargetSusdeShareBps == 0 || _loopTargetSusdeShareBps >= 10_000) {
            revert("targetSusdeShareBps out of range");
        }
        uint256 slippageBps = _readOptionalUint256(
            "executeLoop",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");
        _kyberExcludedSources = _readOptionalString("executeLoop", "kyberExcludedSources", "");

        _skipHeartbeatValidation = SKIP_HEARTBEAT;

        if (susdeSupplyAmount == 0) susdeSupplyAmount = _initialSusdeBalance;
        if (susdeSupplyAmount > _initialSusdeBalance) {
            revert(
                string.concat(
                    "sUSDe wallet balance below requested supply: ",
                    _toDecimalString(_initialSusdeBalance, 18),
                    " < ",
                    _toDecimalString(susdeSupplyAmount, 18)
                )
            );
        }
        if (susdeSupplyAmount == 0) revert("No sUSDe to supply");

        _cacheArgsFingerprint = _computeLoopArgsFingerprint(susdeSupplyAmount);
        _validateReplayCacheMetadata(CACHE_FUNCTION_LOOP, _cacheArgsFingerprint);

        _captureInitialAccountSnapshot();
        _susdeSuppliedAmount = susdeSupplyAmount;
        (
            _loopImbalanceBeforeSusdeOverweight,
            _loopImbalanceBeforeAbsUsde,
            _loopSusdeCollateralValueUsdeBefore,
            _loopUsdeCollateralValueUsdeBefore
        ) = _getLoopPreSupplyCollateralSnapshot(_loopTargetSusdeShareBps);

        console2.log(
            "=== Execute Loop Iteration: sUSDe -> USDT -> USDe (target-capped) -> USDT -> sUSDe ==="
        );
        console2.log("Owner:", _owner);
        console2.log("sUSDe supply amount (from wallet):", _toDecimalString(susdeSupplyAmount, 18));
        console2.log("Borrow percentage (bps):", borrowPercentage);
        console2.log("Target sUSDe share (bps):", _loopTargetSusdeShareBps);
        console2.log("Slippage (bps):", slippageBps);
        if (bytes(_kyberExcludedSources).length > 0) {
            console2.log("Kyber excluded sources:", _kyberExcludedSources);
        }
        console2.log(
            "[Position] Pre-loop collateral gap to target (abs USDe):",
            _toDecimalString(_loopImbalanceBeforeAbsUsde, 18)
        );
        console2.log(
            "[Position] Pre-loop collateral gap side:",
            _loopImbalanceBeforeSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );

        uint256 totalExpectedBorrowsAfterSusdeSupply;
        uint256 usdtBorrowAmount1;
        uint256 susdeSupplyValueUsdeForRatio;

        {
            (
                uint256 currentEMode,
                uint256 availableBorrowsBase,
                uint256 currentLiquidationThreshold,
                uint256 healthFactor
            ) = _getLoopPlanningAccountData();
            bool shouldSetEMode = (currentEMode != EMODE_CATEGORY);

            // Convert sUSDe amount (18dp) to its USDe value using live exchange rate (18dp)
            susdeSupplyValueUsdeForRatio = _susdeToUsdeValueCached(
                CACHE_KEY_LOOP_4626_SUPPLY_VALUE,
                susdeSupplyAmount
            );
            // Convert USDe value (18dp) to Aave base currency (8dp USD): value * 1e8 / 1e18
            uint256 supplyValueBase = FullMath.mulDiv(
                susdeSupplyValueUsdeForRatio,
                10 ** BASE_CURRENCY_DECIMALS,
                1e18
            );
            // Projected borrow capacity after sUSDe supply = existing + new LTV contribution (8dp USD)
            totalExpectedBorrowsAfterSusdeSupply =
                availableBorrowsBase +
                ((supplyValueBase * EMODE_LTV) / 10000);

            // Convert projected capacity (8dp USD) to USDT (6dp): divide by 100
            // Apply borrowPercentage haircut (e.g. 90% = 9000 bps)
            usdtBorrowAmount1 =
                ((totalExpectedBorrowsAfterSusdeSupply * borrowPercentage) / 10000) /
                1e2;
            if (usdtBorrowAmount1 == 0) revert("USDT borrow amount 1 is zero");

            _logBatchStepHeader(
                shouldSetEMode ? _batchTargets.length + 4 : _batchTargets.length + 3,
                "Estimate Borrow #1 from sUSDe supply (this iteration)"
            );
            console2.log("[Position] Current eMode category:", currentEMode);
            console2.log("[Position] Will set eMode in batch:", shouldSetEMode);
            console2.log(
                "[Position] Available borrows (before this iteration):",
                _toDecimalString(availableBorrowsBase, 8)
            );
            console2.log("[Position] Liquidation threshold (bps):", currentLiquidationThreshold);
            console2.log("[Position] Health factor:", _toDecimalString(healthFactor, 18));
            console2.log(
                "[Iteration] sUSDe supply value (USDe):",
                _toDecimalString(susdeSupplyValueUsdeForRatio, 18)
            );
            console2.log(
                "[Iteration] sUSDe supply value (USD):",
                _toDecimalString(supplyValueBase, 8)
            );
            console2.log(
                "[Iteration] Projected available borrows after sUSDe supply:",
                _toDecimalString(totalExpectedBorrowsAfterSusdeSupply, 8)
            );
            console2.log(
                "[Iteration] Borrow #1 amount USDT:",
                _toDecimalString(usdtBorrowAmount1, 6)
            );
            console2.log(
                "[Iteration] Borrow #1 utilization vs projected capacity (bps):",
                _ratioBps(usdtBorrowAmount1 * 1e2, totalExpectedBorrowsAfterSusdeSupply)
            );
            if (shouldSetEMode) {
                _addToBatchWithStepLog(
                    address(AAVE_POOL),
                    _encodeSetUserEMode(EMODE_CATEGORY),
                    string.concat("Set eMode category to ", vm.toString(EMODE_CATEGORY))
                );
            }

            _loopActionsBaseStep = _batchTargets.length;
        }

        address routerUsdtToUsde;
        bytes memory swapCalldataUsdtToUsde;
        uint256 usdeSupplyAmount;
        {
            uint256 usdeAmountOut;
            (routerUsdtToUsde, swapCalldataUsdtToUsde, usdeAmountOut) = _getKyberSwapCalldata(
                "Swap #1 (USDT -> USDe)",
                address(_usdt),
                address(_usde),
                usdtBorrowAmount1,
                slippageBps
            );
            if (usdeAmountOut == 0) revert("USDe quote amount is zero");

            _logBatchStepHeader(
                _loopActionsBaseStep + 6,
                "Build swap #1 (USDT -> USDe) [this iteration]"
            );
            console2.log(
                "[Iteration] Expected USDe out from quote:",
                _toDecimalString(usdeAmountOut, 18)
            );
            {
                uint256 minSwap1ValueRatioBps = _getLoopMinSwapUsdtUsdeValueRatioBps();
                if (minSwap1ValueRatioBps == 0 || minSwap1ValueRatioBps > 10000) {
                    revert("Swap #1 min value ratio invalid");
                }
                _logAndValidateValueRatio(
                    "Swap #1 (USDT -> USDe)",
                    usdeAmountOut,
                    _usdtToUsd18(usdtBorrowAmount1),
                    minSwap1ValueRatioBps
                );
            }

            uint256 conservativeUsdeSupplyAmount = _getConservativeUsdeSupplyAmount(
                usdeAmountOut,
                usdtBorrowAmount1,
                slippageBps
            );
            uint256 usdeAmountOutMin = _getPlannedUsdeAmountOutMin(usdeAmountOut, slippageBps);
            console2.log(
                "[Iteration] Conservative USDe supply haircut vs quote (bps):",
                _ratioBps(conservativeUsdeSupplyAmount, usdeAmountOut)
            );

            uint256 susdeCollateralValueUsdePostSusdeSupply = _loopSusdeCollateralValueUsdeBefore +
                susdeSupplyValueUsdeForRatio;
            (
                _loopImbalancePostSusdeSupplySusdeOverweight,
                _loopImbalancePostSusdeSupplyAbsUsde
            ) = _getCollateralTargetGapFromValues(
                susdeCollateralValueUsdePostSusdeSupply,
                _loopUsdeCollateralValueUsdeBefore,
                _loopTargetSusdeShareBps
            );
            _loopUsdeSupplyCapTarget = _loopImbalancePostSusdeSupplySusdeOverweight
                ? _loopImbalancePostSusdeSupplyAbsUsde
                : 0;

            usdeSupplyAmount = _min(conservativeUsdeSupplyAmount, _loopUsdeSupplyCapTarget);
            _usdeSuppliedAmount = usdeSupplyAmount;
            _plannedUsdeSweepToSusdeAmount = usdeAmountOutMin > usdeSupplyAmount
                ? usdeAmountOutMin - usdeSupplyAmount
                : 0;
            (
                _loopProjectedImbalanceSusdeOverweight,
                _loopProjectedImbalanceAbsUsde
            ) = _getCollateralTargetGapFromValues(
                susdeCollateralValueUsdePostSusdeSupply,
                _loopUsdeCollateralValueUsdeBefore + usdeSupplyAmount,
                _loopTargetSusdeShareBps
            );
            _logLoopProjectedImbalance(
                _loopImbalanceBeforeSusdeOverweight,
                _loopImbalanceBeforeAbsUsde,
                _loopImbalancePostSusdeSupplySusdeOverweight,
                _loopImbalancePostSusdeSupplyAbsUsde,
                conservativeUsdeSupplyAmount,
                _loopUsdeSupplyCapTarget,
                usdeSupplyAmount,
                _plannedUsdeSweepToSusdeAmount
            );
        }

        uint256 usdtBorrowAmount2 = _estimateLoopBorrow2Usdt(
            totalExpectedBorrowsAfterSusdeSupply,
            usdtBorrowAmount1,
            usdeSupplyAmount,
            borrowPercentage
        );

        address routerUsdtToSusde;
        bytes memory swapCalldataUsdtToSusde;
        if (usdtBorrowAmount2 > 0) {
            (routerUsdtToSusde, swapCalldataUsdtToSusde) = _planLoopSwap2(
                usdtBorrowAmount2,
                slippageBps
            );
        } else {
            _expectedMinSusdeOut = 0;
            _logBatchStepHeader(_loopActionsBaseStep + 13, "Build swap #2 (USDT -> sUSDe) [skip]");
            console2.log("[Iteration] Borrow #2 amount is zero; swap #2 skipped");
        }

        _addLoopActionsToBatch(
            susdeSupplyAmount,
            usdtBorrowAmount1,
            usdeSupplyAmount,
            usdtBorrowAmount2,
            _plannedUsdeSweepToSusdeAmount,
            routerUsdtToUsde,
            swapCalldataUsdtToUsde,
            routerUsdtToSusde,
            swapCalldataUsdtToSusde
        );

        console2.log("\n=== Batch prepared ===");
        console2.log("Total batch operations:", _batchTargets.length);

        _setPostBatchValidateSelector(this._validateExecuteLoopPostBatch.selector);

        proposeBatch();

        _writeLoopMetadataCache(
            susdeSupplyAmount,
            borrowPercentage,
            _loopTargetSusdeShareBps,
            slippageBps,
            _kyberExcludedSources
        );
    }

    /// @notice Rebalance Aave collateral split toward target sUSDe share using wallet funds only
    /// @dev    Does not withdraw collateral from Aave, so health-factor headroom is not required.
    function executeRebalanceWallet(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithYieldMS(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
    {
        _loadTokens();
        _initCacheMode(CacheMode.ExecuteRebalance);
        _captureInitialAccountSnapshot();

        uint256 targetSusdeShareBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "targetSusdeShareBps",
            DEFAULT_TARGET_SUSDE_SHARE_BPS
        );
        if (targetSusdeShareBps == 0 || targetSusdeShareBps >= 10_000) {
            revert("targetSusdeShareBps out of range");
        }
        _rebalanceTargetSusdeShareBps = targetSusdeShareBps;

        uint256 ratioToleranceBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "ratioToleranceBps",
            DEFAULT_RATIO_TOLERANCE_BPS
        );
        if (ratioToleranceBps > 10_000) revert("ratioToleranceBps exceeds max");

        uint256 slippageBps = _readOptionalUint256(
            "executeRebalanceWallet",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        uint256 maxRebalanceValueUsde = _readOptionalUint256(
            "executeRebalanceWallet",
            "maxRebalanceValueUsde",
            0
        );
        if (maxRebalanceValueUsde == 0) {
            maxRebalanceValueUsde = type(uint256).max;
        }

        _kyberExcludedSources = _readOptionalString(
            "executeRebalanceWallet",
            "kyberExcludedSources",
            ""
        );

        _cacheArgsFingerprint = _computeRebalanceArgsFingerprint();
        _validateReplayCacheMetadata(CACHE_FUNCTION_REBALANCE, _cacheArgsFingerprint);

        uint256 susdeCollateralValueUsde;
        uint256 usdeCollateralValueUsde;
        (
            _rebalanceImbalanceBeforeSusdeOverweight,
            _rebalanceImbalanceBeforeAbsUsde,
            susdeCollateralValueUsde,
            usdeCollateralValueUsde
        ) = _getAaveCollateralTargetGapUsde(_owner, targetSusdeShareBps);

        uint256 totalCollateralValueUsde = susdeCollateralValueUsde + usdeCollateralValueUsde;
        uint256 currentSusdeShareBps = _ratioBps(
            susdeCollateralValueUsde,
            totalCollateralValueUsde
        );
        _rebalanceImbalanceToleranceUsde = FullMath.mulDiv(
            totalCollateralValueUsde,
            ratioToleranceBps,
            10_000
        );

        console2.log("=== Execute wallet-funded rebalance to target collateral split ===");
        console2.log("Owner:", _owner);
        console2.log("[Target] sUSDe share (bps):", targetSusdeShareBps);
        console2.log("[Position] Current sUSDe share (bps):", currentSusdeShareBps);
        console2.log(
            "[Position] sUSDe collateral value (USDe):",
            _toDecimalString(susdeCollateralValueUsde, 18)
        );
        console2.log(
            "[Position] USDe collateral value (USDe):",
            _toDecimalString(usdeCollateralValueUsde, 18)
        );
        console2.log(
            "[Position] Collateral gap to target (abs USDe):",
            _toDecimalString(_rebalanceImbalanceBeforeAbsUsde, 18)
        );
        console2.log(
            "[Position] Collateral gap side:",
            _rebalanceImbalanceBeforeSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        console2.log(
            "[Position] Collateral tolerance (USDe):",
            _toDecimalString(_rebalanceImbalanceToleranceUsde, 18)
        );

        if (_rebalanceImbalanceBeforeAbsUsde <= _rebalanceImbalanceToleranceUsde) {
            revert("Collateral already within ratio tolerance");
        }

        _rebalanceTargetShiftUsde = _rebalanceImbalanceBeforeAbsUsde;
        if (_rebalanceTargetShiftUsde > maxRebalanceValueUsde) {
            _rebalanceTargetShiftUsde = maxRebalanceValueUsde;
        }
        if (_rebalanceTargetShiftUsde == 0) {
            revert("Rebalance target shift is zero");
        }

        _rebalancePartialReason = "none";
        _rebalancePlannedShiftUsde = 0;

        if (_rebalanceImbalanceBeforeSusdeOverweight) {
            _rebalancePlannedShiftUsde = _addRebalanceActionsForSusdeOverweight(slippageBps);
        } else {
            _rebalancePlannedShiftUsde = _addRebalanceActionsForUsdeOverweight();
        }

        if (_rebalancePlannedShiftUsde < _rebalanceTargetShiftUsde) {
            _rebalancePartialReason = "wallet inventory/cap limits";
        }

        _setPostBatchValidateSelector(this._validateExecuteRebalanceWalletPostBatch.selector);

        proposeBatch();

        _writeRebalanceMetadataCache(
            targetSusdeShareBps,
            slippageBps,
            ratioToleranceBps,
            maxRebalanceValueUsde,
            _kyberExcludedSources
        );
    }

    function _planLoopSwap2(
        uint256 usdtBorrowAmount2,
        uint256 slippageBps
    ) internal returns (address routerUsdtToSusde, bytes memory swapCalldataUsdtToSusde) {
        uint256 susdeAmountOut;
        (routerUsdtToSusde, swapCalldataUsdtToSusde, susdeAmountOut) = _getKyberSwapCalldata(
            "Swap #2 (USDT -> sUSDe)",
            address(_usdt),
            address(_susde),
            usdtBorrowAmount2,
            slippageBps
        );

        _logBatchStepHeader(
            _loopActionsBaseStep + 13,
            "Build swap #2 (USDT -> sUSDe) [this iteration]"
        );
        console2.log(
            "[Iteration] Expected sUSDe out from quote:",
            _toDecimalString(susdeAmountOut, 18)
        );

        uint256 minSwap2ValueRatioBps = _getLoopMinSwapUsdtSusdeValueRatioBps();
        if (minSwap2ValueRatioBps == 0 || minSwap2ValueRatioBps > 10000) {
            revert("Swap #2 min value ratio invalid");
        }

        uint256 swap2ValueOutUsd = _susdeToUsdeValueCached(
            CACHE_KEY_LOOP_4626_SWAP2_VALUE,
            susdeAmountOut
        );
        console2.log(
            "[Iteration] sUSDe exchange rate (USDe per 1 sUSDe):",
            _toDecimalString(_susdeExchangeRate(), 18)
        );
        console2.log(
            "[Iteration] Swap #2 quoted value out (USDe):",
            _toDecimalString(swap2ValueOutUsd, 18)
        );

        _logAndValidateValueRatio(
            "Swap #2 (USDT -> sUSDe)",
            swap2ValueOutUsd,
            _usdtToUsd18(usdtBorrowAmount2),
            minSwap2ValueRatioBps
        );

        _expectedMinSusdeOut = FullMath.mulDiv(susdeAmountOut, 10000 - slippageBps, 10000);
        console2.log(
            "[Iteration] Expected min sUSDe out after slippage buffer:",
            _toDecimalString(_expectedMinSusdeOut, 18)
        );
        console2.log(
            "[Iteration] Min-out buffer vs quote (bps):",
            _ratioBps(_expectedMinSusdeOut, susdeAmountOut)
        );
    }

    function _addRebalanceActionsForSusdeOverweight(
        uint256 slippageBps
    ) internal returns (uint256 plannedShiftUsde) {
        uint256 walletUsdeAmount = _usde.balanceOf(_owner);
        uint256 walletSusdeAmount = _susde.balanceOf(_owner);
        uint256 directUsdeSupply = _min(walletUsdeAmount, _rebalanceTargetShiftUsde);

        (
            uint256 swapSusdeAmountIn,
            uint256 swapUsdeSupplyMin,
            address routerSusdeToUsde,
            bytes memory swapCalldataSusdeToUsde
        ) = _planRebalanceSusdeSwap(directUsdeSupply, walletSusdeAmount, slippageBps);

        uint256 totalUsdeSupplyAmount = directUsdeSupply + swapUsdeSupplyMin;
        if (totalUsdeSupplyAmount == 0) {
            revert("No wallet liquidity available for rebalance");
        }

        if (swapSusdeAmountIn > 0) {
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(routerSusdeToUsde, 0),
                "Reset sUSDe approval for rebalance swap"
            );
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(routerSusdeToUsde, swapSusdeAmountIn),
                string.concat(
                    "Approve sUSDe for rebalance swap amount=",
                    _toDecimalString(swapSusdeAmountIn, 18)
                )
            );
            _addToBatchWithStepLog(
                routerSusdeToUsde,
                swapCalldataSusdeToUsde,
                string.concat(
                    "Swap sUSDe -> USDe amountIn=",
                    _toDecimalString(swapSusdeAmountIn, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(routerSusdeToUsde, 0),
                "Zero sUSDe -> rebalance swap router approval"
            );
        }

        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(AAVE_POOL), totalUsdeSupplyAmount),
            string.concat(
                "Approve USDe -> Aave rebalance amount=",
                _toDecimalString(totalUsdeSupplyAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSupply(address(_usde), totalUsdeSupplyAmount, _owner),
            string.concat(
                "Supply USDe rebalance amount=",
                _toDecimalString(totalUsdeSupplyAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSetUserUseReserveAsCollateral(address(_usde), true),
            "Enable USDe as collateral"
        );
        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(AAVE_POOL), 0),
            "Zero USDe -> Aave approval"
        );

        return totalUsdeSupplyAmount;
    }

    function _planRebalanceSusdeSwap(
        uint256 directUsdeSupply,
        uint256 walletSusdeAmount,
        uint256 slippageBps
    )
        internal
        returns (
            uint256 swapSusdeAmountIn,
            uint256 swapUsdeSupplyMin,
            address routerSusdeToUsde,
            bytes memory swapCalldataSusdeToUsde
        )
    {
        if (_rebalanceTargetShiftUsde <= directUsdeSupply) {
            return (0, 0, address(0), bytes(""));
        }

        uint256 missingUsdeValue = _rebalanceTargetShiftUsde - directUsdeSupply;
        uint256 susdeExchangeRate = _susdeExchangeRate();
        uint256 requiredSusdeAmountIn = FullMath.mulDivUp(
            missingUsdeValue,
            1e18,
            susdeExchangeRate
        );
        swapSusdeAmountIn = _min(requiredSusdeAmountIn, walletSusdeAmount);

        if (swapSusdeAmountIn == 0) {
            return (0, 0, address(0), bytes(""));
        }

        uint256 usdeAmountOut;
        (routerSusdeToUsde, swapCalldataSusdeToUsde, usdeAmountOut) = _getKyberSwapCalldata(
            "Rebalance swap (sUSDe -> USDe)",
            address(_susde),
            address(_usde),
            swapSusdeAmountIn,
            slippageBps
        );

        swapUsdeSupplyMin = FullMath.mulDiv(usdeAmountOut, 10_000 - slippageBps, 10_000);
    }

    function _addRebalanceActionsForUsdeOverweight() internal returns (uint256 plannedShiftUsde) {
        uint256 walletSusdeAmount = _susde.balanceOf(_owner);
        uint256 walletUsdeAmount = _usde.balanceOf(_owner);
        uint256 susdeExchangeRate = _susdeExchangeRate();

        uint256 targetSusdeAmount = FullMath.mulDiv(
            _rebalanceTargetShiftUsde,
            1e18,
            susdeExchangeRate
        );
        uint256 directSusdeSupply = _min(walletSusdeAmount, targetSusdeAmount);

        uint256 stakeUsdeAmount;
        uint256 stakeSusdeShares;
        if (targetSusdeAmount > directSusdeSupply) {
            uint256 remainingSusdeAmount = targetSusdeAmount - directSusdeSupply;
            uint256 remainingUsdeValue = _susdeToUsdeValue(remainingSusdeAmount);
            stakeUsdeAmount = _min(walletUsdeAmount, remainingUsdeValue);
            if (stakeUsdeAmount > 0) {
                stakeSusdeShares = _usdeToSusdeSharesCached(
                    "erc4626.rebalance.usdeToSusde",
                    stakeUsdeAmount
                );
            }
        }

        uint256 totalSusdeSupplyAmount = directSusdeSupply + stakeSusdeShares;
        if (totalSusdeSupplyAmount == 0) {
            revert("No wallet liquidity available for rebalance");
        }

        if (stakeUsdeAmount > 0) {
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), 0),
                "Reset USDe approval for sUSDe deposit"
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), stakeUsdeAmount),
                string.concat(
                    "Approve USDe for sUSDe deposit amount=",
                    _toDecimalString(stakeUsdeAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_susde),
                abi.encodeWithSelector(IERC4626.deposit.selector, stakeUsdeAmount, _owner),
                string.concat(
                    "Deposit USDe into sUSDe amount=",
                    _toDecimalString(stakeUsdeAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), 0),
                "Zero USDe -> sUSDe approval"
            );
        }

        _addToBatchWithStepLog(
            address(_susde),
            _encodeApprove(address(AAVE_POOL), totalSusdeSupplyAmount),
            string.concat(
                "Approve sUSDe -> Aave rebalance amount=",
                _toDecimalString(totalSusdeSupplyAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSupply(address(_susde), totalSusdeSupplyAmount, _owner),
            string.concat(
                "Supply sUSDe rebalance amount=",
                _toDecimalString(totalSusdeSupplyAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSetUserUseReserveAsCollateral(address(_susde), true),
            "Enable sUSDe as collateral"
        );
        _addToBatchWithStepLog(
            address(_susde),
            _encodeApprove(address(AAVE_POOL), 0),
            "Zero sUSDe -> Aave approval"
        );

        return _susdeToUsdeValue(totalSusdeSupplyAmount);
    }

    function _validateExecuteRebalanceWalletPostBatch() external view {
        (
            bool imbalanceAfterSusdeOverweight,
            uint256 imbalanceAfterAbsUsde,
            uint256 susdeCollateralValueUsdeAfter,
            uint256 usdeCollateralValueUsdeAfter
        ) = _getAaveCollateralTargetGapUsde(_owner, _rebalanceTargetSusdeShareBps);

        uint256 totalCollateralValueUsdeAfter = susdeCollateralValueUsdeAfter +
            usdeCollateralValueUsdeAfter;
        uint256 endingSusdeShareBps = _ratioBps(
            susdeCollateralValueUsdeAfter,
            totalCollateralValueUsdeAfter
        );

        console2.log("\n--- Rebalance post-batch summary ---");
        console2.log(
            "[Position] Starting collateral imbalance (abs USDe):",
            _toDecimalString(_rebalanceImbalanceBeforeAbsUsde, 18)
        );
        console2.log(
            "[Position] Target value shift (USDe):",
            _toDecimalString(_rebalanceTargetShiftUsde, 18)
        );
        console2.log(
            "[Position] Planned value shift (USDe):",
            _toDecimalString(_rebalancePlannedShiftUsde, 18)
        );
        console2.log(
            "[Position] Ending sUSDe collateral value (USDe):",
            _toDecimalString(susdeCollateralValueUsdeAfter, 18)
        );
        console2.log(
            "[Position] Ending USDe collateral value (USDe):",
            _toDecimalString(usdeCollateralValueUsdeAfter, 18)
        );
        console2.log(
            "[Position] Ending collateral imbalance (abs USDe):",
            _toDecimalString(imbalanceAfterAbsUsde, 18)
        );
        console2.log(
            "[Position] Ending collateral imbalance side:",
            imbalanceAfterSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        console2.log("[Position] Ending sUSDe share (bps):", endingSusdeShareBps);

        if (
            _rebalanceImbalanceBeforeAbsUsde > _rebalanceImbalanceToleranceUsde &&
            imbalanceAfterAbsUsde >= _rebalanceImbalanceBeforeAbsUsde
        ) {
            revert("Rebalance did not improve collateral gap to target");
        }

        if (imbalanceAfterAbsUsde <= _rebalanceImbalanceToleranceUsde) {
            console2.log("[Rebalance] Gap fully closed within tolerance");
        } else {
            console2.log(
                "[Rebalance] Gap partially reduced; remaining gap to target (USDe):",
                _toDecimalString(imbalanceAfterAbsUsde, 18)
            );
            console2.log("[Rebalance] Partial reason:", _rebalancePartialReason);
        }

        _logBalanceSheetValidationReport("Rebalance");
        console2.log("executeRebalanceWallet post-batch validation passed");
    }

    /// @notice Sweep wallet USDe into wallet sUSDe via ERC4626 deposit
    /// @dev    This does not supply to Aave. It only transforms wallet USDe into wallet sUSDe.
    ///         If usdeSweepAmount is 0 or omitted, full wallet USDe balance is swept.
    function executeSweepWalletUsdeToSusde(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithYieldMS(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
    {
        _loadTokens();
        _initCacheMode(CacheMode.None);
        _captureInitialAccountSnapshot();

        _sweepInitialWalletUsdeBalance = _usde.balanceOf(_owner);
        _sweepInitialWalletSusdeBalance = _susde.balanceOf(_owner);
        _sweepWalletUsdeAmount = _readOptionalUint256(
            "executeSweepWalletUsdeToSusde",
            "usdeSweepAmount",
            0
        );

        if (_sweepWalletUsdeAmount == 0) {
            _sweepWalletUsdeAmount = _sweepInitialWalletUsdeBalance;
        }
        if (_sweepWalletUsdeAmount == 0) revert("No wallet USDe to sweep");
        if (_sweepWalletUsdeAmount > _sweepInitialWalletUsdeBalance) {
            revert(
                string.concat(
                    "USDe wallet balance below requested sweep: ",
                    _toDecimalString(_sweepInitialWalletUsdeBalance, 18),
                    " < ",
                    _toDecimalString(_sweepWalletUsdeAmount, 18)
                )
            );
        }

        console2.log("=== Execute wallet USDe sweep into sUSDe ===");
        console2.log("Owner:", _owner);
        console2.log(
            "[Wallet] Initial USDe balance:",
            _toDecimalString(_sweepInitialWalletUsdeBalance, 18)
        );
        console2.log(
            "[Wallet] Initial sUSDe balance:",
            _toDecimalString(_sweepInitialWalletSusdeBalance, 18)
        );
        console2.log(
            "[Sweep] USDe amount to deposit into sUSDe:",
            _toDecimalString(_sweepWalletUsdeAmount, 18)
        );

        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(_susde), 0),
            "Reset USDe approval for wallet sweep deposit"
        );
        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(_susde), _sweepWalletUsdeAmount),
            string.concat(
                "Approve USDe for wallet sweep amount=",
                _toDecimalString(_sweepWalletUsdeAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(_susde),
            abi.encodeWithSelector(IERC4626.deposit.selector, _sweepWalletUsdeAmount, _owner),
            string.concat(
                "Deposit USDe into wallet sUSDe amount=",
                _toDecimalString(_sweepWalletUsdeAmount, 18)
            )
        );
        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(_susde), 0),
            "Zero USDe -> sUSDe sweep approval"
        );

        _setPostBatchValidateSelector(
            this._validateExecuteSweepWalletUsdeToSusdePostBatch.selector
        );

        proposeBatch();
    }

    function _validateExecuteSweepWalletUsdeToSusdePostBatch() external view {
        uint256 walletUsdeAfter = _usde.balanceOf(_owner);
        uint256 walletSusdeAfter = _susde.balanceOf(_owner);

        if (walletUsdeAfter + _sweepWalletUsdeAmount != _sweepInitialWalletUsdeBalance) {
            revert("Unexpected USDe accounting after sweep");
        }
        if (walletSusdeAfter <= _sweepInitialWalletSusdeBalance) {
            revert("sUSDe wallet balance did not increase after sweep");
        }

        uint256 susdeReceived = walletSusdeAfter - _sweepInitialWalletSusdeBalance;

        console2.log("\n--- Sweep post-batch summary ---");
        console2.log("[Sweep] USDe swept:", _toDecimalString(_sweepWalletUsdeAmount, 18));
        console2.log("[Sweep] sUSDe received:", _toDecimalString(susdeReceived, 18));
        console2.log("[Wallet] USDe balance after:", _toDecimalString(walletUsdeAfter, 18));
        console2.log("[Wallet] sUSDe balance after:", _toDecimalString(walletSusdeAfter, 18));
        _logBalanceSheetValidationReport("Sweep");
        console2.log("executeSweepWalletUsdeToSusde post-batch validation passed");
    }

    /// @notice Execute one max-safe unwind iteration for the sUSDe/USDe Aave loop position
    /// @dev    Unwind order is repay-first, then collateral release:
    ///         1) swap wallet sUSDe -> USDT -> repay USDT
    ///         2) withdraw USDe collateral
    ///         3) swap USDe -> USDT -> repay USDT
    ///         4) withdraw safe sUSDe collateral to wallet
    function executeUnwindLoop(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithYieldMS(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
    {
        _loadTokens();
        _initCacheMode(CacheMode.ExecuteUnwind);

        _initialSusdeBalance = _susde.balanceOf(_owner);

        uint256 slippageBps = _readOptionalUint256(
            "executeUnwindLoop",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        uint256 minHealthFactor = _readOptionalUint256(
            "executeUnwindLoop",
            "minHealthFactor",
            DEFAULT_MIN_HEALTH_FACTOR
        );
        if (minHealthFactor < 1e18) revert("minHealthFactor below 1.0");

        uint256 minSwap1ValueRatioBps = _getUnwindMinSwapUsdeUsdtValueRatioBps();
        if (minSwap1ValueRatioBps == 0 || minSwap1ValueRatioBps > 10000) {
            revert("Swap #1 min value ratio invalid");
        }

        uint256 minSwap2ValueRatioBps = _getUnwindMinSwapSusdeUsdtValueRatioBps();
        if (minSwap2ValueRatioBps == 0 || minSwap2ValueRatioBps > 10000) {
            revert("Swap #2 min value ratio invalid");
        }

        uint256 maxSusdeSwapIn = _readOptionalUint256(
            "executeUnwindLoop",
            "maxSusdeSwapIn",
            DEFAULT_MAX_SUSDE_SWAP_IN
        );
        _kyberExcludedSources = _readOptionalString(
            "executeUnwindLoop",
            "kyberExcludedSources",
            ""
        );

        _cacheArgsFingerprint = _computeUnwindArgsFingerprint();
        _validateReplayCacheMetadata(CACHE_FUNCTION_UNWIND, _cacheArgsFingerprint);

        _captureInitialAccountSnapshot();

        _skipHeartbeatValidation = SKIP_HEARTBEAT;
        UnwindConfig memory config = UnwindConfig({
            slippageBps: slippageBps,
            minHealthFactor: minHealthFactor,
            minSwap1ValueRatioBps: minSwap1ValueRatioBps,
            minSwap2ValueRatioBps: minSwap2ValueRatioBps,
            maxSusdeSwapIn: maxSusdeSwapIn
        });
        UnwindPlan memory plan = _computeUnwindPlan(config);

        if (
            plan.conservativeRepay0 == 0 &&
            plan.conservativeRepay1 == 0 &&
            plan.susdeWithdrawAmountFinal == 0
        ) {
            revert("No safe unwind action available");
        }

        _expectedMinHealthFactor = minHealthFactor;
        _expectedMaxDebtBase = plan.debtAfterStep2 + DEBT_VALIDATION_TOLERANCE_BASE;
        _expectedMinSusdeOut =
            _initialSusdeBalance -
            plan.walletSusdeSwapAmount +
            plan.susdeWithdrawAmountFinal;

        if (plan.walletSusdeSwapAmount > 0) {
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(plan.routerWalletSusdeToUsdt, 0),
                "Reset sUSDe approval for wallet swap"
            );
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(plan.routerWalletSusdeToUsdt, plan.walletSusdeSwapAmount),
                string.concat(
                    "Approve sUSDe for wallet swap amount=",
                    _toDecimalString(plan.walletSusdeSwapAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                plan.routerWalletSusdeToUsdt,
                plan.swapCalldataWalletSusdeToUsdt,
                "Swap sUSDe -> USDT"
            );
            if (plan.conservativeRepay0 > 0) {
                _addToBatchWithStepLog(
                    address(_usdt),
                    _encodeApprove(address(AAVE_POOL), 0),
                    "Reset USDT approval for repay 0"
                );
                _addToBatchWithStepLog(
                    address(_usdt),
                    _encodeApprove(address(AAVE_POOL), plan.conservativeRepay0),
                    string.concat(
                        "Approve USDT for repay 0 amount=",
                        _toDecimalString(plan.conservativeRepay0, 6)
                    )
                );
                _addToBatchWithStepLog(
                    address(AAVE_POOL),
                    _encodeRepay(address(_usdt), plan.conservativeRepay0, _owner),
                    string.concat(
                        "Repay USDT debt (wallet leg) amount=",
                        _toDecimalString(plan.conservativeRepay0, 6)
                    )
                );
            }
        }

        if (plan.usdeWithdrawAmount1 > 0) {
            _addToBatchWithStepLog(
                address(AAVE_POOL),
                _encodeWithdraw(address(_usde), plan.usdeWithdrawAmount1, _owner),
                string.concat(
                    "Withdraw USDe collateral amount=",
                    _toDecimalString(plan.usdeWithdrawAmount1, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(plan.routerUsdeToUsdt, 0),
                "Reset USDe approval for swap"
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(plan.routerUsdeToUsdt, plan.usdeWithdrawAmount1),
                string.concat(
                    "Approve USDe for swap amount=",
                    _toDecimalString(plan.usdeWithdrawAmount1, 18)
                )
            );
            _addToBatchWithStepLog(
                plan.routerUsdeToUsdt,
                plan.swapCalldataUsdeToUsdt,
                "Swap USDe -> USDT"
            );
            if (plan.conservativeRepay1 > 0) {
                _addToBatchWithStepLog(
                    address(_usdt),
                    _encodeApprove(address(AAVE_POOL), 0),
                    "Reset USDT approval for repay 1"
                );
                _addToBatchWithStepLog(
                    address(_usdt),
                    _encodeApprove(address(AAVE_POOL), plan.conservativeRepay1),
                    string.concat(
                        "Approve USDT for repay 1 amount=",
                        _toDecimalString(plan.conservativeRepay1, 6)
                    )
                );
                _addToBatchWithStepLog(
                    address(AAVE_POOL),
                    _encodeRepay(address(_usdt), plan.conservativeRepay1, _owner),
                    string.concat(
                        "Repay USDT debt (USDe leg) amount=",
                        _toDecimalString(plan.conservativeRepay1, 6)
                    )
                );
            }
        }

        if (plan.susdeWithdrawAmountFinal > 0) {
            _addToBatchWithStepLog(
                address(AAVE_POOL),
                _encodeWithdraw(address(_susde), plan.susdeWithdrawAmountFinal, _owner),
                string.concat(
                    "Withdraw sUSDe collateral amount=",
                    _toDecimalString(plan.susdeWithdrawAmountFinal, 18)
                )
            );
        }

        _addToBatchWithStepLog(
            address(_usdt),
            _encodeApprove(address(AAVE_POOL), 0),
            "Zero USDT -> Aave approval"
        );
        if (plan.routerUsdeToUsdt != address(0)) {
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(plan.routerUsdeToUsdt, 0),
                "Zero USDe -> swap router approval"
            );
        }
        if (plan.routerWalletSusdeToUsdt != address(0)) {
            _addToBatchWithStepLog(
                address(_susde),
                _encodeApprove(plan.routerWalletSusdeToUsdt, 0),
                "Zero sUSDe -> wallet swap router approval"
            );
        }
        _setPostBatchValidateSelector(this._validateExecuteUnwindLoopPostBatch.selector);

        proposeBatch();

        _writeUnwindMetadataCache(
            slippageBps,
            minHealthFactor,
            minSwap1ValueRatioBps,
            minSwap2ValueRatioBps,
            maxSusdeSwapIn,
            _kyberExcludedSources,
            _initialSusdeBalance
        );
    }

    function _computeUnwindPlan(
        UnwindConfig memory config
    ) internal returns (UnwindPlan memory plan) {
        _unwindSlippageBps = config.slippageBps;
        _unwindMinHealthFactor = config.minHealthFactor;
        _unwindMinSwap1ValueRatioBps = config.minSwap1ValueRatioBps;
        _unwindMinSwap2ValueRatioBps = config.minSwap2ValueRatioBps;
        _unwindMaxSusdeSwapIn = config.maxSusdeSwapIn;

        UnwindStep1Outputs memory step1 = _computeUnwindStep1();

        plan.walletSusdeSwapAmount = step1.walletSusdeSwapAmount;
        plan.conservativeRepay0 = step1.conservativeRepay0;
        plan.routerWalletSusdeToUsdt = step1.routerWalletSusdeToUsdt;
        plan.swapCalldataWalletSusdeToUsdt = step1.swapCalldataWalletSusdeToUsdt;
        plan.usdeWithdrawAmount1 = step1.usdeWithdrawAmount1;
        plan.conservativeRepay1 = step1.conservativeRepay1;
        plan.routerUsdeToUsdt = step1.routerUsdeToUsdt;
        plan.swapCalldataUsdeToUsdt = step1.swapCalldataUsdeToUsdt;

        plan.debtAfterStep2 = step1.debtAfterStep1;
        uint256 finalCollateralReductionBase = _maxCollateralReductionForMinHealthFactor(
            step1.collateralAfterStep1,
            step1.debtAfterStep1,
            step1.currentLiquidationThreshold,
            _unwindMinHealthFactor
        );
        plan.susdeWithdrawAmountFinal = _min(
            step1.susdeATokenBalance,
            _baseToSusdeAmount(finalCollateralReductionBase)
        );

        _logUnwindPlanWithBatchSteps(plan, _batchTargets.length);
    }

    function _logUnwindPlanWithBatchSteps(UnwindPlan memory plan, uint256 baseStep) internal pure {
        UnwindActionSteps memory steps = _computeUnwindActionSteps(plan, baseStep);

        console2.log("\n--- Unwind plan (conservative, batch-index aligned) ---");
        if (plan.walletSusdeSwapAmount > 0) {
            console2.log(
                string.concat(
                    "[Step ",
                    vm.toString(steps.walletSwap),
                    "] Wallet sUSDe swap input:"
                ),
                _toDecimalString(plan.walletSusdeSwapAmount, 18)
            );
        }
        if (plan.conservativeRepay0 > 0) {
            console2.log(
                string.concat(
                    "[Step ",
                    vm.toString(steps.walletRepay),
                    "] Conservative USDT repay:"
                ),
                _toDecimalString(plan.conservativeRepay0, 6)
            );
        }
        if (plan.usdeWithdrawAmount1 > 0) {
            console2.log(
                string.concat(
                    "[Step ",
                    vm.toString(steps.usdeWithdraw),
                    "] USDe collateral withdraw:"
                ),
                _toDecimalString(plan.usdeWithdrawAmount1, 18)
            );
            console2.log(
                string.concat(
                    "[Step ",
                    vm.toString(steps.usdeSwap),
                    "] Swap USDe -> USDT quote leg"
                )
            );
        }
        if (plan.conservativeRepay1 > 0) {
            console2.log(
                string.concat("[Step ", vm.toString(steps.usdeRepay), "] Conservative USDT repay:"),
                _toDecimalString(plan.conservativeRepay1, 6)
            );
        }
        if (plan.susdeWithdrawAmountFinal > 0) {
            console2.log(
                string.concat(
                    "[Step ",
                    vm.toString(steps.susdeWithdraw),
                    "] sUSDe collateral withdraw:"
                ),
                _toDecimalString(plan.susdeWithdrawAmountFinal, 18)
            );
        }
        console2.log(
            "[Iteration] Total conservative USDT repay:",
            _toDecimalString(plan.conservativeRepay0 + plan.conservativeRepay1, 6)
        );
    }

    function _computeUnwindActionSteps(
        UnwindPlan memory plan,
        uint256 baseStep
    ) internal pure returns (UnwindActionSteps memory steps) {
        uint256 step = baseStep;

        if (plan.walletSusdeSwapAmount > 0) {
            step += 2;
            steps.walletSwap = step;
            step += 1;

            if (plan.conservativeRepay0 > 0) {
                step += 2;
                steps.walletRepay = step;
                step += 1;
            }
        }

        if (plan.usdeWithdrawAmount1 > 0) {
            steps.usdeWithdraw = step;
            step += 1;

            step += 2;
            steps.usdeSwap = step;
            step += 1;

            if (plan.conservativeRepay1 > 0) {
                step += 2;
                steps.usdeRepay = step;
                step += 1;
            }
        }

        if (plan.susdeWithdrawAmountFinal > 0) {
            steps.susdeWithdraw = step;
        }
    }

    function _computeUnwindStep1() internal returns (UnwindStep1Outputs memory step1) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor
        ) = _getUnwindPlanningAccountData();

        if (totalDebtBase == 0) revert("No debt to unwind");
        if (currentLiquidationThreshold == 0) revert("Liquidation threshold is zero");

        uint256 usdtStableDebt;
        uint256 usdtVariableDebt;
        (
            step1.usdeATokenBalance,
            step1.susdeATokenBalance,
            usdtStableDebt,
            usdtVariableDebt
        ) = _getUnwindReserveData();

        if (usdtStableDebt > 0) revert("Stable USDT debt not supported");
        if (usdtVariableDebt == 0) revert("No variable USDT debt");

        console2.log(
            "=== Execute Unwind Iteration: USDe/sUSDe -> USDT repay -> collateral release ==="
        );
        console2.log("Owner:", _owner);
        console2.log("Slippage (bps):", _unwindSlippageBps);
        console2.log("Minimum health factor:", _toDecimalString(_unwindMinHealthFactor, 18));
        console2.log("Current health factor:", _toDecimalString(healthFactor, 18));
        console2.log("Current collateral:", _toDecimalString(totalCollateralBase, 8));
        console2.log("Current debt:", _toDecimalString(totalDebtBase, 8));
        console2.log("Current USDT variable debt:", _toDecimalString(usdtVariableDebt, 6));

        step1.currentLiquidationThreshold = currentLiquidationThreshold;

        UnwindWalletRepayOutputs memory walletRepay = _computeWalletSusdeRepay(
            totalDebtBase,
            usdtVariableDebt
        );
        step1.walletSusdeSwapAmount = walletRepay.walletSusdeSwapAmount;
        step1.conservativeRepay0 = walletRepay.conservativeRepay0;
        step1.routerWalletSusdeToUsdt = walletRepay.routerWalletSusdeToUsdt;
        step1.swapCalldataWalletSusdeToUsdt = walletRepay.swapCalldataWalletSusdeToUsdt;

        uint256 collateralReductionBase = _maxCollateralReductionForMinHealthFactor(
            totalCollateralBase,
            walletRepay.totalDebtBaseAfterWalletRepay,
            currentLiquidationThreshold,
            _unwindMinHealthFactor
        );
        if (collateralReductionBase == 0) revert("No safe collateral headroom");

        uint256 usdeWithdrawBase = _min(
            collateralReductionBase,
            _usdeToBaseValue(step1.usdeATokenBalance)
        );
        uint256 debtNotionalUsde = FullMath.mulDiv(walletRepay.usdtDebtAfterWalletRepay, 1e18, 1e6);
        if (usdeWithdrawBase > 0) {
            uint256 usdeWithdrawAmountPreview = _baseToUsdeAmount(usdeWithdrawBase);
            if (usdeWithdrawAmountPreview > debtNotionalUsde) {
                usdeWithdrawBase = _usdeToBaseValue(debtNotionalUsde);
            }
        }
        step1.usdeWithdrawAmount1 = _baseToUsdeAmount(usdeWithdrawBase);

        (
            step1.routerUsdeToUsdt,
            step1.swapCalldataUsdeToUsdt,
            step1.conservativeRepay1
        ) = _planUsdeRepayLeg(step1.usdeWithdrawAmount1, walletRepay.usdtDebtAfterWalletRepay);

        step1.collateralAfterStep1 = totalCollateralBase - usdeWithdrawBase;
        step1.debtAfterStep1 = _debtBaseAfterRepay(
            walletRepay.totalDebtBaseAfterWalletRepay,
            walletRepay.usdtDebtAfterWalletRepay,
            step1.conservativeRepay1
        );
        step1.usdtDebtAfterStep1 = walletRepay.usdtDebtAfterWalletRepay - step1.conservativeRepay1;
    }

    function _computeWalletSusdeRepay(
        uint256 totalDebtBase,
        uint256 usdtVariableDebt
    ) internal returns (UnwindWalletRepayOutputs memory walletRepay) {
        uint256 debtNotionalSusde = _usdeToSusdeSharesCached(
            CACHE_KEY_UNWIND_4626_STEP1_DEBT_SHARES,
            FullMath.mulDiv(usdtVariableDebt, 1e18, 1e6)
        );
        walletRepay.walletSusdeSwapAmount = _min(_initialSusdeBalance, debtNotionalSusde);
        (
            walletRepay.routerWalletSusdeToUsdt,
            walletRepay.swapCalldataWalletSusdeToUsdt,
            walletRepay.conservativeRepay0,

        ) = _planSusdeRepayLeg(
            "Step 1 swap (wallet sUSDe -> USDT)",
            CACHE_KEY_UNWIND_4626_STEP1_INPUT_VALUE,
            walletRepay.walletSusdeSwapAmount,
            usdtVariableDebt
        );
        walletRepay.totalDebtBaseAfterWalletRepay = _debtBaseAfterRepay(
            totalDebtBase,
            usdtVariableDebt,
            walletRepay.conservativeRepay0
        );
        walletRepay.usdtDebtAfterWalletRepay = usdtVariableDebt - walletRepay.conservativeRepay0;
    }

    function _planUsdeRepayLeg(
        uint256 usdeWithdrawAmount,
        uint256 maxRepayAmount
    ) internal returns (address router, bytes memory swapCalldata, uint256 conservativeRepay) {
        if (usdeWithdrawAmount == 0) return (address(0), bytes(""), 0);

        uint256 usdtAmountOut;
        (router, swapCalldata, usdtAmountOut) = _getKyberSwapCalldata(
            "Step 3 swap (USDe -> USDT)",
            address(_usde),
            address(_usdt),
            usdeWithdrawAmount,
            _unwindSlippageBps
        );

        _logAndValidateValueRatio(
            "Step 3 swap (USDe -> USDT)",
            _usdtToUsd18(usdtAmountOut),
            usdeWithdrawAmount,
            _unwindMinSwap1ValueRatioBps
        );

        conservativeRepay = _min(
            FullMath.mulDiv(usdtAmountOut, 10000 - _unwindSlippageBps, 10000),
            maxRepayAmount
        );
    }

    function _planSusdeRepayLeg(
        string memory swapLabel,
        string memory susdeInputValueCacheKey,
        uint256 susdeSwapAmount,
        uint256 maxRepayAmount
    )
        internal
        returns (
            address router,
            bytes memory swapCalldata,
            uint256 conservativeRepay,
            uint256 susdeSwapValueBase
        )
    {
        if (susdeSwapAmount == 0) return (address(0), bytes(""), 0, 0);

        uint256 usdtAmountOut;
        (router, swapCalldata, usdtAmountOut) = _getKyberSwapCalldata(
            swapLabel,
            address(_susde),
            address(_usdt),
            susdeSwapAmount,
            _unwindSlippageBps
        );

        uint256 susdeInputNotionalUsd = _susdeToUsdeValueCached(
            susdeInputValueCacheKey,
            susdeSwapAmount
        );
        _logAndValidateValueRatio(
            swapLabel,
            _usdtToUsd18(usdtAmountOut),
            susdeInputNotionalUsd,
            _unwindMinSwap2ValueRatioBps
        );

        conservativeRepay = _min(
            FullMath.mulDiv(usdtAmountOut, 10000 - _unwindSlippageBps, 10000),
            maxRepayAmount
        );
        susdeSwapValueBase = _susdeToBaseValue(susdeSwapAmount);
    }

    function _computeUnwindStep2(
        UnwindStep2Inputs memory inputs
    )
        internal
        returns (
            uint256 susdeSwapAmount,
            address routerSusdeToUsdt,
            bytes memory swapCalldataSusdeToUsdt,
            uint256 conservativeRepay2,
            uint256 debtAfterStep2,
            uint256 usdeWithdrawAmountFinal,
            uint256 susdeWithdrawAmountFinal
        )
    {
        uint256 collateralReductionBaseStep2 = _maxCollateralReductionForMinHealthFactor(
            inputs.collateralAfterStep1,
            inputs.debtAfterStep1,
            inputs.currentLiquidationThreshold,
            _unwindMinHealthFactor
        );

        uint256 susdeSwapCap = _unwindMaxSusdeSwapIn == 0
            ? inputs.susdeATokenBalance
            : _min(_unwindMaxSusdeSwapIn, inputs.susdeATokenBalance);
        uint256 susdeSwapByHealthFactor = _baseToSusdeAmount(collateralReductionBaseStep2);
        susdeSwapAmount = _min(susdeSwapCap, susdeSwapByHealthFactor);
        if (susdeSwapAmount > 0) {
            uint256 debtNotionalSusde = _usdeToSusdeSharesCached(
                CACHE_KEY_UNWIND_4626_STEP2_DEBT_SHARES,
                FullMath.mulDiv(inputs.usdtDebtAfterStep1, 1e18, 1e6)
            );
            susdeSwapAmount = _min(susdeSwapAmount, debtNotionalSusde);
        }

        uint256 susdeSwapValueBase;
        (
            routerSusdeToUsdt,
            swapCalldataSusdeToUsdt,
            conservativeRepay2,
            susdeSwapValueBase
        ) = _planSusdeRepayLeg(
            "Step 5 swap (sUSDe -> USDT)",
            CACHE_KEY_UNWIND_4626_STEP5_INPUT_VALUE,
            susdeSwapAmount,
            inputs.usdtDebtAfterStep1
        );

        uint256 collateralAfterStep2 = inputs.collateralAfterStep1 - susdeSwapValueBase;
        debtAfterStep2 = _debtBaseAfterRepay(
            inputs.debtAfterStep1,
            inputs.usdtDebtAfterStep1,
            conservativeRepay2
        );

        (usdeWithdrawAmountFinal, susdeWithdrawAmountFinal) = _computeFinalUnwindWithdrawals(
            inputs,
            collateralAfterStep2,
            debtAfterStep2,
            susdeSwapAmount
        );
    }

    function _computeFinalUnwindWithdrawals(
        UnwindStep2Inputs memory inputs,
        uint256 collateralAfterStep2,
        uint256 debtAfterStep2,
        uint256 susdeSwapAmount
    ) internal view returns (uint256 usdeWithdrawAmountFinal, uint256 susdeWithdrawAmountFinal) {
        uint256 finalCollateralReductionBase = _maxCollateralReductionForMinHealthFactor(
            collateralAfterStep2,
            debtAfterStep2,
            inputs.currentLiquidationThreshold,
            _unwindMinHealthFactor
        );

        uint256 usdeRemainingAToken = inputs.usdeATokenBalance > inputs.usdeWithdrawAmount1
            ? inputs.usdeATokenBalance - inputs.usdeWithdrawAmount1
            : 0;
        uint256 usdeWithdrawBaseFinal = _min(
            finalCollateralReductionBase,
            _usdeToBaseValue(usdeRemainingAToken)
        );
        usdeWithdrawAmountFinal = _baseToUsdeAmount(usdeWithdrawBaseFinal);

        uint256 susdeRemainingAToken = inputs.susdeATokenBalance > susdeSwapAmount
            ? inputs.susdeATokenBalance - susdeSwapAmount
            : 0;
        uint256 remainingCollateralReductionBase = finalCollateralReductionBase -
            usdeWithdrawBaseFinal;
        susdeWithdrawAmountFinal = _min(
            susdeRemainingAToken,
            _baseToSusdeAmount(remainingCollateralReductionBase)
        );
    }

    function _validateExecuteUnwindLoopPostBatch() external view {
        (uint256 collateralAfter, uint256 debtAfter, , , , uint256 healthFactorAfter) = AAVE_POOL
            .getUserAccountData(_owner);

        if (healthFactorAfter < _expectedMinHealthFactor) {
            revert(
                string.concat(
                    "Health factor below minimum: ",
                    _toDecimalString(healthFactorAfter, 18),
                    " < ",
                    _toDecimalString(_expectedMinHealthFactor, 18)
                )
            );
        }

        if (debtAfter > _expectedMaxDebtBase) {
            revert(
                string.concat(
                    "Debt reduction below conservative expectation: ",
                    _toDecimalString(debtAfter, 8),
                    " > ",
                    _toDecimalString(_expectedMaxDebtBase, 8)
                )
            );
        }

        uint256 susdeBalanceAfter = _susde.balanceOf(_owner);
        if (susdeBalanceAfter < _expectedMinSusdeOut) {
            revert("sUSDe balance below conservative expectation");
        }

        console2.log("\n--- Post-batch summary (unwind) ---");
        console2.log("[Position] Collateral after:", _toDecimalString(collateralAfter, 8));
        console2.log("[Position] Debt after:", _toDecimalString(debtAfter, 8));
        console2.log("[Position] Health factor after:", _toDecimalString(healthFactorAfter, 18));
        console2.log("[Position] sUSDe wallet balance:", _toDecimalString(susdeBalanceAfter, 18));
        _logBalanceSheetValidationReport("Unwind");
        console2.log("executeUnwindLoop post-batch validation passed");
    }

    function _addLoopActionsToBatch(
        uint256 susdeSupplyAmount,
        uint256 usdtBorrowAmount1,
        uint256 usdeSupplyAmount,
        uint256 usdtBorrowAmount2,
        uint256 usdeSweepToSusdeAmount,
        address routerUsdtToUsde,
        bytes memory swapCalldataUsdtToUsde,
        address routerUsdtToSusde,
        bytes memory swapCalldataUsdtToSusde
    ) internal {
        _addToBatchWithStepLog(
            address(_susde),
            _encodeApprove(address(AAVE_POOL), susdeSupplyAmount),
            string.concat("Approve sUSDe -> Aave amount=", _toDecimalString(susdeSupplyAmount, 18))
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSupply(address(_susde), susdeSupplyAmount, _owner),
            string.concat("Supply sUSDe amount=", _toDecimalString(susdeSupplyAmount, 18))
        );
        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeSetUserUseReserveAsCollateral(address(_susde), true),
            "Enable sUSDe as collateral"
        );

        _addToBatchWithStepLog(
            address(AAVE_POOL),
            _encodeBorrow(address(_usdt), usdtBorrowAmount1, _owner),
            string.concat("Borrow USDT amount 1 amount=", _toDecimalString(usdtBorrowAmount1, 6))
        );

        // USDT uses a non-standard approve that requires resetting to 0 before setting a new value.
        // This pattern is applied before each swap below (steps 5 and 8).

        _addToBatchWithStepLog(
            address(_usdt),
            _encodeApprove(routerUsdtToUsde, 0),
            "Reset USDT approval for swap 1 router"
        );
        _addToBatchWithStepLog(
            address(_usdt),
            _encodeApprove(routerUsdtToUsde, usdtBorrowAmount1),
            string.concat("Approve USDT for swap 1 amount=", _toDecimalString(usdtBorrowAmount1, 6))
        );
        _addToBatchWithStepLog(
            routerUsdtToUsde,
            swapCalldataUsdtToUsde,
            string.concat("Swap USDT -> USDe amountIn=", _toDecimalString(usdtBorrowAmount1, 6))
        );

        if (usdeSupplyAmount > 0) {
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(AAVE_POOL), usdeSupplyAmount),
                string.concat(
                    "Approve USDe -> Aave amount=",
                    _toDecimalString(usdeSupplyAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                address(AAVE_POOL),
                _encodeSupply(address(_usde), usdeSupplyAmount, _owner),
                string.concat("Supply USDe amount=", _toDecimalString(usdeSupplyAmount, 18))
            );
            _addToBatchWithStepLog(
                address(AAVE_POOL),
                _encodeSetUserUseReserveAsCollateral(address(_usde), true),
                "Enable USDe as collateral"
            );
        }

        if (usdeSweepToSusdeAmount > 0) {
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), 0),
                "Reset USDe approval for sUSDe sweep deposit"
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), usdeSweepToSusdeAmount),
                string.concat(
                    "Approve USDe for sUSDe sweep amount=",
                    _toDecimalString(usdeSweepToSusdeAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_susde),
                abi.encodeWithSelector(IERC4626.deposit.selector, usdeSweepToSusdeAmount, _owner),
                string.concat(
                    "Sweep leftover USDe into sUSDe wallet amount=",
                    _toDecimalString(usdeSweepToSusdeAmount, 18)
                )
            );
            _addToBatchWithStepLog(
                address(_usde),
                _encodeApprove(address(_susde), 0),
                "Zero USDe -> sUSDe sweep approval"
            );
        }

        if (usdtBorrowAmount2 > 0) {
            _addToBatchWithStepLog(
                address(AAVE_POOL),
                _encodeBorrow(address(_usdt), usdtBorrowAmount2, _owner),
                string.concat(
                    "Borrow USDT amount 2 amount=",
                    _toDecimalString(usdtBorrowAmount2, 6)
                )
            );

            _addToBatchWithStepLog(
                address(_usdt),
                _encodeApprove(routerUsdtToSusde, 0),
                "Reset USDT approval for swap 2 router"
            );
            _addToBatchWithStepLog(
                address(_usdt),
                _encodeApprove(routerUsdtToSusde, usdtBorrowAmount2),
                string.concat(
                    "Approve USDT for swap 2 amount=",
                    _toDecimalString(usdtBorrowAmount2, 6)
                )
            );
            _addToBatchWithStepLog(
                routerUsdtToSusde,
                swapCalldataUsdtToSusde,
                string.concat(
                    "Swap USDT -> sUSDe amountIn=",
                    _toDecimalString(usdtBorrowAmount2, 6)
                )
            );
        }

        _addToBatchWithStepLog(
            address(_susde),
            _encodeApprove(address(AAVE_POOL), 0),
            "Zero sUSDe -> Aave approval"
        );
        _addToBatchWithStepLog(
            address(_usdt),
            _encodeApprove(routerUsdtToUsde, 0),
            "Zero USDT -> swap 1 router approval"
        );
        if (routerUsdtToSusde != address(0) && routerUsdtToSusde != routerUsdtToUsde) {
            _addToBatchWithStepLog(
                address(_usdt),
                _encodeApprove(routerUsdtToSusde, 0),
                "Zero USDT -> swap 2 router approval"
            );
        }
        _addToBatchWithStepLog(
            address(_usde),
            _encodeApprove(address(AAVE_POOL), 0),
            "Zero USDe -> Aave approval"
        );
    }

    function _addToBatchWithStepLog(
        address target,
        bytes memory data,
        string memory label
    ) internal {
        uint256 step = _batchTargets.length;
        console2.log(string.concat("step ", vm.toString(step), ": ", label));
        addToBatch(target, data);
    }

    function _logBatchStepHeader(uint256 step, string memory title) internal pure {
        console2.log(string.concat("\n--- Step ", vm.toString(step), ": ", title, " ---"));
    }

    /// @notice Post-batch validation: verify the loop produced expected results
    /// @dev    Two validation checks:
    ///         1. sUSDe balance >= _expectedMinSusdeOut (slippage guard on swap #2)
    ///         2. Accounting check: wallet sUSDe + supplied sUSDe >= initial balance (no sUSDe lost)
    ///         Also reports sUSDe efficiency, collateral summary, and Aave balance sheet deltas.
    function _validateExecuteLoopPostBatch() external view {
        uint256 susdeBalanceAfter = _susde.balanceOf(_owner);
        if (susdeBalanceAfter < _expectedMinSusdeOut) {
            revert(
                string.concat(
                    "sUSDe balance should be at least ",
                    _toDecimalString(_expectedMinSusdeOut, 18),
                    ", but is ",
                    _toDecimalString(susdeBalanceAfter, 18)
                )
            );
        }

        if (susdeBalanceAfter + _susdeSuppliedAmount < _initialSusdeBalance) {
            revert("Unexpected sUSDe accounting");
        }

        uint256 walletSusdeDelta;
        bool walletSusdeIncreased = susdeBalanceAfter >= _initialSusdeBalance;
        if (walletSusdeIncreased) {
            walletSusdeDelta = susdeBalanceAfter - _initialSusdeBalance;
        } else {
            walletSusdeDelta = _initialSusdeBalance - susdeBalanceAfter;
        }

        uint256 actualSusdeOut = (susdeBalanceAfter + _susdeSuppliedAmount) - _initialSusdeBalance;
        uint256 efficiencyBps = FullMath.mulDiv(actualSusdeOut, 10000, _susdeSuppliedAmount);

        (, , , , , uint256 healthFactorAfter) = AAVE_POOL.getUserAccountData(REPORTING_MS);

        console2.log("\n--- Post-batch summary ---");
        console2.log("[Iteration] Actual sUSDe out:", _toDecimalString(actualSusdeOut, 18));
        console2.log("[Iteration] sUSDe out efficiency vs supplied sUSDe (bps):", efficiencyBps);
        if (walletSusdeIncreased) {
            console2.log(
                string.concat(
                    "[Iteration] Wallet sUSDe change: +",
                    _toDecimalString(walletSusdeDelta, 18)
                )
            );
        } else {
            console2.log(
                string.concat(
                    "[Iteration] Wallet sUSDe change: -",
                    _toDecimalString(walletSusdeDelta, 18)
                )
            );
        }
        _logCollateralSuppliedSummary();
        console2.log(
            "[Iteration] USDe swept into wallet sUSDe (batch min amount):",
            _toDecimalString(_plannedUsdeSweepToSusdeAmount, 18)
        );
        _logBalanceSheetValidationReport("Wind");
        (
            uint256 susdeCollateralValueUsdeAfter,
            uint256 usdeCollateralValueUsdeAfter
        ) = _getAaveCollateralValuesUsde(_owner);
        uint256 totalCollateralValueUsdeAfter = susdeCollateralValueUsdeAfter +
            usdeCollateralValueUsdeAfter;
        uint256 susdeShareBpsAfter = _ratioBps(
            susdeCollateralValueUsdeAfter,
            totalCollateralValueUsdeAfter
        );
        uint256 usdeShareBpsAfter = _ratioBps(
            usdeCollateralValueUsdeAfter,
            totalCollateralValueUsdeAfter
        );
        console2.log("[Position] Aave sUSDe share after (bps):", susdeShareBpsAfter);
        console2.log("[Position] Aave USDe share after (bps):", usdeShareBpsAfter);
        (
            bool gapAfterSusdeAboveTarget,
            uint256 gapAfterAbsUsde
        ) = _getCollateralTargetGapFromValues(
                susdeCollateralValueUsdeAfter,
                usdeCollateralValueUsdeAfter,
                _loopTargetSusdeShareBps
            );
        console2.log(
            "[Position] Collateral gap before (abs USDe):",
            _toDecimalString(_loopImbalanceBeforeAbsUsde, 18)
        );
        console2.log(
            "[Position] Collateral gap side before:",
            _loopImbalanceBeforeSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        console2.log(
            "[Position] Collateral gap projected (abs USDe):",
            _toDecimalString(_loopProjectedImbalanceAbsUsde, 18)
        );
        console2.log(
            "[Position] Collateral gap side projected:",
            _loopProjectedImbalanceSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        uint256 projectedVsActualGapAbsUsde = _getCollateralImbalanceDriftAbsUsde(
            _loopProjectedImbalanceSusdeOverweight,
            _loopProjectedImbalanceAbsUsde,
            gapAfterSusdeAboveTarget,
            gapAfterAbsUsde
        );
        console2.log(
            "[Position] Projected-vs-actual collateral gap drift (abs USDe):",
            _toDecimalString(projectedVsActualGapAbsUsde, 18)
        );
        if (projectedVsActualGapAbsUsde > LOOP_IMBALANCE_DRIFT_TOLERANCE_USDE) {
            revert("Loop projected/actual collateral gap drift too high");
        }
        console2.log(
            "[Position] Collateral gap after (abs USDe):",
            _toDecimalString(gapAfterAbsUsde, 18)
        );
        console2.log(
            "[Position] Collateral gap side after:",
            gapAfterSusdeAboveTarget ? "sUSDe above target" : "sUSDe below target"
        );
        if (gapAfterAbsUsde > _loopImbalanceBeforeAbsUsde + LOOP_IMBALANCE_DRIFT_TOLERANCE_USDE) {
            revert("Loop increased collateral gap to target");
        }
        console2.log(
            "[Position] Aave health factor after batch:",
            _toDecimalString(healthFactorAfter, 18)
        );
        console2.log("executeLoop post-batch validation passed");
    }

    /// @notice Log Aave balance sheet deltas (loop iteration) and total position (full account)
    /// @dev    "Loop" deltas = change from this iteration only (after - before).
    ///         "Position total" = full Aave account state including prior positions.
    function _logAaveBalanceSheetReport() internal view {
        (
            uint256 totalCollateralBaseAfter,
            uint256 totalDebtBaseAfter,
            uint256 netAccountValueBaseAfter
        ) = _getAccountSummaryBase(REPORTING_MS);

        uint256 collateralDelta;
        bool collateralIncreased = totalCollateralBaseAfter >= _initialTotalCollateralBase;
        if (collateralIncreased) {
            collateralDelta = totalCollateralBaseAfter - _initialTotalCollateralBase;
        } else {
            collateralDelta = _initialTotalCollateralBase - totalCollateralBaseAfter;
        }

        uint256 debtDelta;
        bool debtIncreased = totalDebtBaseAfter >= _initialTotalDebtBase;
        if (debtIncreased) {
            debtDelta = totalDebtBaseAfter - _initialTotalDebtBase;
        } else {
            debtDelta = _initialTotalDebtBase - totalDebtBaseAfter;
        }

        uint256 netDelta;
        bool netIncreased = netAccountValueBaseAfter >= _initialNetAccountValueBase;
        if (netIncreased) {
            netDelta = netAccountValueBaseAfter - _initialNetAccountValueBase;
        } else {
            netDelta = _initialNetAccountValueBase - netAccountValueBaseAfter;
        }

        if (collateralIncreased) {
            console2.log(
                string.concat(
                    "[Iteration] Collateral change: +",
                    _toDecimalString(collateralDelta, 8)
                )
            );
        } else {
            console2.log(
                string.concat(
                    "[Iteration] Collateral change: -",
                    _toDecimalString(collateralDelta, 8)
                )
            );
        }

        if (debtIncreased) {
            console2.log(
                string.concat("[Iteration] Debt change: +", _toDecimalString(debtDelta, 8))
            );
        } else {
            console2.log(
                string.concat("[Iteration] Debt change: -", _toDecimalString(debtDelta, 8))
            );
        }

        if (netIncreased) {
            console2.log(
                string.concat(
                    "[Iteration] Net account value change: +",
                    _toDecimalString(netDelta, 8)
                )
            );
        } else {
            console2.log(
                string.concat(
                    "[Iteration] Net account value change: -",
                    _toDecimalString(netDelta, 8)
                )
            );
        }

        console2.log("[Position] Total collateral:", _toDecimalString(totalCollateralBaseAfter, 8));
        console2.log("[Position] Total debt:", _toDecimalString(totalDebtBaseAfter, 8));
        console2.log(
            "[Position] Net (collateral - debt):",
            _toDecimalString(netAccountValueBaseAfter, 8)
        );

        if (collateralDelta > 0 && debtIncreased) {
            uint256 efficiencyBps = FullMath.mulDiv(debtDelta, 10000, collateralDelta);
            uint256 debtCoverageBps = _ratioBps(collateralDelta, debtDelta);
            console2.log("Loop iteration efficiency (debt/collateral, bps):", efficiencyBps);
            console2.log("  = %d.%d%%", efficiencyBps / 100, efficiencyBps % 100);
            console2.log("[Iteration] Collateral/debt coverage (bps):", debtCoverageBps);

            uint256 unwindGap;
            bool unwindGapPositive = collateralDelta >= debtDelta;
            if (unwindGapPositive) {
                unwindGap = collateralDelta - debtDelta;
                console2.log(
                    string.concat(
                        "[Iteration] Immediate unwind surplus (USD): +",
                        _toDecimalString(unwindGap, 8)
                    )
                );
            } else {
                unwindGap = debtDelta - collateralDelta;
                console2.log(
                    string.concat(
                        "[Iteration] Immediate unwind gap (USD): -",
                        _toDecimalString(unwindGap, 8)
                    )
                );
            }
        }
    }

    function _logCollateralSuppliedSummary() internal view {
        uint256 susdeSuppliedValue = _susdeToUsdeValue(_susdeSuppliedAmount);
        uint256 susdeSuppliedValueBase = FullMath.mulDiv(
            susdeSuppliedValue,
            10 ** BASE_CURRENCY_DECIMALS,
            1e18
        );
        uint256 usdeSuppliedValueBase = FullMath.mulDiv(
            _usdeSuppliedAmount,
            10 ** BASE_CURRENCY_DECIMALS,
            1e18
        );
        uint256 totalNewCollateralBase = susdeSuppliedValueBase + usdeSuppliedValueBase;

        console2.log("\n--- Collateral supplied (this iteration) ---");
        console2.log("[Iteration] sUSDe supplied:", _toDecimalString(_susdeSuppliedAmount, 18));
        console2.log(
            "[Iteration] sUSDe supplied value (USD):",
            _toDecimalString(susdeSuppliedValueBase, 8)
        );
        console2.log("[Iteration] USDe supplied:", _toDecimalString(_usdeSuppliedAmount, 18));
        console2.log(
            "[Iteration] USDe supplied value (USD):",
            _toDecimalString(usdeSuppliedValueBase, 8)
        );
        console2.log(
            "[Iteration] Total new collateral (USD):",
            _toDecimalString(totalNewCollateralBase, 8)
        );
        if (totalNewCollateralBase > 0) {
            console2.log(
                "sUSDe share (bps):",
                _ratioBps(susdeSuppliedValueBase, totalNewCollateralBase)
            );
            console2.log(
                "USDe share (bps):",
                _ratioBps(usdeSuppliedValueBase, totalNewCollateralBase)
            );
        }
    }

    function _getAccountSummaryBase(
        address account
    )
        internal
        view
        returns (uint256 collateralBase, uint256 debtBase, uint256 netAccountValueBase)
    {
        (collateralBase, debtBase, , , , ) = AAVE_POOL.getUserAccountData(account);
        netAccountValueBase = collateralBase > debtBase ? collateralBase - debtBase : 0;
    }

    function _captureInitialAccountSnapshot() internal {
        _initialBalanceSheet = _collectBalanceSheet(_owner);

        if (_isCacheReplay()) {
            _initialTotalCollateralBase = _cacheReadUint(
                CACHE_KEY_REPORTING_INITIAL_COLLATERAL_BASE
            );
            _initialTotalDebtBase = _cacheReadUint(CACHE_KEY_REPORTING_INITIAL_DEBT_BASE);
            _initialNetAccountValueBase = _cacheReadUint(CACHE_KEY_REPORTING_INITIAL_NET_BASE);
            return;
        }

        (
            _initialTotalCollateralBase,
            _initialTotalDebtBase,
            _initialNetAccountValueBase
        ) = _getAccountSummaryBase(REPORTING_MS);

        _cacheSetUint(CACHE_KEY_REPORTING_INITIAL_COLLATERAL_BASE, _initialTotalCollateralBase);
        _cacheSetUint(CACHE_KEY_REPORTING_INITIAL_DEBT_BASE, _initialTotalDebtBase);
        _cacheSetUint(CACHE_KEY_REPORTING_INITIAL_NET_BASE, _initialNetAccountValueBase);
    }

    function _collectBalanceSheet(
        address account
    ) internal view returns (BalanceSheetSnapshot memory snapshot) {
        snapshot.walletSusdeAmount = _susde.balanceOf(account);
        snapshot.walletUsdeAmount = _usde.balanceOf(account);
        snapshot.walletUsdtAmount = _usdt.balanceOf(account);

        (snapshot.aaveUsdeCollateralAmount, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_usde),
            account
        );
        (snapshot.aaveSusdeCollateralAmount, , , , , , , , ) = AAVE_DATA_PROVIDER
            .getUserReserveData(address(_susde), account);
        uint256 usdtStableDebt;
        uint256 usdtVariableDebt;
        (
            snapshot.aaveUsdtCollateralAmount,
            usdtStableDebt,
            usdtVariableDebt,
            ,
            ,
            ,
            ,
            ,

        ) = AAVE_DATA_PROVIDER.getUserReserveData(address(_usdt), account);

        snapshot.aaveUsdtDebtAmount = usdtStableDebt + usdtVariableDebt;

        snapshot.walletSusdeValueBase = _susdeToBaseValue(snapshot.walletSusdeAmount);
        snapshot.walletUsdeValueBase = _usdeToBaseValue(snapshot.walletUsdeAmount);
        snapshot.walletUsdtValueBase = FullMath.mulDiv(
            snapshot.walletUsdtAmount,
            BASE_CURRENCY_SCALE,
            1e6
        );
        snapshot.aaveSusdeCollateralValueBase = _susdeToBaseValue(
            snapshot.aaveSusdeCollateralAmount
        );
        snapshot.aaveUsdeCollateralValueBase = _usdeToBaseValue(snapshot.aaveUsdeCollateralAmount);
        snapshot.aaveUsdtCollateralValueBase = FullMath.mulDiv(
            snapshot.aaveUsdtCollateralAmount,
            BASE_CURRENCY_SCALE,
            1e6
        );

        (, snapshot.aaveDebtTotalBase, , , , ) = AAVE_POOL.getUserAccountData(account);

        snapshot.totalAssetsBase =
            snapshot.walletSusdeValueBase +
            snapshot.walletUsdeValueBase +
            snapshot.walletUsdtValueBase +
            snapshot.aaveSusdeCollateralValueBase +
            snapshot.aaveUsdeCollateralValueBase +
            snapshot.aaveUsdtCollateralValueBase;

        snapshot.netAssetsPositive = snapshot.totalAssetsBase >= snapshot.aaveDebtTotalBase;
        snapshot.netAssetsAbsBase = snapshot.netAssetsPositive
            ? snapshot.totalAssetsBase - snapshot.aaveDebtTotalBase
            : snapshot.aaveDebtTotalBase - snapshot.totalAssetsBase;
    }

    function _logBalanceSheetValidationReport(string memory phase) internal view {
        BalanceSheetSnapshot memory finalSnapshot = _collectBalanceSheet(_owner);

        console2.log(string.concat("\n=== ", phase, " balance sheet (validation) ==="));
        _logBalanceSheetSnapshot("Before", _initialBalanceSheet);
        _logBalanceSheetSnapshot("After", finalSnapshot);
        _logBalanceSheetDelta(_initialBalanceSheet, finalSnapshot);
        console2.log("");
    }

    function _logBalanceSheetSnapshot(
        string memory label,
        BalanceSheetSnapshot memory snapshot
    ) internal pure {
        console2.log(string.concat("--- ", label, " ---"));

        console2.log("[Wallet] sUSDe amount:", _toTwoDpString(snapshot.walletSusdeAmount, 18));
        console2.log("[Wallet] sUSDe USD:", _toTwoDpString(snapshot.walletSusdeValueBase, 8));
        console2.log("[Wallet] USDe amount:", _toTwoDpString(snapshot.walletUsdeAmount, 18));
        console2.log("[Wallet] USDe USD:", _toTwoDpString(snapshot.walletUsdeValueBase, 8));
        console2.log("[Wallet] USDT amount:", _toTwoDpString(snapshot.walletUsdtAmount, 6));
        console2.log("[Wallet] USDT USD:", _toTwoDpString(snapshot.walletUsdtValueBase, 8));

        console2.log(
            "[Aave collateral] sUSDe amount:",
            _toTwoDpString(snapshot.aaveSusdeCollateralAmount, 18)
        );
        console2.log(
            "[Aave collateral] sUSDe USD:",
            _toTwoDpString(snapshot.aaveSusdeCollateralValueBase, 8)
        );
        console2.log(
            "[Aave collateral] USDe amount:",
            _toTwoDpString(snapshot.aaveUsdeCollateralAmount, 18)
        );
        console2.log(
            "[Aave collateral] USDe USD:",
            _toTwoDpString(snapshot.aaveUsdeCollateralValueBase, 8)
        );
        console2.log(
            "[Aave collateral] USDT amount:",
            _toTwoDpString(snapshot.aaveUsdtCollateralAmount, 6)
        );
        console2.log(
            "[Aave collateral] USDT USD:",
            _toTwoDpString(snapshot.aaveUsdtCollateralValueBase, 8)
        );

        console2.log("[Aave debt] USDT amount:", _toTwoDpString(snapshot.aaveUsdtDebtAmount, 6));
        console2.log("[Aave debt] USD:", _toTwoDpString(snapshot.aaveDebtTotalBase, 8));
        console2.log(
            "[Totals] Assets (wallet + Aave collateral) USD:",
            _toTwoDpString(snapshot.totalAssetsBase, 8)
        );

        if (snapshot.netAssetsPositive) {
            console2.log(
                string.concat(
                    "[Totals] Net assets USD: +",
                    _toTwoDpString(snapshot.netAssetsAbsBase, 8)
                )
            );
        } else {
            console2.log(
                string.concat(
                    "[Totals] Net assets USD: -",
                    _toTwoDpString(snapshot.netAssetsAbsBase, 8)
                )
            );
        }
    }

    function _logBalanceSheetDelta(
        BalanceSheetSnapshot memory beforeSnapshot,
        BalanceSheetSnapshot memory afterSnapshot
    ) internal pure {
        console2.log("--- Delta (after - before) ---");

        _logSignedDelta(
            "[Wallet] sUSDe amount delta:",
            beforeSnapshot.walletSusdeAmount,
            afterSnapshot.walletSusdeAmount,
            18
        );
        _logSignedDelta(
            "[Wallet] sUSDe USD delta:",
            beforeSnapshot.walletSusdeValueBase,
            afterSnapshot.walletSusdeValueBase,
            8
        );
        _logSignedDelta(
            "[Wallet] USDe amount delta:",
            beforeSnapshot.walletUsdeAmount,
            afterSnapshot.walletUsdeAmount,
            18
        );
        _logSignedDelta(
            "[Wallet] USDe USD delta:",
            beforeSnapshot.walletUsdeValueBase,
            afterSnapshot.walletUsdeValueBase,
            8
        );
        _logSignedDelta(
            "[Wallet] USDT amount delta:",
            beforeSnapshot.walletUsdtAmount,
            afterSnapshot.walletUsdtAmount,
            6
        );
        _logSignedDelta(
            "[Wallet] USDT USD delta:",
            beforeSnapshot.walletUsdtValueBase,
            afterSnapshot.walletUsdtValueBase,
            8
        );

        _logSignedDelta(
            "[Aave collateral] sUSDe amount delta:",
            beforeSnapshot.aaveSusdeCollateralAmount,
            afterSnapshot.aaveSusdeCollateralAmount,
            18
        );
        _logSignedDelta(
            "[Aave collateral] sUSDe USD delta:",
            beforeSnapshot.aaveSusdeCollateralValueBase,
            afterSnapshot.aaveSusdeCollateralValueBase,
            8
        );
        _logSignedDelta(
            "[Aave collateral] USDe amount delta:",
            beforeSnapshot.aaveUsdeCollateralAmount,
            afterSnapshot.aaveUsdeCollateralAmount,
            18
        );
        _logSignedDelta(
            "[Aave collateral] USDe USD delta:",
            beforeSnapshot.aaveUsdeCollateralValueBase,
            afterSnapshot.aaveUsdeCollateralValueBase,
            8
        );
        _logSignedDelta(
            "[Aave collateral] USDT amount delta:",
            beforeSnapshot.aaveUsdtCollateralAmount,
            afterSnapshot.aaveUsdtCollateralAmount,
            6
        );
        _logSignedDelta(
            "[Aave collateral] USDT USD delta:",
            beforeSnapshot.aaveUsdtCollateralValueBase,
            afterSnapshot.aaveUsdtCollateralValueBase,
            8
        );

        _logSignedDelta(
            "[Aave debt] USDT amount delta:",
            beforeSnapshot.aaveUsdtDebtAmount,
            afterSnapshot.aaveUsdtDebtAmount,
            6
        );
        _logSignedDelta(
            "[Aave debt] USD delta:",
            beforeSnapshot.aaveDebtTotalBase,
            afterSnapshot.aaveDebtTotalBase,
            8
        );
        _logSignedDelta(
            "[Totals] Liabilities USD delta:",
            beforeSnapshot.aaveDebtTotalBase,
            afterSnapshot.aaveDebtTotalBase,
            8
        );
        _logSignedDelta(
            "[Totals] Assets USD delta:",
            beforeSnapshot.totalAssetsBase,
            afterSnapshot.totalAssetsBase,
            8
        );

        _logSignedDeltaWithSigns(
            "[Totals] Net assets USD delta:",
            beforeSnapshot.netAssetsPositive,
            beforeSnapshot.netAssetsAbsBase,
            afterSnapshot.netAssetsPositive,
            afterSnapshot.netAssetsAbsBase,
            8
        );
    }

    function _logSignedDelta(
        string memory label,
        uint256 beforeValue,
        uint256 afterValue,
        uint256 decimals
    ) internal pure {
        if (afterValue >= beforeValue) {
            console2.log(
                string.concat(label, " +", _toTwoDpString(afterValue - beforeValue, decimals))
            );
        } else {
            console2.log(
                string.concat(label, " -", _toTwoDpString(beforeValue - afterValue, decimals))
            );
        }
    }

    function _logSignedDeltaWithSigns(
        string memory label,
        bool beforePositive,
        uint256 beforeAbs,
        bool afterPositive,
        uint256 afterAbs,
        uint256 decimals
    ) internal pure {
        if (beforePositive && afterPositive) {
            _logSignedDelta(label, beforeAbs, afterAbs, decimals);
            return;
        }

        if (!beforePositive && !afterPositive) {
            _logSignedDelta(label, afterAbs, beforeAbs, decimals);
            return;
        }

        uint256 magnitude = beforeAbs + afterAbs;
        if (afterPositive) {
            console2.log(string.concat(label, " +", _toTwoDpString(magnitude, decimals)));
        } else {
            console2.log(string.concat(label, " -", _toTwoDpString(magnitude, decimals)));
        }
    }

    function _toTwoDpString(uint256 value, uint256 decimals) internal pure returns (string memory) {
        if (decimals == 2) return _toDecimalString(value, 2);

        if (decimals > 2) {
            uint256 scaledDown = value / (10 ** (decimals - 2));
            return _toDecimalString(scaledDown, 2);
        }

        uint256 scaledUp = value * (10 ** (2 - decimals));
        return _toDecimalString(scaledUp, 2);
    }

    // ============ Encoding Helpers ============

    function _encodeApprove(address spender, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
    }

    function _encodeSupply(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAaveV3Pool.supply.selector, asset, amount, onBehalfOf, 0);
    }

    function _encodeBorrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAaveV3Pool.borrow.selector,
                asset,
                amount,
                VARIABLE_RATE,
                0,
                onBehalfOf
            );
    }

    function _encodeWithdraw(
        address asset,
        uint256 amount,
        address to
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, asset, amount, to);
    }

    function _encodeRepay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAaveV3Pool.repay.selector,
                asset,
                amount,
                VARIABLE_RATE,
                onBehalfOf
            );
    }

    function _encodeSetUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAaveV3Pool.setUserUseReserveAsCollateral.selector,
                asset,
                useAsCollateral
            );
    }

    function _encodeSetUserEMode(uint8 categoryId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAaveV3Pool.setUserEMode.selector, categoryId);
    }

    function _estimateLoopBorrow2Usdt(
        uint256 totalExpectedBorrowsAfterSusdeSupply,
        uint256 usdtBorrowAmount1,
        uint256 usdeSupplyAmount,
        uint256 borrowPercentage
    ) internal view returns (uint256 usdtBorrowAmount2) {
        // USDe supply amount is already in 18dp; convert to Aave base (8dp USD)
        uint256 usdeSupplyValueBase = FullMath.mulDiv(
            usdeSupplyAmount,
            10 ** BASE_CURRENCY_DECIMALS,
            1e18
        );
        // Projected borrow capacity after both supplies:
        // Start from post-sUSDe capacity, subtract borrow #1 (converted 6dp→8dp via *100),
        // then add USDe LTV contribution
        uint256 totalExpectedBorrowsAfterUsdeSupply = (totalExpectedBorrowsAfterSusdeSupply -
            (usdtBorrowAmount1 * 1e2)) + ((usdeSupplyValueBase * EMODE_LTV) / 10000);

        // Convert projected capacity (8dp USD) to USDT (6dp): divide by 100
        usdtBorrowAmount2 =
            ((totalExpectedBorrowsAfterUsdeSupply * borrowPercentage) / 10000) /
            1e2;

        _logBatchStepHeader(
            _loopActionsBaseStep + 10,
            "Estimate Borrow #2 after USDe supply (this iteration)"
        );
        console2.log(
            "[Iteration] Chosen USDe supply amount (target-capped):",
            _toDecimalString(usdeSupplyAmount, 18)
        );
        console2.log(
            "[Iteration] USDe supply value (USD):",
            _toDecimalString(usdeSupplyValueBase, 8)
        );
        console2.log(
            "[Iteration] Projected available borrows after USDe supply:",
            _toDecimalString(totalExpectedBorrowsAfterUsdeSupply, 8)
        );
        console2.log("[Iteration] Borrow #2 amount USDT:", _toDecimalString(usdtBorrowAmount2, 6));
        console2.log(
            "[Iteration] Borrow #2 utilization vs projected capacity (bps):",
            _ratioBps(usdtBorrowAmount2 * 1e2, totalExpectedBorrowsAfterUsdeSupply)
        );
    }

    /// @notice Compute a conservative USDe supply amount to avoid reverts from rounding/swap slippage
    /// @dev    Takes the minimum of two estimates:
    ///         1. Quote-based: the Kyber quote output minus slippage buffer (18dp)
    ///         2. Input-notional: the USDT input converted 1:1 to USDe (6dp→18dp) minus slippage buffer
    ///         The quote may overestimate due to route optimization, while the input-notional is a
    ///         hard floor at 1:1 exchange rate. Taking the minimum protects against both overestimation
    ///         and swap shortfall. A final percentage haircut (DEFAULT_USDE_SUPPLY_PERCENTAGE_BPS)
    ///         is applied for additional safety margin.
    /// @param usdeAmountOut  Quoted USDe output from KyberSwap (18dp)
    /// @param usdtAmountIn   USDT amount being swapped (6dp)
    /// @param slippageBps    Slippage tolerance in basis points
    /// @return Conservative USDe supply amount (18dp)
    function _getConservativeUsdeSupplyAmount(
        uint256 usdeAmountOut,
        uint256 usdtAmountIn,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        uint256 quoteBased = FullMath.mulDiv(usdeAmountOut, 10000 - slippageBps, 10000);

        uint256 inputBased = FullMath.mulDiv(usdtAmountIn, 1e18, 1e6);
        inputBased = FullMath.mulDiv(inputBased, 10000 - slippageBps, 10000);

        uint256 conservativeAmount = inputBased < quoteBased ? inputBased : quoteBased;
        return FullMath.mulDiv(conservativeAmount, DEFAULT_USDE_SUPPLY_PERCENTAGE_BPS, 10000);
    }

    /// @notice Compute conservative swap #1 minimum output used for deterministic downstream sizing
    /// @dev    Returns quote output after slippage buffer, in USDe units (18dp).
    /// @param usdeAmountOut      Quoted USDe output from KyberSwap (18dp)
    /// @param slippageBps        Slippage tolerance in basis points
    /// @return Conservative minimum USDe output from swap #1 (18dp)
    function _getPlannedUsdeAmountOutMin(
        uint256 usdeAmountOut,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(usdeAmountOut, 10000 - slippageBps, 10000);
    }

    function _logLoopProjectedImbalance(
        bool imbalanceBeforeSusdeOverweight,
        uint256 imbalanceBeforeAbsUsde,
        bool imbalancePostSusdeSupplyOverweight,
        uint256 imbalancePostSusdeSupplyAbsUsde,
        uint256 conservativeUsdeSupplyAmount,
        uint256 usdeSupplyCapTarget,
        uint256 usdeSupplyAmount,
        uint256 usdeSweepToSusdeAmount
    ) internal view {
        console2.log(
            "[Position] Pre-loop collateral gap to target (abs USDe):",
            _toDecimalString(imbalanceBeforeAbsUsde, 18)
        );
        console2.log(
            "[Position] Pre-loop collateral gap side:",
            imbalanceBeforeSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        console2.log("[Position] Target sUSDe share (bps):", _loopTargetSusdeShareBps);
        console2.log(
            "[Position] Post-sUSDe collateral gap to target (abs USDe):",
            _toDecimalString(imbalancePostSusdeSupplyAbsUsde, 18)
        );
        console2.log(
            "[Position] Post-sUSDe collateral gap side:",
            imbalancePostSusdeSupplyOverweight ? "sUSDe above target" : "sUSDe below target"
        );
        console2.log(
            "[Iteration] Conservative USDe from swap #1:",
            _toDecimalString(conservativeUsdeSupplyAmount, 18)
        );
        console2.log(
            "[Iteration] USDe cap target for target-share supply:",
            _toDecimalString(usdeSupplyCapTarget, 18)
        );
        console2.log(
            "[Iteration] Chosen USDe supply to Aave:",
            _toDecimalString(usdeSupplyAmount, 18)
        );
        console2.log(
            "[Iteration] Leftover USDe swept into wallet sUSDe:",
            _toDecimalString(usdeSweepToSusdeAmount, 18)
        );
        console2.log(
            "[Position] Projected final collateral gap to target (abs USDe):",
            _toDecimalString(_loopProjectedImbalanceAbsUsde, 18)
        );
        console2.log(
            "[Position] Projected final collateral gap side:",
            _loopProjectedImbalanceSusdeOverweight ? "sUSDe above target" : "sUSDe below target"
        );
    }

    function _getCollateralTargetGapFromValues(
        uint256 susdeCollateralValueUsde,
        uint256 usdeCollateralValueUsde,
        uint256 targetSusdeShareBps
    ) internal pure returns (bool susdeAboveTarget, uint256 absGapUsde) {
        if (targetSusdeShareBps == 0 || targetSusdeShareBps >= 10_000) {
            revert("targetSusdeShareBps out of range");
        }

        uint256 desiredTotalCollateralUsde = FullMath.mulDivUp(
            susdeCollateralValueUsde,
            10_000,
            targetSusdeShareBps
        );
        uint256 currentTotalCollateralUsde = susdeCollateralValueUsde + usdeCollateralValueUsde;

        if (desiredTotalCollateralUsde > currentTotalCollateralUsde) {
            susdeAboveTarget = true;
            absGapUsde = desiredTotalCollateralUsde - currentTotalCollateralUsde;
            return (susdeAboveTarget, absGapUsde);
        }

        uint256 targetSusdeValueUsde = FullMath.mulDivUp(
            uint256(targetSusdeShareBps),
            usdeCollateralValueUsde,
            10_000 - targetSusdeShareBps
        );
        if (targetSusdeValueUsde > susdeCollateralValueUsde) {
            susdeAboveTarget = false;
            absGapUsde = targetSusdeValueUsde - susdeCollateralValueUsde;
        }
    }

    function _applyCollateralImbalanceDelta(
        bool beforeSusdeOverweight,
        uint256 beforeAbsUsde,
        uint256 susdeAddedUsde,
        uint256 usdeAddedUsde
    ) internal pure returns (bool afterSusdeOverweight, uint256 afterAbsUsde) {
        if (beforeSusdeOverweight) {
            uint256 susdeSide = beforeAbsUsde + susdeAddedUsde;
            if (susdeSide >= usdeAddedUsde) {
                return (true, susdeSide - usdeAddedUsde);
            }
            return (false, usdeAddedUsde - susdeSide);
        }

        uint256 usdeSide = beforeAbsUsde + usdeAddedUsde;
        if (susdeAddedUsde >= usdeSide) {
            return (true, susdeAddedUsde - usdeSide);
        }
        return (false, usdeSide - susdeAddedUsde);
    }

    function _getAaveCollateralValuesUsde(
        address account
    ) internal view returns (uint256 susdeCollateralValueUsde, uint256 usdeCollateralValueUsde) {
        (uint256 usdeATokenBalance, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_usde),
            account
        );
        (uint256 susdeATokenBalance, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_susde),
            account
        );

        usdeCollateralValueUsde = usdeATokenBalance;
        susdeCollateralValueUsde = _susdeToUsdeValue(susdeATokenBalance);
    }

    function _getAaveCollateralImbalanceUsde(
        address account
    )
        internal
        view
        returns (
            bool susdeOverweight,
            uint256 absDeltaUsde,
            uint256 susdeCollateralValueUsde,
            uint256 usdeCollateralValueUsde
        )
    {
        (susdeCollateralValueUsde, usdeCollateralValueUsde) = _getAaveCollateralValuesUsde(account);

        if (susdeCollateralValueUsde >= usdeCollateralValueUsde) {
            susdeOverweight = true;
            absDeltaUsde = susdeCollateralValueUsde - usdeCollateralValueUsde;
        } else {
            susdeOverweight = false;
            absDeltaUsde = usdeCollateralValueUsde - susdeCollateralValueUsde;
        }
    }

    function _getAaveCollateralTargetGapUsde(
        address account,
        uint256 targetSusdeShareBps
    )
        internal
        view
        returns (
            bool susdeAboveTarget,
            uint256 absGapUsde,
            uint256 susdeCollateralValueUsde,
            uint256 usdeCollateralValueUsde
        )
    {
        if (targetSusdeShareBps == 0 || targetSusdeShareBps >= 10_000) {
            revert("targetSusdeShareBps out of range");
        }

        (susdeCollateralValueUsde, usdeCollateralValueUsde) = _getAaveCollateralValuesUsde(account);

        (susdeAboveTarget, absGapUsde) = _getCollateralTargetGapFromValues(
            susdeCollateralValueUsde,
            usdeCollateralValueUsde,
            targetSusdeShareBps
        );
    }

    function _getAaveCollateralImbalanceSideAndAbs(
        address account
    ) internal view returns (bool susdeOverweight, uint256 absDeltaUsde) {
        (susdeOverweight, absDeltaUsde, , ) = _getAaveCollateralImbalanceUsde(account);
    }

    function _ratioBps(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        return FullMath.mulDiv(numerator, 10000, denominator);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _getCollateralImbalanceDriftAbsUsde(
        bool sideABefore,
        uint256 absBefore,
        bool sideAAfter,
        uint256 absAfter
    ) internal pure returns (uint256) {
        if (sideABefore == sideAAfter) {
            return absBefore >= absAfter ? absBefore - absAfter : absAfter - absBefore;
        }

        return absBefore + absAfter;
    }

    function _usdeToBaseValue(uint256 usdeAmount) internal pure returns (uint256) {
        return FullMath.mulDiv(usdeAmount, BASE_CURRENCY_SCALE, 1e18);
    }

    function _baseToUsdeAmount(uint256 baseAmount) internal pure returns (uint256) {
        return FullMath.mulDiv(baseAmount, 1e18, BASE_CURRENCY_SCALE);
    }

    function _susdeToBaseValue(uint256 susdeAmount) internal view returns (uint256) {
        return FullMath.mulDiv(_susdeToUsdeValue(susdeAmount), BASE_CURRENCY_SCALE, 1e18);
    }

    function _baseToSusdeAmount(uint256 baseAmount) internal view returns (uint256) {
        uint256 usdeAmount = _baseToUsdeAmount(baseAmount);
        uint256 oneSusdeValue = _susdeExchangeRate();
        if (oneSusdeValue == 0) revert("sUSDe exchange rate is zero");
        return FullMath.mulDiv(usdeAmount, 1e18, oneSusdeValue);
    }

    function _usdeToSusdeShares(uint256 usdeAmount) internal view returns (uint256) {
        try IERC4626(address(_susde)).convertToShares(usdeAmount) returns (uint256 shares) {
            return shares;
        } catch {
            revert("sUSDe convertToShares failed");
        }
    }

    function _usdeToSusdeSharesCached(
        string memory cacheKeyPrefix,
        uint256 usdeAmount
    ) internal returns (uint256 shares) {
        if (_isCacheReplay()) {
            uint256 cachedInput = _cacheReadUint(string.concat(cacheKeyPrefix, ".input"));
            if (cachedInput != usdeAmount) {
                _revertCacheFailure(
                    string.concat("4626 convertToShares input mismatch ", cacheKeyPrefix)
                );
            }
            return _cacheReadUint(string.concat(cacheKeyPrefix, ".output"));
        }

        shares = _usdeToSusdeShares(usdeAmount);
        _cacheSetUint(string.concat(cacheKeyPrefix, ".input"), usdeAmount);
        _cacheSetUint(string.concat(cacheKeyPrefix, ".output"), shares);
    }

    function _maxCollateralReductionForMinHealthFactor(
        uint256 collateralBase,
        uint256 debtBase,
        uint256 liquidationThresholdBps,
        uint256 minHealthFactor
    ) internal pure returns (uint256) {
        if (debtBase == 0 || collateralBase == 0 || liquidationThresholdBps == 0) {
            return collateralBase;
        }

        uint256 requiredCollateralBase = FullMath.mulDivUp(
            minHealthFactor,
            debtBase * 10000,
            uint256(liquidationThresholdBps) * 1e18
        );

        if (requiredCollateralBase >= collateralBase) return 0;
        return collateralBase - requiredCollateralBase;
    }

    function _debtBaseAfterRepay(
        uint256 debtBase,
        uint256 usdtDebt,
        uint256 usdtRepay
    ) internal pure returns (uint256) {
        if (debtBase == 0 || usdtDebt == 0) return 0;
        if (usdtRepay >= usdtDebt) return 0;

        uint256 usdtDebtRemaining = usdtDebt - usdtRepay;
        return FullMath.mulDivUp(debtBase, usdtDebtRemaining, usdtDebt);
    }

    function _toDecimalString(
        uint256 value,
        uint256 decimals
    ) internal pure returns (string memory) {
        if (value == 0) return "0";
        string memory raw = vm.toString(value);
        if (decimals == 0) return raw;
        bytes memory rawBytes = bytes(raw);
        bytes memory result;
        if (rawBytes.length <= decimals) {
            bytes memory lead = new bytes(2 + decimals - rawBytes.length);
            lead[0] = "0";
            lead[1] = ".";
            for (uint256 i = 0; i < decimals - rawBytes.length; i++) {
                lead[i + 2] = "0";
            }
            result = bytes(string.concat(string(lead), raw));
        } else {
            uint256 intPartLen = rawBytes.length - decimals;
            result = new bytes(rawBytes.length + 1);
            uint256 j;
            for (uint256 i = 0; i < rawBytes.length; i++) {
                if (i == intPartLen) {
                    result[j] = ".";
                    j++;
                }
                result[j] = rawBytes[i];
                j++;
            }
        }
        uint256 end = result.length;
        while (end > 0 && result[end - 1] == "0") {
            end--;
        }
        if (end > 0 && result[end - 1] == ".") {
            end--;
        }
        bytes memory trimmed = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            trimmed[i] = result[i];
        }
        return string(trimmed);
    }

    function _usdtToUsd18(uint256 usdtAmount) internal pure returns (uint256) {
        return FullMath.mulDiv(usdtAmount, 1e18, 1e6);
    }

    function _susdeToUsdeValue(uint256 susdeAmount) internal view returns (uint256) {
        try IERC4626(address(_susde)).convertToAssets(susdeAmount) returns (uint256 assets) {
            if (susdeAmount > 0 && assets == 0) revert("sUSDe convertToAssets returned zero");
            return assets;
        } catch {
            revert("sUSDe convertToAssets failed");
        }
    }

    function _susdeToUsdeValueCached(
        string memory cacheKeyPrefix,
        uint256 susdeAmount
    ) internal returns (uint256 assets) {
        if (_isCacheReplay()) {
            uint256 cachedInput = _cacheReadUint(string.concat(cacheKeyPrefix, ".input"));
            if (cachedInput != susdeAmount) {
                _revertCacheFailure(
                    string.concat("4626 convertToAssets input mismatch ", cacheKeyPrefix)
                );
            }
            return _cacheReadUint(string.concat(cacheKeyPrefix, ".output"));
        }

        assets = _susdeToUsdeValue(susdeAmount);
        _cacheSetUint(string.concat(cacheKeyPrefix, ".input"), susdeAmount);
        _cacheSetUint(string.concat(cacheKeyPrefix, ".output"), assets);
    }

    function _susdeExchangeRate() internal view returns (uint256) {
        return _susdeToUsdeValue(1e18);
    }

    function _logAndValidateValueRatio(
        string memory stepLabel,
        uint256 valueOutUsd,
        uint256 inputNotionalUsd,
        uint256 minRatioBps
    ) internal pure {
        uint256 ratioBps = _ratioBps(valueOutUsd, inputNotionalUsd);
        console2.log(stepLabel);
        console2.log("Value/input notional ratio (bps):", ratioBps);
        console2.log("Minimum accepted value ratio (bps):", minRatioBps);

        if (ratioBps < minRatioBps) {
            revert(string.concat(stepLabel, " value ratio below minimum"));
        }
    }

    // ============ KyberSwap API ============

    function _getKyberSwapCalldata(
        string memory stepLabel,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (address router, bytes memory swapCalldata, uint256 amountOut) {
        console2.log("amountIn", amountIn);
        if (_isCacheReplay()) {
            console2.log("[Iteration] Kyber source: cache replay");
            if (bytes(_kyberExcludedSources).length > 0) {
                console2.log("[Iteration] Kyber excluded sources (arg):", _kyberExcludedSources);
            } else {
                console2.log("[Iteration] Kyber excluded sources (arg): (none)");
            }
            console2.log("[Iteration] Route source breakdown: unavailable in cache replay");
            (router, swapCalldata, amountOut) = _cacheReadKyberSwap(stepLabel);
            _logKyberAmountOut(tokenOut, amountOut);
            console2.log("[Iteration] Router:", router);
            return (router, swapCalldata, amountOut);
        }

        console2.log("[Iteration] Kyber source: live API");

        (router, swapCalldata, amountOut) = _getKyberSwapCalldataLive(
            stepLabel,
            tokenIn,
            tokenOut,
            amountIn,
            slippageBps
        );
        _cacheWriteKyberSwap(stepLabel, router, swapCalldata, amountOut);
    }

    function _getKyberSwapCalldataLive(
        string memory stepLabel,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (address router, bytes memory swapCalldata, uint256 amountOut) {
        string memory getUrl = string.concat(
            KYBERSWAP_BASE_URL,
            "/api/v1/routes?tokenIn=",
            vm.toString(tokenIn),
            "&tokenOut=",
            vm.toString(tokenOut),
            "&amountIn=",
            vm.toString(amountIn)
        );
        if (bytes(_kyberExcludedSources).length > 0) {
            getUrl = string.concat(getUrl, "&excludedSources=", _kyberExcludedSources);
        }

        string[] memory headers = new string[](2);
        headers[0] = "Accept: application/json";
        headers[1] = string.concat("X-Client-Id: ", KYBERSWAP_CLIENT_ID);

        console2.log("\n--- %s: Query Kyber route ---", stepLabel);

        (uint256 getStatus, bytes memory getResponse) = getUrl.get(headers);
        if (getStatus >= 400) revert(string.concat("KyberSwap GET failed: ", string(getResponse)));

        string memory getResponseStr = string(getResponse);
        string memory routeSummaryJson = _extractJsonObjectForKey(getResponseStr, '"routeSummary"');
        _logKyberRouteSourceDetails(routeSummaryJson);
        amountOut = vm.parseUint(getResponseStr.readString(".data.routeSummary.amountOut"));
        router = vm.parseJsonAddress(getResponseStr, ".data.routerAddress");
        if (router == address(0)) router = KYBERSWAP_ROUTER_FALLBACK;

        _logKyberAmountOut(tokenOut, amountOut);
        console2.log("[Iteration] Router:", router);

        string memory postBody = string.concat(
            '{"routeSummary":',
            routeSummaryJson,
            ',"sender":"',
            vm.toString(_owner),
            '","recipient":"',
            vm.toString(_owner),
            '","slippageTolerance":',
            vm.toString(slippageBps),
            "}"
        );

        (uint256 postStatus, bytes memory postResponse) = string
            .concat(KYBERSWAP_BASE_URL, "/api/v1/route/build")
            .post(headers, postBody);
        if (postStatus >= 400) {
            revert(string.concat("KyberSwap POST failed: ", string(postResponse)));
        }

        swapCalldata = vm.parseBytes(string(postResponse).readString(".data.data"));
    }

    function _cacheReadKyberSwap(
        string memory stepLabel
    ) internal view returns (address router, bytes memory swapCalldata, uint256 amountOut) {
        string memory cacheKeyPrefix = _kyberCacheKeyPrefix(stepLabel);
        router = _cacheReadAddress(string.concat(cacheKeyPrefix, ".router"));
        swapCalldata = _cacheReadBytes(string.concat(cacheKeyPrefix, ".swapCalldata"));
        amountOut = _cacheReadUint(string.concat(cacheKeyPrefix, ".amountOut"));
    }

    function _cacheWriteKyberSwap(
        string memory stepLabel,
        address router,
        bytes memory swapCalldata,
        uint256 amountOut
    ) internal {
        string memory cacheKeyPrefix = _kyberCacheKeyPrefix(stepLabel);
        _cacheSetAddress(string.concat(cacheKeyPrefix, ".router"), router);
        _cacheSetBytes(string.concat(cacheKeyPrefix, ".swapCalldata"), swapCalldata);
        _cacheSetUint(string.concat(cacheKeyPrefix, ".amountOut"), amountOut);
    }

    function _kyberCacheKeyPrefix(string memory stepLabel) internal pure returns (string memory) {
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 stepHash = keccak256(bytes(stepLabel));
        if (stepHash == keccak256(bytes("Swap #1 (USDT -> USDe)"))) {
            return CACHE_KEY_LOOP_SWAP1_PREFIX;
        }
        if (stepHash == keccak256(bytes("Swap #2 (USDT -> sUSDe)"))) {
            return CACHE_KEY_LOOP_SWAP2_PREFIX;
        }
        if (stepHash == keccak256(bytes("Step 1 swap (wallet sUSDe -> USDT)"))) {
            return CACHE_KEY_UNWIND_SWAP1_PREFIX;
        }
        if (stepHash == keccak256(bytes("Step 3 swap (USDe -> USDT)"))) {
            return CACHE_KEY_UNWIND_SWAP3_PREFIX;
        }
        if (stepHash == keccak256(bytes("Step 5 swap (sUSDe -> USDT)"))) {
            return CACHE_KEY_UNWIND_SWAP5_PREFIX;
        }
        if (stepHash == keccak256(bytes("Rebalance swap (sUSDe -> USDe)"))) {
            return CACHE_KEY_REBALANCE_SWAP1_PREFIX;
        }

        revert("Unknown Kyber cache step");
    }

    function _logKyberAmountOut(address tokenOut, uint256 amountOut) internal view {
        if (tokenOut == address(_usdt)) {
            console2.log("Route obtained, amountOut:", _toDecimalString(amountOut, 6));
        } else {
            console2.log("Route obtained, amountOut:", _toDecimalString(amountOut, 18));
        }
    }

    function _extractJsonObjectForKey(
        string memory json,
        string memory key
    ) internal pure returns (string memory) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(key);

        uint256 keyIndex = _indexOf(jsonBytes, keyBytes);
        if (keyIndex == type(uint256).max) revert("JSON key not found");

        uint256 i = keyIndex + keyBytes.length;
        while (i < jsonBytes.length) {
            bytes1 char_ = jsonBytes[i];
            if (
                char_ == 0x3a || // :
                char_ == 0x20 || // space
                char_ == 0x0a || // \n
                char_ == 0x0d || // \r
                char_ == 0x09 // \t
            ) {
                ++i;
                continue;
            }
            break;
        }

        if (i >= jsonBytes.length || jsonBytes[i] != 0x7b) revert("JSON object not found");

        uint256 start = i;
        uint256 depth = 0;
        bool inString = false;
        bool escaped = false;

        for (; i < jsonBytes.length; ++i) {
            bytes1 char_ = jsonBytes[i];

            if (inString) {
                if (escaped) {
                    escaped = false;
                } else if (char_ == 0x5c) {
                    escaped = true;
                } else if (char_ == 0x22) {
                    inString = false;
                }
                continue;
            }

            if (char_ == 0x22) {
                inString = true;
                continue;
            }

            if (char_ == 0x7b) {
                ++depth;
            } else if (char_ == 0x7d) {
                --depth;
                if (depth == 0) {
                    return _sliceToString(jsonBytes, start, i + 1);
                }
            }
        }

        revert("JSON object unterminated");
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || needle.length > haystack.length) return type(uint256).max;

        uint256 lastStart = haystack.length - needle.length;
        for (uint256 i = 0; i <= lastStart; ++i) {
            bool matches = true;
            for (uint256 j = 0; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return i;
        }

        return type(uint256).max;
    }

    function _logKyberRouteSourceDetails(string memory routeSummaryJson) internal view {
        if (bytes(_kyberExcludedSources).length > 0) {
            console2.log("[Iteration] Kyber excluded sources (arg):", _kyberExcludedSources);
        } else {
            console2.log("[Iteration] Kyber excluded sources (arg): (none)");
        }
        console2.log("[Iteration] Kyber route summary JSON:", routeSummaryJson);
    }

    function _sliceToString(
        bytes memory data,
        uint256 start,
        uint256 end
    ) internal pure returns (string memory) {
        if (end <= start || end > data.length) revert("Invalid slice");

        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; ++i) {
            out[i] = data[start + i];
        }

        return string(out);
    }

    function _getLoopMinSwapUsdtUsdeValueRatioBps() internal view returns (uint256) {
        return
            _readOptionalUint256(
                "executeLoop",
                "minSwapUsdtUsdeValueRatioBps",
                DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS
            );
    }

    function _getLoopMinSwapUsdtSusdeValueRatioBps() internal view returns (uint256) {
        return
            _readOptionalUint256(
                "executeLoop",
                "minSwapUsdtSusdeValueRatioBps",
                DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS
            );
    }

    function _getUnwindMinSwapUsdeUsdtValueRatioBps() internal view returns (uint256) {
        return
            _readOptionalUint256(
                "executeUnwindLoop",
                "minSwapUsdeUsdtValueRatioBps",
                DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS
            );
    }

    function _getUnwindMinSwapSusdeUsdtValueRatioBps() internal view returns (uint256) {
        return
            _readOptionalUint256(
                "executeUnwindLoop",
                "minSwapSusdeUsdtValueRatioBps",
                DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS
            );
    }

    // ============ Args Helpers ============

    function _readOptionalUint256(
        string memory functionName,
        string memory key,
        uint256 defaultValue
    ) internal view returns (uint256) {
        if (bytes(_argsFile).length == 0) return defaultValue;

        string memory path = string.concat(
            ".functions[?(@.name == '",
            functionName,
            "')].args.",
            key
        );
        try vm.parseJsonUint(_argsFile, path) returns (uint256 value) {
            return value;
        } catch {
            try vm.parseJsonString(_argsFile, path) returns (string memory valueString) {
                if (bytes(valueString).length == 0) return defaultValue;
                try vm.parseUint(valueString) returns (uint256 parsedValue) {
                    return parsedValue;
                } catch {
                    return defaultValue;
                }
            } catch {
                return defaultValue;
            }
        }
    }

    function _readOptionalString(
        string memory functionName,
        string memory key,
        string memory defaultValue
    ) internal view returns (string memory) {
        if (bytes(_argsFile).length == 0) return defaultValue;

        string memory path = string.concat(
            ".functions[?(@.name == '",
            functionName,
            "')].args.",
            key
        );
        try vm.parseJsonString(_argsFile, path) returns (string memory value) {
            if (bytes(value).length == 0) return defaultValue;
            return value;
        } catch {
            return defaultValue;
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
