// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

// Test
import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleGetQuoteTest is ERC7726OracleTest {
    // ========== TESTS ========== //

    // given the oracle is disabled
    //  [X] it reverts

    function test_givenOracleIsDisabled_reverts() public {
        // Oracle starts disabled by default, so we can test directly
        // Note: This assumes getQuote will check isEnabled and revert with NotEnabled
        vm.expectRevert(IEnabler.NotEnabled.selector);

        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
    }

    // given the base asset is not configured
    //  [X] it reverts

    function test_givenBaseAssetIsNotConfigured_reverts() public givenOracleIsEnabled {
        // Use an address that doesn't have a price set
        address unconfiguredBase = makeAddr("UNCONFIGURED_BASE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unconfiguredBase)
        );

        oracle.getQuote(1e18, unconfiguredBase, address(loanToken));
    }

    // given the quote asset is not configured
    //  [X] it reverts

    function test_givenQuoteAssetIsNotConfigured_reverts() public givenOracleIsEnabled {
        // Use an address that doesn't have a price set
        address unconfiguredQuote = makeAddr("UNCONFIGURED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unconfiguredQuote)
        );

        oracle.getQuote(1e18, address(collateralToken), unconfiguredQuote);
    }

    // given the base asset price is zero
    //  [X] it reverts

    function test_givenBaseAssetPriceIsZero_reverts() public givenOracleIsEnabled {
        // Set base asset price to zero
        _setPRICEPrices(address(collateralToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(collateralToken))
        );

        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
    }

    // given the quote asset price is zero
    //  [X] it reverts

    function test_givenQuoteAssetPriceIsZero_reverts() public givenOracleIsEnabled {
        // Set quote asset price to zero
        _setPRICEPrices(address(loanToken), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(loanToken))
        );

        oracle.getQuote(1e18, address(collateralToken), address(loanToken));
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
        priceModule.setPriceDecimals(8);

        // Create tokens with different decimals
        // Base token: 9 decimals, Quote token: 18 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 9);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(baseToken), 2e8);
        _setPRICEPrices(address(quoteToken), 1e8);

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
        priceModule.setPriceDecimals(8);

        // Create tokens with different decimals
        // Base token: 18 decimals, Quote token: 9 decimals
        MockERC20 baseToken = new MockERC20("Base Token", "BASE", 18);
        MockERC20 quoteToken = new MockERC20("Quote Token", "QUOTE", 9);

        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(baseToken), 2e8);
        _setPRICEPrices(address(quoteToken), 1e8);

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
        priceModule.setPriceDecimals(8);

        // Use tokens with same decimals (18)
        // Set prices: base = 2e8 USD, quote = 1e8 USD (8 decimals)
        _setPRICEPrices(address(collateralToken), 2e8);
        _setPRICEPrices(address(loanToken), 1e8);

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
