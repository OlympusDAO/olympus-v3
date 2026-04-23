// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

// Test
import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";

contract ERC7726OracleGetQuoteTest is ERC7726OracleTest {
    // ========== TESTS ========== //

    // given the oracle is disabled
    //  [X] it reverts

    function test_givenOracleIsDisabled_reverts() public {
        _disableOracle();

        vm.expectRevert(IERC7726Oracle.ERC7726Oracle_NotEnabled.selector);

        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
    }

    // given the base asset is not configured
    //  [X] it reverts

    function test_givenBaseAssetIsNotConfigured_reverts() public givenOracleIsEnabled {
        // Use an address that doesn't have a price set
        address unconfiguredBase = makeAddr("UNCONFIGURED_BASE");

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unconfiguredBase)
        );

        oracle.getQuote(1e18, unconfiguredBase, address(loanToken));
    }

    // given the quote asset is not configured
    //  [X] it reverts

    function test_givenQuoteAssetIsNotConfigured_reverts() public givenOracleIsEnabled {
        // Use an address that doesn't have a price set
        address unconfiguredQuote = makeAddr("UNCONFIGURED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unconfiguredQuote)
        );

        oracle.getQuote(1e18, address(collateralToken), unconfiguredQuote);
    }

    // given the base asset is unit of account
    //  [X] it reverts because unit of account is not an ERC20 token

    function test_givenBaseAssetIsUnitOfAccount_reverts() public givenOracleIsEnabled {
        priceCache.cachePrice(UNIT_OF_ACCOUNT, address(loanToken));

        vm.expectRevert();
        oracle.getQuote(1e18, UNIT_OF_ACCOUNT, address(loanToken));
    }

    // given the quote asset is unit of account
    //  [X] it reverts because unit of account is not an ERC20 token

    function test_givenQuoteAssetIsUnitOfAccount_reverts() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        vm.expectRevert();
        oracle.getQuote(1e18, address(collateralToken), UNIT_OF_ACCOUNT);
    }

    // given getQuotes is called with base asset as unit of account
    //  [X] it reverts because unit of account is not an ERC20 token

    function test_givenGetQuotesBaseAssetIsUnitOfAccount_reverts() public givenOracleIsEnabled {
        priceCache.cachePrice(UNIT_OF_ACCOUNT, address(loanToken));

        vm.expectRevert();
        oracle.getQuotes(1e18, UNIT_OF_ACCOUNT, address(loanToken));
    }

    // given getQuotes is called with quote asset as unit of account
    //  [X] it reverts because unit of account is not an ERC20 token

    function test_givenGetQuotesQuoteAssetIsUnitOfAccount_reverts() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        vm.expectRevert();
        oracle.getQuotes(1e18, address(collateralToken), UNIT_OF_ACCOUNT);
    }

    function test_givenOracleIsEnabled_gasSnapshot_getQuote() public givenOracleIsEnabled {
        vm.startSnapshotGas("ERC7726OracleCloneable.getQuote");
        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    // given the base/quote pair has not been cached
    //  [X] it reverts with stale

    function test_givenBaseAssetPairIsNotCached_revertsWithStale() public givenOracleIsEnabled {
        MockERC20 zeroBaseToken = new MockERC20("Zero Base", "ZBASE", 18);
        _setPRICEPrices(address(zeroBaseToken), 0);
        uint256 latestPermissibleTimestamp = block.timestamp > DEFAULT_MAX_AGE
            ? block.timestamp - DEFAULT_MAX_AGE
            : 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726Oracle.ERC7726Oracle_Stale.selector,
                uint256(0),
                latestPermissibleTimestamp
            )
        );

        oracle.getQuote(1e18, address(zeroBaseToken), address(loanToken));
    }

    // given the base/quote pair has not been cached
    //  [X] it reverts with stale

    function test_givenQuoteAssetPairIsNotCached_revertsWithStale() public givenOracleIsEnabled {
        MockERC20 zeroQuoteToken = new MockERC20("Zero Quote", "ZQUOTE", 18);
        _setPRICEPrices(address(zeroQuoteToken), 0);
        uint256 latestPermissibleTimestamp = block.timestamp > DEFAULT_MAX_AGE
            ? block.timestamp - DEFAULT_MAX_AGE
            : 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726Oracle.ERC7726Oracle_Stale.selector,
                uint256(0),
                latestPermissibleTimestamp
            )
        );

        oracle.getQuote(1e18, address(collateralToken), address(zeroQuoteToken));
    }

    function test_givenOnlyBaseUsdCacheChanges_returnsCachedPairQuote()
        public
        givenOracleIsEnabled
    {
        // Seed the direct pair cache, then refresh only the base/USD cache.
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        uint256 outAmount = oracle.getQuote(1e18, address(collateralToken), address(loanToken));
        assertEq(outAmount, 2e18, "Quote should remain the cached pair quote");
    }

    function test_givenOnlyAssetUsdCacheChanges_returnsCachedPairQuote()
        public
        givenOracleIsEnabled
    {
        // Seed the direct pair cache, then refresh only the quote/USD cache.
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);

        uint256 outAmount = oracle.getQuote(1e18, address(collateralToken), address(loanToken));
        assertEq(outAmount, 2e18, "Quote should remain the cached pair quote");
    }

    function test_givenCloneablePricesAreStale_reverts() public givenOracleIsEnabled {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        vm.warp(block.timestamp + 1 hours + 1);
        uint256 latestPermissibleTimestamp = block.timestamp - uint256(1 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726Oracle.ERC7726Oracle_Stale.selector,
                uint256(1),
                latestPermissibleTimestamp
            )
        );
        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
    }

    function test_givenLiveBasePriceChanges_withoutCacheRefresh_keepsCachedQuote()
        public
        givenOracleIsEnabled
    {
        uint256 initialQuote = oracle.getQuote(1e18, address(collateralToken), address(loanToken));
        assertEq(initialQuote, 2e18, "Initial quote should use cached 2:1 ratio");

        // Update live price only; cloneable reads the cache so this should not affect quote yet.
        _setPRICEPrices(address(collateralToken), 3e18);
        uint256 quoteBeforeRefresh = oracle.getQuote(
            1e18,
            address(collateralToken),
            address(loanToken)
        );
        assertEq(quoteBeforeRefresh, initialQuote, "Quote should remain cached before refresh");

        // Refresh cache and verify quote reflects new ratio.
        vm.warp(block.timestamp + 1);
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint256 quoteAfterRefresh = oracle.getQuote(
            1e18,
            address(collateralToken),
            address(loanToken)
        );
        assertEq(quoteAfterRefresh, 3e18, "Quote should update after cache refresh");
    }

    function test_givenLiveQuotePriceChanges_withoutCacheRefresh_keepsCachedQuote()
        public
        givenOracleIsEnabled
    {
        uint256 initialQuote = oracle.getQuote(1e18, address(collateralToken), address(loanToken));
        assertEq(initialQuote, 2e18, "Initial quote should use cached 2:1 ratio");

        // Update live quote price only; cloneable reads the cache so this should not affect quote yet.
        _setPRICEPrices(address(loanToken), 2e18);
        uint256 quoteBeforeRefresh = oracle.getQuote(
            1e18,
            address(collateralToken),
            address(loanToken)
        );
        assertEq(quoteBeforeRefresh, initialQuote, "Quote should remain cached before refresh");

        // Refresh cache and verify quote reflects new ratio.
        vm.warp(block.timestamp + 1);
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint256 quoteAfterRefresh = oracle.getQuote(
            1e18,
            address(collateralToken),
            address(loanToken)
        );
        assertEq(quoteAfterRefresh, 1e18, "Quote should update after cache refresh");
    }

    // given the base token decimals are smaller than the quote token decimals
    //  [X] it returns the correct quantity of quote tokens
    //  [X] it returns in terms of quote token decimals

    function test_givenBaseTokenDecimalsAreSmallerThanQuoteTokenDecimals_returnsCorrectQuantity()
        public
        givenOracleIsEnabled
    {
        // Create tokens with different decimals
        // Base token: 9 decimals, Quote token: 18 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 9);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        // Set prices: base = 2e18 USD, quote = 1e18 USD
        _setPRICEPrices(address(baseToken), 2e18);
        _setPRICEPrices(address(quoteToken), 1e18);
        priceCache.cachePrice(address(baseToken), address(quoteToken));

        // inAmount = 1e9 (1 base token with 9 decimals)
        uint256 inAmount = 1e9;

        // Calculate expected quote:
        // basePrice = 2e18 (18 decimals)
        // quotePrice = 1e18 (18 decimals)
        // baseDecimals = 9, quoteDecimals = 18, priceDecimals = 18
        // outAmount = (1e9 * 2e18 * 10^18) / (1e18 * 10^9) = (1e9 * 2e18 * 1e18) / (1e18 * 1e9) = 2e18
        uint256 expectedOutAmount = 2e18;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(baseToken), address(quoteToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(baseToken),
            address(quoteToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    // given the quote token decimals are smaller than the base token decimals
    //  [X] it returns the correct quantity of quote tokens
    //  [X] it returns in terms of quote token decimals

    function test_givenQuoteTokenDecimalsAreSmallerThanBaseTokenDecimals_returnsCorrectQuantity()
        public
        givenOracleIsEnabled
    {
        // Create tokens with different decimals
        // Base token: 18 decimals, Quote token: 9 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 18);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 9);

        // Set prices: base = 2e18 USD, quote = 1e18 USD
        _setPRICEPrices(address(baseToken), 2e18);
        _setPRICEPrices(address(quoteToken), 1e18);
        priceCache.cachePrice(address(baseToken), address(quoteToken));

        // inAmount = 1e18 (1 base token with 18 decimals)
        uint256 inAmount = 1e18;

        // Calculate expected quote:
        // basePrice = 2e18 (18 decimals)
        // quotePrice = 1e18 (18 decimals)
        // baseDecimals = 18, quoteDecimals = 9, priceDecimals = 18
        // outAmount = (1e18 * 2e18 * 10^9) / (1e18 * 10^18) = (1e18 * 2e18 * 1e9) / (1e18 * 1e18) = 2e9
        uint256 expectedOutAmount = 2e9;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(baseToken), address(quoteToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(baseToken),
            address(quoteToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    // given the price decimals are not 18
    //  given the base token decimals are smaller than the quote token decimals
    //   [X] it returns the correct quantity of quote tokens
    //   [X] it returns in terms of quote token decimals

    function test_givenPriceDecimalsAreNot18_givenBaseTokenDecimalsAreSmallerThanQuoteTokenDecimals_returnsCorrectQuantity()
        public
        givenOracleIsEnabled
    {
        // Set price decimals to 8
        priceCache.setPriceDecimals(8);

        // Create tokens with different decimals
        // Base token: 9 decimals, Quote token: 18 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 9);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(baseToken), 2e8);
        _setPRICEPrices(address(quoteToken), 1e8);
        priceCache.cachePrice(address(baseToken), address(quoteToken));

        // inAmount = 1e9 (1 base token with 9 decimals)
        uint256 inAmount = 1e9;

        // Calculate expected quote:
        // basePrice = 2e8 (8 decimals)
        // quotePrice = 1e8 (8 decimals)
        // baseDecimals = 9, quoteDecimals = 18, priceDecimals = 8
        // outAmount = (1e9 * 2e8 * 10^18) / (1e8 * 10^9) = (1e9 * 2e8 * 1e18) / (1e8 * 1e9) = 2e18
        uint256 expectedOutAmount = 2e18;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(baseToken), address(quoteToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(baseToken),
            address(quoteToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    //  given the quote token decimals are smaller than the base token decimals
    //   [X] it returns the correct quantity of quote tokens
    //   [X] it returns in terms of quote token decimals

    function test_givenPriceDecimalsAreNot18_givenQuoteTokenDecimalsAreSmallerThanBaseTokenDecimals_returnsCorrectQuantity()
        public
        givenOracleIsEnabled
    {
        // Set price decimals to 8
        priceCache.setPriceDecimals(8);

        // Create tokens with different decimals
        // Base token: 18 decimals, Quote token: 9 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 18);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 9);

        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(baseToken), 2e8);
        _setPRICEPrices(address(quoteToken), 1e8);
        priceCache.cachePrice(address(baseToken), address(quoteToken));

        // inAmount = 1e18 (1 base token with 18 decimals)
        uint256 inAmount = 1e18;

        // Calculate expected quote:
        // basePrice = 2e8 (8 decimals)
        // quotePrice = 1e8 (8 decimals)
        // baseDecimals = 18, quoteDecimals = 9, priceDecimals = 8
        // outAmount = (1e18 * 2e8 * 10^9) / (1e8 * 10^18) = (1e18 * 2e8 * 1e9) / (1e8 * 1e18) = 2e9
        uint256 expectedOutAmount = 2e9;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(baseToken), address(quoteToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(baseToken),
            address(quoteToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    //  [X] it returns the correct quantity of quote tokens
    //  [X] it returns in terms of quote token decimals

    function test_givenPriceDecimalsAreNot18_returnsCorrectQuantity() public givenOracleIsEnabled {
        // Set price decimals to 8
        priceCache.setPriceDecimals(8);

        // Use tokens with same decimals (18)
        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(collateralToken), 2e8);
        _setPRICEPrices(address(loanToken), 1e8);
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        // inAmount = 1e18 (1 base token with 18 decimals)
        uint256 inAmount = 1e18;

        // Calculate expected quote:
        // basePrice = 2e8 (8 decimals)
        // quotePrice = 1e8 (8 decimals)
        // baseDecimals = 18, quoteDecimals = 18, priceDecimals = 8
        // outAmount = (1e18 * 2e8 * 10^18) / (1e8 * 10^18) = (1e18 * 2e8 * 1e18) / (1e8 * 1e18) = 2e18
        uint256 expectedOutAmount = 2e18;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(collateralToken), address(loanToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(collateralToken),
            address(loanToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    // [X] it returns the correct quantity of quote tokens
    // [X] it returns in terms of quote token decimals

    function test_returnsCorrectQuantity() public givenOracleIsEnabled {
        // inAmount = 1e18 (1 base token with 18 decimals)
        uint256 inAmount = 1e18;

        // Calculate expected quote:
        // basePrice = 2e18 (18 decimals)
        // quotePrice = 1e18 (18 decimals)
        // baseDecimals = 18, quoteDecimals = 18, priceDecimals = 18
        // outAmount = (1e18 * 2e18 * 10^18) / (1e18 * 10^18) = (1e18 * 2e18 * 1e18) / (1e18 * 1e18) = 2e18
        uint256 expectedOutAmount = 2e18;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(collateralToken), address(loanToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(collateralToken),
            address(loanToken)
        );

        // Verify results match
        assertEq(outAmount, expectedOutAmount, "getQuote should return correct amount");
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    // given the inAmount is not 1 (in the scale of the token)
    //  [X] it returns the correct quantity of quote tokens
    //  [X] it returns in terms of quote token decimals

    function test_givenInAmountIsNotOne_returnsCorrectQuantity() public givenOracleIsEnabled {
        // inAmount = 5e18 (5 base tokens with 18 decimals)
        uint256 inAmount = 5e18;

        // Calculate expected quote:
        // basePrice = 2e18 (18 decimals)
        // quotePrice = 1e18 (18 decimals)
        // baseDecimals = 18, quoteDecimals = 18, priceDecimals = 18
        // outAmount = (5e18 * 2e18 * 10^18) / (1e18 * 10^18) = (5e18 * 2e18 * 1e18) / (1e18 * 1e18) = 10e18
        uint256 expectedOutAmount = 10e18;

        // Call getQuote
        uint256 outAmount = oracle.getQuote(inAmount, address(collateralToken), address(loanToken));

        // Call getQuotes
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(collateralToken),
            address(loanToken)
        );

        // Verify results match
        assertEq(
            outAmount,
            expectedOutAmount,
            "getQuote should return correct amount for 5 base tokens"
        );
        assertEq(bidOutAmount, expectedOutAmount, "getQuotes bid should match getQuote");
        assertEq(askOutAmount, expectedOutAmount, "getQuotes ask should match getQuote");
    }

    // given the ordering of base and quote tokens are swapped
    //  [X] it returns the correct quantity of quote tokens
    //  [X] it returns in terms of quote token decimals

    function test_givenOrderingSwapped_returnsCorrectQuantity() public givenOracleIsEnabled {
        // Swap the order: use loan token as base and collateral token as quote
        // Original: base (collateral token) = 2e18 USD, quote (loan token) = 1e18 USD
        // Swapped: base (loan token) = 1e18 USD, quote (collateral token) = 2e18 USD
        // inAmount = 1e18 (1 loan token in native decimals)

        uint256 inAmount = 1e18;

        // Calculate expected quote:
        // base token price (loan token) = 1e18 (18 decimals)
        // quote token price (collateral token) = 2e18 (18 decimals)
        // base token decimals = 18, quote token decimals = 18, price decimals = 18
        // outAmount = (1e18 * 1e18 * 10^18) / (2e18 * 10^18) = (1e18 * 1e18 * 1e18) / (2e18 * 1e18) = 0.5e18 (0.5 collateral tokens)
        uint256 expectedOutAmount = 0.5e18;

        // Call getQuote with swapped order
        uint256 outAmount = oracle.getQuote(inAmount, address(loanToken), address(collateralToken));

        // Call getQuotes with swapped order
        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(
            inAmount,
            address(loanToken),
            address(collateralToken)
        );

        // Verify results match
        assertEq(
            outAmount,
            expectedOutAmount,
            "getQuote should return correct amount when tokens are swapped"
        );
        assertEq(
            bidOutAmount,
            expectedOutAmount,
            "getQuotes bid should match getQuote when tokens are swapped"
        );
        assertEq(
            askOutAmount,
            expectedOutAmount,
            "getQuotes ask should match getQuote when tokens are swapped"
        );
    }
}
// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
