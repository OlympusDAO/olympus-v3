// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
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
    uint256 internal _susdeSuppliedAmount;
    uint256 internal _usdeSuppliedAmount;
    uint256 internal _plannedUsdeToSusdeDepositAmount;
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

    struct UnwindConfig {
        uint256 slippageBps;
        uint256 minHealthFactor;
        uint256 minSwap1ValueRatioBps;
        uint256 minSwap2ValueRatioBps;
        uint256 maxSusdeSwapIn;
    }

    struct UnwindPlan {
        uint256 conservativeRepay1;
        uint256 conservativeRepay2;
        uint256 usdeWithdrawAmount1;
        uint256 susdeSwapAmount;
        uint256 usdeWithdrawAmountFinal;
        uint256 susdeWithdrawAmountFinal;
        uint256 debtAfterStep2;
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
        uint256 usdeWithdrawAmount1;
        uint256 conservativeRepay1;
        uint256 collateralAfterStep1;
        uint256 debtAfterStep1;
        uint256 usdtDebtAfterStep1;
        address routerUsdeToUsdt;
        bytes swapCalldataUsdeToUsdt;
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
    uint256 internal constant MAX_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%

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

    // Aave base currency decimals (USD = 8 decimals)
    uint256 internal constant BASE_CURRENCY_DECIMALS = 8;
    uint256 internal constant BASE_CURRENCY_SCALE = 10 ** BASE_CURRENCY_DECIMALS;

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

        _initialSusdeBalance = _susde.balanceOf(_owner);
        _captureInitialAccountSnapshot();

        uint256 susdeSupplyAmount = _readOptionalUint256("executeLoop", "susdeSupplyAmount", 0);
        uint256 borrowPercentage = _readOptionalUint256(
            "executeLoop",
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );

        if (borrowPercentage > MAX_BORROW_PERCENTAGE) revert("Borrow percentage exceeds max");
        uint256 slippageBps = _readOptionalUint256(
            "executeLoop",
            "slippageBps",
            DEFAULT_SLIPPAGE_BPS
        );
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        _skipHeartbeatValidation = SKIP_HEARTBEAT;

        if (susdeSupplyAmount == 0) susdeSupplyAmount = _initialSusdeBalance;
        if (susdeSupplyAmount == 0) revert("No sUSDe to supply");
        _susdeSuppliedAmount = susdeSupplyAmount;

        console2.log("=== Execute Loop Iteration: sUSDe -> USDT -> USDe -> sUSDe ===");
        console2.log("Owner:", _owner);
        console2.log("sUSDe supply amount (from wallet):", _toDecimalString(susdeSupplyAmount, 18));
        console2.log("Borrow percentage (bps):", borrowPercentage);
        console2.log("Slippage (bps):", slippageBps);

        uint256 totalExpectedBorrowsAfterSusdeSupply;
        uint256 usdtBorrowAmount1;

        {
            uint256 currentEMode = AAVE_POOL.getUserEMode(_owner);
            bool shouldSetEMode = (currentEMode != EMODE_CATEGORY);

            (
                ,
                ,
                uint256 availableBorrowsBase, // 8dp USD
                uint256 currentLiquidationThreshold, // bps
                ,
                uint256 healthFactor // 1e18 ray
            ) = AAVE_POOL.getUserAccountData(_owner);

            // Convert sUSDe amount (18dp) to its USDe value using live exchange rate (18dp)
            uint256 susdeSupplyValueUsde = _susdeToUsdeValue(susdeSupplyAmount);
            // Convert USDe value (18dp) to Aave base currency (8dp USD): value * 1e8 / 1e18
            uint256 supplyValueBase = FullMath.mulDiv(
                susdeSupplyValueUsde,
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

            console2.log("\n--- Step 1: Estimate Borrow #1 from sUSDe supply (this iteration) ---");
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
                _toDecimalString(susdeSupplyValueUsde, 18)
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
                console2.log("\n2. Set eMode category to", EMODE_CATEGORY);
                addToBatch(address(AAVE_POOL), _encodeSetUserEMode(EMODE_CATEGORY));
            }
        }

        (
            address routerUsdtToUsde,
            bytes memory swapCalldataUsdtToUsde,
            uint256 usdeAmountOut
        ) = _getKyberSwapCalldata(
                "Swap #1 (USDT -> USDe)",
                address(_usdt),
                address(_usde),
                usdtBorrowAmount1,
                slippageBps
            );
        if (usdeAmountOut == 0) revert("USDe quote amount is zero");

        console2.log("\n--- Step 2: Build swap #1 (USDT -> USDe) [this iteration] ---");
        console2.log(
            "[Iteration] Expected USDe out from quote:",
            _toDecimalString(usdeAmountOut, 18)
        );
        {
            uint256 minSwap1ValueRatioBps = _readOptionalUint256(
                "executeLoop",
                "minSwap1ValueRatioBps",
                _readOptionalUint256(
                    "executeLoop",
                    "minSwap1QuoteRatioBps",
                    DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS
                )
            );
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

        uint256 usdeSupplyAmount = _getConservativeUsdeSupplyAmount(
            usdeAmountOut,
            usdtBorrowAmount1,
            slippageBps
        );
        if (usdeSupplyAmount == 0) revert("USDe supply amount is zero");
        _usdeSuppliedAmount = usdeSupplyAmount;
        console2.log(
            "[Iteration] Conservative USDe supply haircut vs quote (bps):",
            _ratioBps(usdeSupplyAmount, usdeAmountOut)
        );

        _plannedUsdeToSusdeDepositAmount = _getPlannedUsdeToSusdeDepositAmount(
            usdeAmountOut,
            usdeSupplyAmount,
            slippageBps
        );
        console2.log(
            "[Iteration] Planned USDe -> sUSDe deposit amount:",
            _toDecimalString(_plannedUsdeToSusdeDepositAmount, 18)
        );

        uint256 usdtBorrowAmount2;
        {
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
            if (usdtBorrowAmount2 == 0) revert("USDT borrow amount 2 is zero");

            console2.log("\n--- Step 3: Estimate Borrow #2 after USDe supply (this iteration) ---");
            console2.log(
                "[Iteration] Conservative USDe supply amount:",
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
            console2.log(
                "[Iteration] Borrow #2 amount USDT:",
                _toDecimalString(usdtBorrowAmount2, 6)
            );
            console2.log(
                "[Iteration] Borrow #2 utilization vs projected capacity (bps):",
                _ratioBps(usdtBorrowAmount2 * 1e2, totalExpectedBorrowsAfterUsdeSupply)
            );
        }

        (
            address routerUsdtToSusde,
            bytes memory swapCalldataUsdtToSusde,
            uint256 susdeAmountOut
        ) = _getKyberSwapCalldata(
                "Swap #2 (USDT -> sUSDe)",
                address(_usdt),
                address(_susde),
                usdtBorrowAmount2,
                slippageBps
            );

        console2.log("\n--- Step 4: Build swap #2 (USDT -> sUSDe) [this iteration] ---");
        console2.log(
            "[Iteration] Expected sUSDe out from quote:",
            _toDecimalString(susdeAmountOut, 18)
        );
        {
            uint256 minSwap2ValueRatioBps = _readOptionalUint256(
                "executeLoop",
                "minSwap2ValueRatioBps",
                _readOptionalUint256(
                    "executeLoop",
                    "minSwap2QuoteRatioBps",
                    DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS
                )
            );
            if (minSwap2ValueRatioBps == 0 || minSwap2ValueRatioBps > 10000) {
                revert("Swap #2 min value ratio invalid");
            }
            uint256 swap2ValueOutUsd = _susdeToUsdeValue(susdeAmountOut);
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
        }
        _expectedMinSusdeOut = FullMath.mulDiv(susdeAmountOut, 10000 - slippageBps, 10000);
        console2.log(
            "[Iteration] Expected min sUSDe out after slippage buffer:",
            _toDecimalString(_expectedMinSusdeOut, 18)
        );
        console2.log(
            "[Iteration] Min-out buffer vs quote (bps):",
            _ratioBps(_expectedMinSusdeOut, susdeAmountOut)
        );

        _addLoopActionsToBatch(
            susdeSupplyAmount,
            usdtBorrowAmount1,
            usdeSupplyAmount,
            usdtBorrowAmount2,
            _plannedUsdeToSusdeDepositAmount,
            routerUsdtToUsde,
            swapCalldataUsdtToUsde,
            routerUsdtToSusde,
            swapCalldataUsdtToSusde
        );

        console2.log("\n=== Batch prepared ===");
        console2.log("Total batch operations:", _batchTargets.length);

        _setPostBatchValidateSelector(this._validateExecuteLoopPostBatch.selector);

        proposeBatch();
    }

    /// @notice Execute one max-safe unwind iteration for the sUSDe/USDe Aave loop position
    /// @dev    Unwind order is repay-first for each collateral leg:
    ///         1) withdraw USDe -> swap USDe->USDT -> repay USDT
    ///         2) withdraw sUSDe (swap leg) -> swap sUSDe->USDT -> repay USDT
    ///         3) withdraw remaining safe collateral and convert final USDe to sUSDe
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

        _initialSusdeBalance = _susde.balanceOf(_owner);
        _captureInitialAccountSnapshot();

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

        uint256 minSwap1ValueRatioBps = _readOptionalUint256(
            "executeUnwindLoop",
            "minSwap1ValueRatioBps",
            DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS
        );
        if (minSwap1ValueRatioBps == 0 || minSwap1ValueRatioBps > 10000) {
            revert("Swap #1 min value ratio invalid");
        }

        uint256 minSwap2ValueRatioBps = _readOptionalUint256(
            "executeUnwindLoop",
            "minSwap2ValueRatioBps",
            DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS
        );
        if (minSwap2ValueRatioBps == 0 || minSwap2ValueRatioBps > 10000) {
            revert("Swap #2 min value ratio invalid");
        }

        uint256 maxSusdeSwapIn = _readOptionalUint256(
            "executeUnwindLoop",
            "maxSusdeSwapIn",
            DEFAULT_MAX_SUSDE_SWAP_IN
        );

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
            plan.conservativeRepay1 == 0 &&
            plan.conservativeRepay2 == 0 &&
            plan.susdeWithdrawAmountFinal == 0
        ) {
            revert("No safe unwind action available");
        }

        _expectedMinHealthFactor = minHealthFactor;
        _expectedMaxDebtBase = plan.debtAfterStep2;
        _expectedMinSusdeOut = _initialSusdeBalance + plan.susdeWithdrawAmountFinal;

        if (plan.usdeWithdrawAmount1 > 0) {
            addToBatch(
                address(AAVE_POOL),
                _encodeWithdraw(address(_usde), plan.usdeWithdrawAmount1, _owner)
            );
            addToBatch(address(_usde), _encodeApprove(plan.routerUsdeToUsdt, 0));
            addToBatch(
                address(_usde),
                _encodeApprove(plan.routerUsdeToUsdt, plan.usdeWithdrawAmount1)
            );
            addToBatch(plan.routerUsdeToUsdt, plan.swapCalldataUsdeToUsdt);
            addToBatch(address(_usdt), _encodeApprove(address(AAVE_POOL), 0));
            addToBatch(address(_usdt), _encodeApprove(address(AAVE_POOL), type(uint256).max));
            addToBatch(address(AAVE_POOL), _encodeRepay(address(_usdt), type(uint256).max, _owner));
        }

        if (plan.susdeSwapAmount > 0) {
            addToBatch(
                address(AAVE_POOL),
                _encodeWithdraw(address(_susde), plan.susdeSwapAmount, _owner)
            );
            addToBatch(address(_susde), _encodeApprove(plan.routerSusdeToUsdt, 0));
            addToBatch(
                address(_susde),
                _encodeApprove(plan.routerSusdeToUsdt, plan.susdeSwapAmount)
            );
            addToBatch(plan.routerSusdeToUsdt, plan.swapCalldataSusdeToUsdt);
            addToBatch(address(_usdt), _encodeApprove(address(AAVE_POOL), 0));
            addToBatch(address(_usdt), _encodeApprove(address(AAVE_POOL), type(uint256).max));
            addToBatch(address(AAVE_POOL), _encodeRepay(address(_usdt), type(uint256).max, _owner));
        }

        if (plan.usdeWithdrawAmountFinal > 0) {
            addToBatch(
                address(AAVE_POOL),
                _encodeWithdraw(address(_usde), plan.usdeWithdrawAmountFinal, _owner)
            );
            addToBatch(
                address(_usde),
                _encodeApprove(address(_susde), plan.usdeWithdrawAmountFinal)
            );
            addToBatch(address(_susde), _encodeDeposit4626(plan.usdeWithdrawAmountFinal, _owner));
        }

        if (plan.susdeWithdrawAmountFinal > 0) {
            addToBatch(
                address(AAVE_POOL),
                _encodeWithdraw(address(_susde), plan.susdeWithdrawAmountFinal, _owner)
            );
        }

        addToBatch(address(_usdt), _encodeApprove(address(AAVE_POOL), 0));
        if (plan.routerUsdeToUsdt != address(0)) {
            addToBatch(address(_usde), _encodeApprove(plan.routerUsdeToUsdt, 0));
        }
        if (plan.routerSusdeToUsdt != address(0)) {
            addToBatch(address(_susde), _encodeApprove(plan.routerSusdeToUsdt, 0));
        }
        addToBatch(address(_usde), _encodeApprove(address(_susde), 0));

        _setPostBatchValidateSelector(this._validateExecuteUnwindLoopPostBatch.selector);

        proposeBatch();
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

        plan.usdeWithdrawAmount1 = step1.usdeWithdrawAmount1;
        plan.conservativeRepay1 = step1.conservativeRepay1;
        plan.routerUsdeToUsdt = step1.routerUsdeToUsdt;
        plan.swapCalldataUsdeToUsdt = step1.swapCalldataUsdeToUsdt;

        uint256 susdeSwapAmount;
        address routerSusdeToUsdt;
        bytes memory swapCalldataSusdeToUsdt;
        uint256 conservativeRepay2;
        uint256 debtAfterStep2;
        uint256 usdeWithdrawAmountFinal;
        uint256 susdeWithdrawAmountFinal;
        UnwindStep2Inputs memory step2Inputs;
        step2Inputs.collateralAfterStep1 = step1.collateralAfterStep1;
        step2Inputs.debtAfterStep1 = step1.debtAfterStep1;
        step2Inputs.usdtDebtAfterStep1 = step1.usdtDebtAfterStep1;
        step2Inputs.currentLiquidationThreshold = step1.currentLiquidationThreshold;
        step2Inputs.usdeATokenBalance = step1.usdeATokenBalance;
        step2Inputs.susdeATokenBalance = step1.susdeATokenBalance;
        step2Inputs.usdeWithdrawAmount1 = step1.usdeWithdrawAmount1;
        (
            susdeSwapAmount,
            routerSusdeToUsdt,
            swapCalldataSusdeToUsdt,
            conservativeRepay2,
            debtAfterStep2,
            usdeWithdrawAmountFinal,
            susdeWithdrawAmountFinal
        ) = _computeUnwindStep2(step2Inputs);

        plan.susdeSwapAmount = susdeSwapAmount;
        plan.routerSusdeToUsdt = routerSusdeToUsdt;
        plan.swapCalldataSusdeToUsdt = swapCalldataSusdeToUsdt;
        plan.conservativeRepay2 = conservativeRepay2;
        plan.debtAfterStep2 = debtAfterStep2;
        plan.usdeWithdrawAmountFinal = usdeWithdrawAmountFinal;
        plan.susdeWithdrawAmountFinal = susdeWithdrawAmountFinal;

        console2.log("\n--- Unwind plan (conservative) ---");
        console2.log(
            "[Iteration] Withdraw #1 USDe:",
            _toDecimalString(plan.usdeWithdrawAmount1, 18)
        );
        console2.log(
            "[Iteration] Conservative repay #1 USDT:",
            _toDecimalString(plan.conservativeRepay1, 6)
        );
        console2.log(
            "[Iteration] Swap #2 sUSDe input:",
            _toDecimalString(plan.susdeSwapAmount, 18)
        );
        console2.log(
            "[Iteration] Conservative repay #2 USDT:",
            _toDecimalString(plan.conservativeRepay2, 6)
        );
        console2.log(
            "[Iteration] Final USDe withdraw:",
            _toDecimalString(plan.usdeWithdrawAmountFinal, 18)
        );
        console2.log(
            "[Iteration] Final sUSDe withdraw:",
            _toDecimalString(plan.susdeWithdrawAmountFinal, 18)
        );
    }

    function _computeUnwindStep1() internal returns (UnwindStep1Outputs memory step1) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            uint256 currentLiquidationThreshold,
            ,
            uint256 healthFactor
        ) = AAVE_POOL.getUserAccountData(_owner);

        if (totalDebtBase == 0) revert("No debt to unwind");
        if (currentLiquidationThreshold == 0) revert("Liquidation threshold is zero");

        (step1.usdeATokenBalance, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_usde),
            _owner
        );
        (step1.susdeATokenBalance, , , , , , , , ) = AAVE_DATA_PROVIDER.getUserReserveData(
            address(_susde),
            _owner
        );
        (, uint256 usdtStableDebt, uint256 usdtVariableDebt, , , , , , ) = AAVE_DATA_PROVIDER
            .getUserReserveData(address(_usdt), _owner);

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

        uint256 collateralReductionBase = _maxCollateralReductionForMinHealthFactor(
            totalCollateralBase,
            totalDebtBase,
            currentLiquidationThreshold,
            _unwindMinHealthFactor
        );
        if (collateralReductionBase == 0) revert("No safe collateral headroom");

        uint256 usdeWithdrawBase = _min(
            collateralReductionBase,
            _usdeToBaseValue(step1.usdeATokenBalance)
        );
        uint256 debtNotionalUsde = FullMath.mulDiv(usdtVariableDebt, 1e18, 1e6);
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
        ) = _planUsdeRepayLeg(step1.usdeWithdrawAmount1, usdtVariableDebt);

        step1.collateralAfterStep1 = totalCollateralBase - usdeWithdrawBase;
        step1.debtAfterStep1 = totalDebtBase - (step1.conservativeRepay1 * 1e2);
        step1.usdtDebtAfterStep1 = usdtVariableDebt - step1.conservativeRepay1;
    }

    function _planUsdeRepayLeg(
        uint256 usdeWithdrawAmount,
        uint256 maxRepayAmount
    ) internal returns (address router, bytes memory swapCalldata, uint256 conservativeRepay) {
        if (usdeWithdrawAmount == 0) return (address(0), bytes(""), 0);

        uint256 usdtAmountOut;
        (router, swapCalldata, usdtAmountOut) = _getKyberSwapCalldata(
            "Swap #1 (USDe -> USDT)",
            address(_usde),
            address(_usdt),
            usdeWithdrawAmount,
            _unwindSlippageBps
        );

        _logAndValidateValueRatio(
            "Swap #1 (USDe -> USDT)",
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
            "Swap #2 (sUSDe -> USDT)",
            address(_susde),
            address(_usdt),
            susdeSwapAmount,
            _unwindSlippageBps
        );

        uint256 susdeInputNotionalUsd = _susdeToUsdeValue(susdeSwapAmount);
        _logAndValidateValueRatio(
            "Swap #2 (sUSDe -> USDT)",
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
            uint256 debtNotionalSusde = _usdeToSusdeShares(
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
        ) = _planSusdeRepayLeg(susdeSwapAmount, inputs.usdtDebtAfterStep1);

        uint256 collateralAfterStep2 = inputs.collateralAfterStep1 - susdeSwapValueBase;
        debtAfterStep2 = inputs.debtAfterStep1 - (conservativeRepay2 * 1e2);

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
            revert("Debt reduction below conservative expectation");
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
        _logAaveBalanceSheetReport();
        console2.log("executeUnwindLoop post-batch validation passed");
    }

    function _addLoopActionsToBatch(
        uint256 susdeSupplyAmount,
        uint256 usdtBorrowAmount1,
        uint256 usdeSupplyAmount,
        uint256 usdtBorrowAmount2,
        uint256 usdeToSusdeDepositAmount,
        address routerUsdtToUsde,
        bytes memory swapCalldataUsdtToUsde,
        address routerUsdtToSusde,
        bytes memory swapCalldataUsdtToSusde
    ) internal {
        // 3. Approve & supply sUSDe, set collateral
        console2.log("\n3. Approve and supply sUSDe to Aave");
        addToBatch(address(_susde), _encodeApprove(address(AAVE_POOL), susdeSupplyAmount));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_susde), susdeSupplyAmount, _owner));
        addToBatch(address(AAVE_POOL), _encodeSetUserUseReserveAsCollateral(address(_susde), true));

        // 4. Borrow USDT amount 1
        console2.log("\n4. Borrow USDT amount 1 from Aave");
        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount1, _owner));

        // Debug: inspect borrowed USDT balance before first swap
        addToBatch(address(_usdt), _encodeBalanceOf(_owner));

        // USDT uses a non-standard approve that requires resetting to 0 before setting a new value.
        // This pattern is applied before each swap below (steps 5 and 8).
        // Debug balanceOf calls are included to trace intermediate balances during simulation.

        // 5. Swap USDT -> USDe
        console2.log("\n5. Swap USDT amount 1 to USDe");
        addToBatch(address(_usdt), _encodeApprove(routerUsdtToUsde, 0));
        addToBatch(address(_usdt), _encodeApprove(routerUsdtToUsde, usdtBorrowAmount1));
        addToBatch(routerUsdtToUsde, swapCalldataUsdtToUsde);

        // Debug: inspect realized USDe balance after swap, before supply
        addToBatch(address(_usde), _encodeBalanceOf(_owner));
        // Debug: inspect remaining USDT after first swap
        addToBatch(address(_usdt), _encodeBalanceOf(_owner));

        // 6. Approve & supply USDe, set collateral
        console2.log("\n6. Approve and supply USDe to Aave");
        addToBatch(address(_usde), _encodeApprove(address(AAVE_POOL), usdeSupplyAmount));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_usde), usdeSupplyAmount, _owner));
        addToBatch(address(AAVE_POOL), _encodeSetUserUseReserveAsCollateral(address(_usde), true));

        // 7. Borrow USDT amount 2
        console2.log("\n7. Borrow USDT amount 2 from Aave");
        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount2, _owner));

        // 8. Swap USDT -> sUSDe
        console2.log("\n8. Swap USDT amount 2 to sUSDe");
        addToBatch(address(_usdt), _encodeApprove(routerUsdtToSusde, 0));
        addToBatch(address(_usdt), _encodeApprove(routerUsdtToSusde, usdtBorrowAmount2));
        addToBatch(routerUsdtToSusde, swapCalldataUsdtToSusde);

        // Debug: inspect realized sUSDe balance after second swap
        addToBatch(address(_susde), _encodeBalanceOf(_owner));

        // 9. Deposit conservative leftover USDe into sUSDe
        if (usdeToSusdeDepositAmount > 0) {
            console2.log("\n9. Deposit conservative leftover USDe into sUSDe");
            addToBatch(address(_usde), _encodeApprove(address(_susde), usdeToSusdeDepositAmount));
            addToBatch(address(_susde), _encodeDeposit4626(usdeToSusdeDepositAmount, _owner));
        }

        // 10. Zero approvals
        console2.log("\n10. Zero approvals");
        addToBatch(address(_susde), _encodeApprove(address(AAVE_POOL), 0));
        addToBatch(address(_usdt), _encodeApprove(routerUsdtToUsde, 0));
        if (routerUsdtToSusde != routerUsdtToUsde) {
            addToBatch(address(_usdt), _encodeApprove(routerUsdtToSusde, 0));
        }
        addToBatch(address(_usde), _encodeApprove(address(AAVE_POOL), 0));
        addToBatch(address(_usde), _encodeApprove(address(_susde), 0));
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

        uint256 actualSusdeOut = (susdeBalanceAfter + _susdeSuppliedAmount) - _initialSusdeBalance;
        uint256 efficiencyBps = FullMath.mulDiv(actualSusdeOut, 10000, _initialSusdeBalance);

        (, , , , , uint256 healthFactorAfter) = AAVE_POOL.getUserAccountData(REPORTING_MS);

        console2.log("\n--- Post-batch summary ---");
        console2.log("[Iteration] Actual sUSDe out:", _toDecimalString(actualSusdeOut, 18));
        console2.log("[Iteration] sUSDe out efficiency vs initial balance (bps):", efficiencyBps);
        _logCollateralSuppliedSummary();
        _logAaveBalanceSheetReport();
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
            console2.log("Loop iteration efficiency (debt/collateral, bps):", efficiencyBps);
            console2.log("  = %d.%d%%", efficiencyBps / 100, efficiencyBps % 100);
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
        (
            _initialTotalCollateralBase,
            _initialTotalDebtBase,
            _initialNetAccountValueBase
        ) = _getAccountSummaryBase(REPORTING_MS);
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

    function _encodeBalanceOf(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.balanceOf.selector, account);
    }

    function _encodeDeposit4626(
        uint256 assets,
        address receiver
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC4626.deposit.selector, assets, receiver);
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

    /// @notice Compute the amount of leftover USDe (after supplying to Aave) to deposit into sUSDe
    /// @dev    After swap #1, we may receive more USDe than we supply to Aave (due to conservative
    ///         sizing). This leftover is deposited into sUSDe via IERC4626.deposit to capture yield
    ///         rather than leaving it idle. The amount is: min(quote output) - conservative supply amount.
    ///         If supply >= quote min, there's no planned leftover and this returns 0.
    /// @param usdeAmountOut      Quoted USDe output from KyberSwap (18dp)
    /// @param usdeSupplyAmount   Conservative USDe supply amount from _getConservativeUsdeSupplyAmount (18dp)
    /// @param slippageBps        Slippage tolerance in basis points
    /// @return Amount of USDe to deposit into sUSDe (18dp), or 0 if no leftover is expected
    function _getPlannedUsdeToSusdeDepositAmount(
        uint256 usdeAmountOut,
        uint256 usdeSupplyAmount,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        uint256 usdeAmountOutMin = FullMath.mulDiv(usdeAmountOut, 10000 - slippageBps, 10000);
        return usdeAmountOutMin > usdeSupplyAmount ? usdeAmountOutMin - usdeSupplyAmount : 0;
    }

    function _ratioBps(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        return FullMath.mulDiv(numerator, 10000, denominator);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
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
        string memory getUrl = string.concat(
            KYBERSWAP_BASE_URL,
            "/api/v1/routes?tokenIn=",
            vm.toString(tokenIn),
            "&tokenOut=",
            vm.toString(tokenOut),
            "&amountIn=",
            vm.toString(amountIn)
        );

        string[] memory headers = new string[](2);
        headers[0] = "Accept: application/json";
        headers[1] = string.concat("X-Client-Id: ", KYBERSWAP_CLIENT_ID);

        console2.log("\n--- %s: Query Kyber route ---", stepLabel);

        (uint256 getStatus, bytes memory getResponse) = getUrl.get(headers);
        if (getStatus >= 400) revert(string.concat("KyberSwap GET failed: ", string(getResponse)));

        string memory getResponseStr = string(getResponse);
        string memory routeSummaryJson = _extractJsonObjectForKey(getResponseStr, '"routeSummary"');
        amountOut = vm.parseUint(getResponseStr.readString(".data.routeSummary.amountOut"));
        router = vm.parseJsonAddress(getResponseStr, ".data.routerAddress");
        if (router == address(0)) router = KYBERSWAP_ROUTER_FALLBACK;

        console2.log("Route obtained, amountOut:", _toDecimalString(amountOut, 18));
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
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
