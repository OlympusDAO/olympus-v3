// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IAaveV3Pool} from "src/external/interfaces/IAaveV3Pool.sol";
import {FullMath} from "src/libraries/FullMath.sol";

/// @title SUSDeAaveLoop
/// @notice Batch script to execute sUSDe Aave loop yield strategy
/// @dev    Strategy: Supply sUSDe → Borrow USDT → Swap to USDe → Supply USDe → Borrow USDT → Swap to sUSDe
///         Split into 3 functions to handle dynamic amounts between steps
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
    address internal constant KYBERSWAP_ROUTER = 0x6131B37d65fE405d9820C9B10FBb9a118BA031B3;

    // Token addresses (loaded from env.json)
    IERC20 internal _susde;
    IERC20 internal _usde;
    IERC20 internal _usdt;

    // Aave interest rate mode
    uint256 internal constant VARIABLE_RATE = 2;

    // Default values
    uint256 internal constant DEFAULT_BORROW_PERCENTAGE = 9000; // 90%
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 50; // 0.5%
    uint256 internal constant MAX_BORROW_PERCENTAGE = 10000; // 100%
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%

    // Aave eMode category for sUSDe/USDe/USDT stablecoins (hardcoded)
    // Category 2 on Aave Ethereum Core Pool
    uint8 internal constant EMODE_CATEGORY = 2;
    // eMode category 2 LTV (90% = 9000 bps)
    uint256 internal constant EMODE_LTV = 9000;

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

    /// @notice Step 1: Supply sUSDe to Aave and borrow USDT
    /// @dev    If susdeSupplyAmount is 0 or not provided, uses full sUSDe balance
    function supplySusdeAndBorrow(
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

        uint256 susdeSupplyAmount = _readOptionalUint256("susdeSupplyAmount", 0);
        uint256 borrowPercentage = _readOptionalUint256(
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );

        if (borrowPercentage > MAX_BORROW_PERCENTAGE) revert("Borrow percentage exceeds max");
        if (susdeSupplyAmount == 0) susdeSupplyAmount = _susde.balanceOf(_owner);

        console2.log("=== Step 1: Supply sUSDe and Borrow USDT ===");
        console2.log("Owner:", _owner);
        console2.log("sUSDe supply amount:", susdeSupplyAmount);
        console2.log("Borrow percentage (bps):", borrowPercentage);

        if (susdeSupplyAmount == 0) revert("No sUSDe to supply");

        // ============ DECIMAL SCALE CALCULATIONS ============
        // sUSDe: 18 decimals | USDT: 6 decimals | Aave base: 8 decimals (USD)
        //
        // Check if eMode is set to the correct category
        uint256 currentEMode = AAVE_POOL.getUserEMode(_owner);
        bool shouldSetEMode = (currentEMode != EMODE_CATEGORY);

        // Get current available borrows
        (, , uint256 availableBorrowsBase, , , ) = AAVE_POOL.getUserAccountData(_owner);

        // Use eMode category LTV (90%) since we're setting eMode
        // sUSDe reserve-level LTV is 0 because it can only be used in eMode
        uint256 ltv = EMODE_LTV;

        // Calculate expected increase in available borrows from the supply
        // Convert from 18 decimals (sUSDe) to 8 decimals (Aave base currency USD)
        uint256 supplyValueBase = FullMath.mulDiv(
            susdeSupplyAmount,
            10 ** BASE_CURRENCY_DECIMALS,
            1e18
        );
        uint256 expectedBorrowsIncrease = (supplyValueBase * ltv) / 10000;
        uint256 totalExpectedBorrows = availableBorrowsBase + expectedBorrowsIncrease;

        uint256 usdtBorrowAmountBase = (totalExpectedBorrows * borrowPercentage) / 10000;

        // Convert from base currency (USD 8 decimals) to USDT (6 decimals)
        // USDT is priced at ~$1, so: usdt_amount = base_amount * 10^6 / 10^8 = base_amount / 100
        uint256 usdtBorrowAmount = usdtBorrowAmountBase / 1e2;

        console2.log("\n1a. Calculations:");
        console2.log("Current eMode category:", currentEMode);
        console2.log("Target eMode category:", EMODE_CATEGORY);
        console2.log("Should set eMode:", shouldSetEMode);
        console2.log("Current available borrows (base):", availableBorrowsBase);
        console2.log("sUSDe LTV (bps):", ltv);
        console2.log("Expected borrows increase (base):", expectedBorrowsIncrease);
        console2.log("Total expected borrows (base):", totalExpectedBorrows);
        console2.log("USDT borrow amount:", usdtBorrowAmount);

        // NOW add to batch
        // Set eMode if not already set to target category
        if (shouldSetEMode) {
            console2.log("\n1b. Set eMode category to", EMODE_CATEGORY);
            addToBatch(address(AAVE_POOL), _encodeSetUserEMode(EMODE_CATEGORY));
        }

        console2.log("\n1c. Supply sUSDe to Aave");
        addToBatch(address(_susde), _encodeApprove(address(AAVE_POOL), susdeSupplyAmount));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_susde), susdeSupplyAmount, _owner));

        console2.log("\n1d. Set sUSDe as collateral");
        addToBatch(address(AAVE_POOL), _encodeSetUserUseReserveAsCollateral(address(_susde), true));

        console2.log("\n1e. Borrow USDT from Aave");
        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount, _owner));

        console2.log("\n1f. Zero sUSDe approval to Aave Pool");
        addToBatch(address(_susde), _encodeApprove(address(AAVE_POOL), 0));

        console2.log("\n=== Batch prepared ===");
        console2.log("Total batch operations:", _batchTargets.length);

        proposeBatch();
    }

    /// @notice Step 2: Swap USDT to USDe and supply to Aave
    /// @dev    Reads actual USDT balance on-chain and calls KyberSwap API
    function swapAndSupplyUsde(
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

        uint256 slippageBps = _readOptionalUint256("slippageBps", DEFAULT_SLIPPAGE_BPS);
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        console2.log("=== Step 2: Swap USDT to USDe and Supply ===");
        console2.log("Owner:", _owner);
        console2.log("Slippage (bps):", slippageBps);

        // ============ DECIMAL SCALE CALCULATIONS ============
        // USDT: 6 decimals | USDe: 18 decimals
        // KyberSwap handles all decimal conversions internally
        // amountOut is in tokenOut's native decimals (18 for USDe)

        uint256 usdtBalance = _usdt.balanceOf(_owner);
        console2.log("\n2a. USDT balance:", usdtBalance);

        if (usdtBalance == 0) revert("No USDT to swap");

        (bytes memory swapCalldata, uint256 usdeAmountOut) = _getKyberSwapCalldata(
            address(_usdt),
            address(_usde),
            usdtBalance,
            slippageBps
        );

        console2.log("\n2b. KyberSwap route obtained");
        console2.log("Expected USDe output:", usdeAmountOut);

        // NOW add to batch
        console2.log("\n2c. Swap USDT to USDe");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, usdtBalance));
        addToBatch(KYBERSWAP_ROUTER, swapCalldata);

        console2.log("\n2d. Supply USDe to Aave");
        addToBatch(address(_usde), _encodeApprove(address(AAVE_POOL), usdeAmountOut));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_usde), usdeAmountOut, _owner));

        console2.log("\n2e. Set USDe as collateral");
        addToBatch(address(AAVE_POOL), _encodeSetUserUseReserveAsCollateral(address(_usde), true));

        console2.log("\n2f. Zero approvals");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, 0));
        addToBatch(address(_usde), _encodeApprove(address(AAVE_POOL), 0));

        console2.log("\n=== Batch prepared ===");
        console2.log("Total batch operations:", _batchTargets.length);

        proposeBatch();
    }

    /// @notice Step 3: Borrow more USDT and swap to sUSDe
    /// @dev    Calculates borrow amount, borrows, then swaps to sUSDe
    function borrowAndSwapToSusde(
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

        uint256 borrowPercentage = _readOptionalUint256(
            "borrowPercentage",
            DEFAULT_BORROW_PERCENTAGE
        );
        uint256 slippageBps = _readOptionalUint256("slippageBps", DEFAULT_SLIPPAGE_BPS);

        if (borrowPercentage > MAX_BORROW_PERCENTAGE) revert("Borrow percentage exceeds max");
        if (slippageBps > MAX_SLIPPAGE_BPS) revert("Slippage exceeds max");

        console2.log("=== Step 3: Borrow USDT and Swap to sUSDe ===");
        console2.log("Owner:", _owner);
        console2.log("Borrow percentage (bps):", borrowPercentage);
        console2.log("Slippage (bps):", slippageBps);

        // ============ DECIMAL SCALE CALCULATIONS ============
        // USDT: 6 decimals | sUSDe: 18 decimals | Aave base: 8 decimals (USD)
        //
        // availableBorrowsBase: 8 decimals (USD)
        // usdtBorrowAmount: 6 decimals (USDT native)

        (, , uint256 availableBorrowsBase, , , ) = AAVE_POOL.getUserAccountData(_owner);
        uint256 usdtBorrowAmountBase = (availableBorrowsBase * borrowPercentage) / 10000;

        // Convert from base currency (USD 8 decimals) to USDT (6 decimals)
        uint256 usdtBorrowAmount = usdtBorrowAmountBase / 1e2;

        console2.log("\n3a. Calculations:");
        console2.log("Available borrows (base):", availableBorrowsBase);
        console2.log("USDT borrow amount:", usdtBorrowAmount);

        (bytes memory swapCalldata, ) = _getKyberSwapCalldata(
            address(_usdt),
            address(_susde),
            usdtBorrowAmount,
            slippageBps
        );

        console2.log("\n3b. KyberSwap route obtained");

        // NOW add to batch
        console2.log("\n3c. Borrow USDT from Aave");
        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount, _owner));

        console2.log("\n3d. Swap USDT to sUSDe");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, usdtBorrowAmount));
        addToBatch(KYBERSWAP_ROUTER, swapCalldata);

        console2.log("\n3e. Zero USDT approval to Router");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, 0));

        console2.log("\n=== Batch prepared ===");
        console2.log("Total batch operations:", _batchTargets.length);

        proposeBatch();
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

    // ============ KyberSwap API ============

    function _getKyberSwapCalldata(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (bytes memory swapCalldata, uint256 amountOut) {
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

        console2.log("Calling KyberSwap GET /api/v1/routes");

        (uint256 getStatus, bytes memory getResponse) = getUrl.get(headers);
        if (getStatus >= 400) revert(string.concat("KyberSwap GET failed: ", string(getResponse)));

        string memory getResponseStr = string(getResponse);
        bytes memory routeSummaryBytes = vm.parseJson(getResponseStr, ".data.routeSummary");
        amountOut = vm.parseUint(getResponseStr.readString(".data.routeSummary.amountOut"));

        console2.log("Route obtained, amountOut:", amountOut);

        string memory postBody = string.concat(
            '{"routeSummary":',
            string(routeSummaryBytes),
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
