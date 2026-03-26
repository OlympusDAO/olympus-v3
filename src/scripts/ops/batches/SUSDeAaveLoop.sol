// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
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

    // Aave interest rate mode
    uint256 internal constant VARIABLE_RATE = 2;

    // Default values
    uint256 internal constant DEFAULT_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 5; // 0.05%
    uint256 internal constant DEFAULT_USDE_SUPPLY_PERCENTAGE_BPS = 10_000; // 100%
    uint256 internal constant DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS = 9990; // 99.90% (USDT -> USDe)
    uint256 internal constant DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS = 9990; // 99.90% (USDT -> sUSDe value)
    uint256 internal constant MAX_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%

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

    /// @notice Load token addresses from env.json
    function _loadTokens() internal {
        _susde = IERC20(_envAddressNotZero("external.tokens.sUSDE"));
        _usde = IERC20(_envAddressNotZero("external.tokens.USDE"));
        _usdt = IERC20(_envAddressNotZero("external.tokens.USDT"));
    }

    /// @notice Execute one full sUSDe Aave loop iteration in a single multisig batch
    /// @dev    If susdeSupplyAmount is 0 or not provided, uses full sUSDe balance
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

        uint256 susdeSupplyAmount = _readOptionalUint256("susdeSupplyAmount", 0);
        uint256 borrowPercentage = _readOptionalUint256(
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );

        if (borrowPercentage > MAX_BORROW_PERCENTAGE) revert("Borrow percentage exceeds max");
        uint256 slippageBps = _readOptionalUint256("slippageBps", DEFAULT_SLIPPAGE_BPS);
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        if (susdeSupplyAmount == 0) susdeSupplyAmount = _initialSusdeBalance;
        if (susdeSupplyAmount == 0) revert("No sUSDe to supply");
        _susdeSuppliedAmount = susdeSupplyAmount;

        console2.log("=== Execute Loop: sUSDe -> USDT -> USDe -> sUSDe ===");
        console2.log("Owner:", _owner);
        console2.log("sUSDe supply amount (from wallet):", susdeSupplyAmount);
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
                uint256 availableBorrowsBase,
                uint256 currentLiquidationThreshold,
                ,
                uint256 healthFactor
            ) = AAVE_POOL.getUserAccountData(_owner);

            uint256 susdeSupplyValueUsde = _susdeToUsdeValue(susdeSupplyAmount);
            uint256 supplyValueBase = FullMath.mulDiv(
                susdeSupplyValueUsde,
                10 ** BASE_CURRENCY_DECIMALS,
                1e18
            );
            totalExpectedBorrowsAfterSusdeSupply =
                availableBorrowsBase +
                ((supplyValueBase * EMODE_LTV) / 10000);

            usdtBorrowAmount1 =
                ((totalExpectedBorrowsAfterSusdeSupply * borrowPercentage) / 10000) /
                1e2;
            if (usdtBorrowAmount1 == 0) revert("USDT borrow amount 1 is zero");

            console2.log("\n--- Step 1: Estimate Borrow #1 from sUSDe supply ---");
            console2.log("Current eMode category:", currentEMode);
            console2.log("Will set eMode in batch:", shouldSetEMode);
            console2.log("Current available borrows base (8dp USD):", availableBorrowsBase);
            console2.log("Current liquidation threshold (bps):", currentLiquidationThreshold);
            console2.log("Current health factor (1e18):", healthFactor);
            console2.log("sUSDe supply value (USDe, 18dp):", susdeSupplyValueUsde);
            console2.log("sUSDe supply value base (8dp USD):", supplyValueBase);
            console2.log(
                "Projected available borrows after sUSDe supply (8dp USD):",
                totalExpectedBorrowsAfterSusdeSupply
            );
            console2.log("Borrow #1 target base (8dp USD):", usdtBorrowAmount1 * 1e2);
            console2.log("Borrow #1 amount USDT (6dp):", usdtBorrowAmount1);
            console2.log(
                "Borrow #1 utilization vs projected capacity (bps):",
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

        console2.log("\n--- Step 2: Build swap #1 (USDT -> USDe) ---");
        console2.log("Expected USDe out from quote (18dp):", usdeAmountOut);
        {
            uint256 minSwap1ValueRatioBps = _readOptionalUint256(
                "minSwap1ValueRatioBps",
                _readOptionalUint256("minSwap1QuoteRatioBps", DEFAULT_MIN_SWAP1_VALUE_RATIO_BPS)
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
            "Conservative USDe supply haircut vs quote (bps):",
            _ratioBps(usdeSupplyAmount, usdeAmountOut)
        );

        _plannedUsdeToSusdeDepositAmount = _getPlannedUsdeToSusdeDepositAmount(
            usdeAmountOut,
            usdeSupplyAmount,
            slippageBps
        );
        console2.log(
            "Planned USDe -> sUSDe deposit amount (conservative, 18dp):",
            _plannedUsdeToSusdeDepositAmount
        );

        uint256 usdtBorrowAmount2;
        {
            uint256 usdeSupplyValueBase = FullMath.mulDiv(
                usdeSupplyAmount,
                10 ** BASE_CURRENCY_DECIMALS,
                1e18
            );
            uint256 totalExpectedBorrowsAfterUsdeSupply = (totalExpectedBorrowsAfterSusdeSupply -
                (usdtBorrowAmount1 * 1e2)) + ((usdeSupplyValueBase * EMODE_LTV) / 10000);

            usdtBorrowAmount2 =
                ((totalExpectedBorrowsAfterUsdeSupply * borrowPercentage) / 10000) /
                1e2;
            if (usdtBorrowAmount2 == 0) revert("USDT borrow amount 2 is zero");

            console2.log("\n--- Step 3: Estimate Borrow #2 after USDe supply ---");
            console2.log("Conservative USDe supply amount (18dp):", usdeSupplyAmount);
            console2.log("USDe supply value base (8dp USD):", usdeSupplyValueBase);
            console2.log(
                "Projected available borrows after USDe supply (8dp USD):",
                totalExpectedBorrowsAfterUsdeSupply
            );
            console2.log("Borrow #2 target base (8dp USD):", usdtBorrowAmount2 * 1e2);
            console2.log("Borrow #2 amount USDT (6dp):", usdtBorrowAmount2);
            console2.log(
                "Borrow #2 utilization vs projected capacity (bps):",
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

        console2.log("\n--- Step 4: Build swap #2 (USDT -> sUSDe) ---");
        console2.log("Expected sUSDe out from quote (18dp):", susdeAmountOut);
        {
            uint256 minSwap2ValueRatioBps = _readOptionalUint256(
                "minSwap2ValueRatioBps",
                _readOptionalUint256("minSwap2QuoteRatioBps", DEFAULT_MIN_SWAP2_VALUE_RATIO_BPS)
            );
            if (minSwap2ValueRatioBps == 0 || minSwap2ValueRatioBps > 10000) {
                revert("Swap #2 min value ratio invalid");
            }
            uint256 susdeUsdeRate = _susdeExchangeRate();
            uint256 swap2ValueOutUsd = _susdeToUsdeValue(susdeAmountOut);
            console2.log("sUSDe exchange rate (USDe per 1 sUSDe, 1e18):", susdeUsdeRate);
            console2.log("Swap #2 quoted value out (USDe 18dp):", swap2ValueOutUsd);

            _logAndValidateValueRatio(
                "Swap #2 (USDT -> sUSDe)",
                swap2ValueOutUsd,
                _usdtToUsd18(usdtBorrowAmount2),
                minSwap2ValueRatioBps
            );
        }
        _expectedMinSusdeOut = FullMath.mulDiv(susdeAmountOut, 10000 - slippageBps, 10000);
        console2.log("Expected min sUSDe out after slippage buffer (18dp):", _expectedMinSusdeOut);
        console2.log(
            "Min-out buffer vs quote (bps):",
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

        // 5. Swap USDT -> USDe
        console2.log("\n5. Swap USDT amount 1 to USDe");
        // USDT requires resetting allowance to zero before setting a new non-zero allowance.
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
        // USDT requires resetting allowance to zero before setting a new non-zero allowance.
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

    function _validateExecuteLoopPostBatch() external view {
        uint256 susdeBalanceAfter = _susde.balanceOf(_owner);
        if (susdeBalanceAfter < _expectedMinSusdeOut) {
            revert(
                string.concat(
                    "sUSDe balance should be at least ",
                    vm.toString(_expectedMinSusdeOut),
                    ", but is ",
                    vm.toString(susdeBalanceAfter)
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
        console2.log("Actual sUSDe out (swap #2):", actualSusdeOut);
        console2.log("sUSDe out efficiency vs initial balance (bps):", efficiencyBps);
        _logAaveBalanceSheetReport();
        console2.log("Aave health factor after batch (1e18):", healthFactorAfter);
        console2.log("executeLoop post-batch validation passed");
    }

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
            console2.log("Loop collateral change (8dp USD): +", collateralDelta);
        } else {
            console2.log("Loop collateral change (8dp USD): -", collateralDelta);
        }

        if (debtIncreased) {
            console2.log("Loop debt change (8dp USD): +", debtDelta);
        } else {
            console2.log("Loop debt change (8dp USD): -", debtDelta);
        }

        if (netIncreased) {
            console2.log("Loop net account value change (8dp USD): +", netDelta);
        } else {
            console2.log("Loop net account value change (8dp USD): -", netDelta);
        }

        console2.log("Position total collateral (8dp USD):", totalCollateralBaseAfter);
        console2.log("Position total debt (8dp USD):", totalDebtBaseAfter);
        console2.log("Position net account value (8dp USD):", netAccountValueBaseAfter);
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

    function _getConservativeUsdeSupplyAmount(
        uint256 usdeAmountOut,
        uint256 usdtAmountIn,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        // Quote-based minimum (18 decimals): amountOut * (1 - slippage)
        uint256 quoteBased = FullMath.mulDiv(usdeAmountOut, 10000 - slippageBps, 10000);

        // Input-notional minimum (18 decimals): usdt(6) -> usde(18) at 1:1, then apply slippage
        uint256 inputBased = FullMath.mulDiv(usdtAmountIn, 1e18, 1e6);
        inputBased = FullMath.mulDiv(inputBased, 10000 - slippageBps, 10000);

        uint256 conservativeAmount = inputBased < quoteBased ? inputBased : quoteBased;
        return FullMath.mulDiv(conservativeAmount, DEFAULT_USDE_SUPPLY_PERCENTAGE_BPS, 10000);
    }

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
        console2.log("Calling KyberSwap GET /api/v1/routes");

        (uint256 getStatus, bytes memory getResponse) = getUrl.get(headers);
        if (getStatus >= 400) revert(string.concat("KyberSwap GET failed: ", string(getResponse)));

        string memory getResponseStr = string(getResponse);
        string memory routeSummaryJson = _extractJsonObjectForKey(getResponseStr, '"routeSummary"');
        amountOut = vm.parseUint(getResponseStr.readString(".data.routeSummary.amountOut"));
        router = vm.parseJsonAddress(getResponseStr, ".data.routerAddress");
        if (router == address(0)) router = KYBERSWAP_ROUTER_FALLBACK;

        console2.log("Route obtained, amountOut:", amountOut);
        console2.log("Router:", router);

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

        console2.log("Calling KyberSwap POST /api/v1/route/build");

        (uint256 postStatus, bytes memory postResponse) = string
            .concat(KYBERSWAP_BASE_URL, "/api/v1/route/build")
            .post(headers, postBody);
        if (postStatus >= 400)
            revert(string.concat("KyberSwap POST failed: ", string(postResponse)));

        swapCalldata = vm.parseBytes(string(postResponse).readString(".data.data"));
        console2.log("Swap calldata obtained, length:", bytes(swapCalldata).length);
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
        string memory key,
        uint256 defaultValue
    ) internal view returns (uint256) {
        if (bytes(_argsFile).length == 0) return defaultValue;

        string memory path = string.concat(".functions[0].args.", key);
        try vm.parseJson(_argsFile, path) returns (bytes memory parsed) {
            if (parsed.length == 0) return defaultValue;
            return abi.decode(parsed, (uint256));
        } catch {
            return defaultValue;
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
