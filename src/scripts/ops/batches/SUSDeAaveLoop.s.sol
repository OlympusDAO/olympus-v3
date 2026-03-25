// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {Surl} from "@surl-1.0.0/Surl.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IAaveV3Pool} from "src/external/interfaces/IAaveV3Pool.sol";

/// @title SUSDeAaveLoop
/// @notice Batch script to execute sUSDe Aave loop yield strategy
/// @dev    Strategy: Supply sUSDe → Borrow USDT → Swap to USDe → Supply USDe → Borrow USDT → Swap to sUSDe
///         Split into 3 functions to handle dynamic amounts between steps
///
///         Aave Pool: Ethereum Core Pool (includes sUSDe, USDe, USDT, and many other assets)
///         Pool Address: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
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

    // KyberSwap API
    string internal constant KYBERSWAP_BASE_URL = "https://aggregator-api.kyberswap.com/ethereum";
    string internal constant KYBERSWAP_CLIENT_ID = "OlympusDAO";

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

        // Approve and Supply sUSDe
        console2.log("\n1a. Supply sUSDe to Aave");
        addToBatch(address(_susde), _encodeApprove(address(AAVE_POOL), susdeSupplyAmount));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_susde), susdeSupplyAmount, _owner));

        // Borrow USDT
        (, , uint256 availableBorrowsBase, , , ) = AAVE_POOL.getUserAccountData(_owner);
        uint256 usdtBorrowAmount = (availableBorrowsBase * borrowPercentage) / 10000;

        console2.log("\n1b. Borrow USDT from Aave");
        console2.log("Available borrows (base):", availableBorrowsBase);
        console2.log("USDT borrow amount:", usdtBorrowAmount);

        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount, _owner));

        // Zero approval
        console2.log("\n1c. Zero sUSDe approval to Aave Pool");
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

        // Swap USDT → USDe
        console2.log("\n2c. Swap USDT to USDe");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, usdtBalance));
        addToBatch(KYBERSWAP_ROUTER, swapCalldata);

        // Supply USDe
        console2.log("\n2d. Supply USDe to Aave");
        addToBatch(address(_usde), _encodeApprove(address(AAVE_POOL), usdeAmountOut));
        addToBatch(address(AAVE_POOL), _encodeSupply(address(_usde), usdeAmountOut, _owner));

        // Zero approvals
        console2.log("\n2e. Zero approvals");
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

        // Borrow USDT
        (, , uint256 availableBorrowsBase, , , ) = AAVE_POOL.getUserAccountData(_owner);
        uint256 usdtBorrowAmount = (availableBorrowsBase * borrowPercentage) / 10000;

        console2.log("\n3a. Borrow USDT from Aave");
        console2.log("Available borrows (base):", availableBorrowsBase);
        console2.log("USDT borrow amount:", usdtBorrowAmount);

        addToBatch(address(AAVE_POOL), _encodeBorrow(address(_usdt), usdtBorrowAmount, _owner));

        // Swap to sUSDe
        (bytes memory swapCalldata, ) = _getKyberSwapCalldata(
            address(_usdt),
            address(_susde),
            usdtBorrowAmount,
            slippageBps
        );

        console2.log("\n3b. KyberSwap route obtained");

        console2.log("\n3c. Swap USDT to sUSDe");
        addToBatch(address(_usdt), _encodeApprove(KYBERSWAP_ROUTER, usdtBorrowAmount));
        addToBatch(KYBERSWAP_ROUTER, swapCalldata);

        // Zero approval
        console2.log("\n3d. Zero USDT approval to Router");
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
