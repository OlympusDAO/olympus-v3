// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Actions} from "src/Kernel.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract ChainlinkOracleCloneableLatestRoundDataTest is ChainlinkOracleCloneableTest {
    // ========== TESTS ========== //

    // latestRoundData
    // when factory is disabled
    //  [X] it reverts with ChainlinkOracle_NotEnabled

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NotEnabled.selector);

        oracle.latestRoundData();
    }

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        oracle.latestRoundData();
    }

    // when oracle is not enabled
    //  [X] it reverts with ChainlinkOracle_NotEnabled

    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NotEnabled.selector);

        oracle.latestRoundData();
    }

    // when live prices become zero but cache already exists
    //  [X] it still returns cached round data

    function test_whenLivePricesAreZeroButCacheExists_returnsCachedPrice() public {
        // The oracle uses cached values and does not fallback to live pricing.
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        _setPRICEPrices(address(baseToken), 0);
        _setPRICEPrices(address(quoteToken), 0);

        (, int256 answer, , , ) = oracle.latestRoundData();
        // Expected cached round answer:
        // BASE_PRICE = 2e18, QUOTE_PRICE = 1e18, PRICE_DECIMALS = 18
        // (BASE_PRICE * 10^PRICE_DECIMALS) / QUOTE_PRICE
        // = (2e18 * 1e18) / 1e18
        // = 2e18
        assertEq(answer, 2e18, "Should return cached round");
    }

    // when cached ratio rounds down to zero
    //  [X] it reverts with ChainlinkOracle_NoDataPresent

    function test_whenCachedRatioRoundsDownToZero_reverts() public {
        _setPRICEPrices(address(baseToken), 1);
        _setPRICEPrices(address(quoteToken), 1e36);
        _storePrices();

        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NoDataPresent.selector);
        oracle.latestRoundData();
    }

    // when cached pair price exceeds int256
    //  [X] it reverts via SafeCast.toInt256 overflow guard

    function test_whenCachedPairPriceExceedsInt256_reverts() public {
        uint256 overflowPrice = uint256(type(int256).max) + 1;
        _setPRICEPrices(address(baseToken), overflowPrice);
        _setPRICEPrices(address(quoteToken), QUOTE_PRICE);
        _storePrices();

        vm.expectRevert(bytes("SafeCast: value doesn't fit in an int256"));
        oracle.latestRoundData();
    }

    // when oracle is enabled
    //  [X] it returns correct round data
    //  [X] it returns correct price calculation
    //  [X] it returns cached pair round ID
    //  [X] it returns stored price (not live price)

    function test_whenOracleIsEnabled_returnsCorrectRoundData() public givenPricesAreStored warp {
        // Change current prices but don't store
        _setPRICEPrices(address(baseToken), 15e18); // 15 USD
        _setPRICEPrices(address(quoteToken), 5e18); // 5 USD

        // Calculate expected price: (basePrice / quotePrice) * 10^PRICE_DECIMALS
        // basePrice = 2e18, quotePrice = 1e18
        // Expected: (2e18 / 1e18) * 1e18 = 2e18
        uint256 expectedPrice = (BASE_PRICE * 10 ** PRICE_DECIMALS) / QUOTE_PRICE;

        // Get round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(roundId, lastStoredRoundId, "Round ID should match pair round");

        // Verify answer is correct
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(answer, int256(expectedPrice), "Answer should be correct price");

        // Verify timestamps
        assertEq(startedAt, lastStoredTimestamp, "StartedAt should be the pair timestamp");
        assertEq(updatedAt, lastStoredTimestamp, "UpdatedAt should be the pair timestamp");

        // Verify answeredInRound
        assertEq(answeredInRound, roundId, "AnsweredInRound should equal roundId");

        // Verify AggregatorV2 interface functions return correct values
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestAnswer(),
            answer,
            "latestAnswer should return correct answer"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestTimestamp(),
            updatedAt,
            "latestTimestamp should return correct timestamp"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestRound(),
            uint256(roundId),
            "latestRound should return correct round ID"
        );
    }

    // when base/quote decimals are highly mismatched (0 vs 18)
    //  [X] it still returns the correctly scaled non-zero answer for a 1:3 ratio
    function test_whenBaseIsZeroDecimalsAndQuoteIsEighteenDecimals_givenOneToThreeRatio_returnsNonZeroAnswer()
        public
    {
        MockERC20 zeroDecBase = new MockERC20("Zero Dec Base", "ZBASE", 0);
        MockERC20 eighteenDecQuote = new MockERC20("Eighteen Dec Quote", "EQUOTE", 18);

        _setPRICEPrices(address(zeroDecBase), 1e18);
        _setPRICEPrices(address(eighteenDecQuote), 3e18);

        vm.prank(admin);
        address newOracle = factory.createOracle(
            address(zeroDecBase),
            address(eighteenDecQuote),
            DEFAULT_MAX_AGE,
            bytes("")
        );

        // Cache direct pair snapshot consumed by cloneable oracle.
        priceCache.cachePrice(address(zeroDecBase), address(eighteenDecQuote));

        // Expected answer: (1e18 * 1e18) / 3e18 = 333333333333333333
        uint256 expectedAnswer = 333333333333333333;

        (, int256 answer, , , ) = IChainlinkOracle(newOracle).latestRoundData();
        assertEq(
            answer,
            /// forge-lint: disable-next-line(unsafe-typecast)
            int256(expectedAnswer),
            "Should return non-zero scaled answer with 0/18 token decimals"
        );
    }

    function test_whenOracleIsEnabled_gasSnapshotLatestRoundData() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.latestRoundData");
        oracle.latestRoundData();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_whenOracleIsEnabled_gasSnapshotLatestAnswer() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.latestAnswer");
        AggregatorV2V3Interface(address(oracle)).latestAnswer();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_whenOracleIsEnabled_gasSnapshotLatestTimestamp() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.latestTimestamp");
        AggregatorV2V3Interface(address(oracle)).latestTimestamp();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_whenOracleIsEnabled_gasSnapshotLatestRound() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.latestRound");
        AggregatorV2V3Interface(address(oracle)).latestRound();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_whenOracleIsEnabled_gasSnapshotGetRoundData() public givenPricesAreStored {
        (uint80 roundId, , , , ) = oracle.latestRoundData();

        vm.startSnapshotGas("ChainlinkOracleCloneable.getRoundData");
        oracle.getRoundData(roundId);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    // when cache decimals change
    //  [X] it continues to use original oracle decimals
    //  [X] it returns correct price calculation with original decimals

    function test_whenPriceCacheDecimalsChange_continuesToUseOriginalDecimals() public {
        // Get original decimals
        uint8 originalDecimals = oracle.decimals();

        // Verify original decimals
        assertEq(originalDecimals, PRICE_DECIMALS, "Should have original PRICE decimals");

        // Change cache decimals
        uint8 newDecimals = 9;
        priceCache.setPriceDecimals(newDecimals);

        // Verify cache decimals changed
        assertEq(priceCache.decimals(), newDecimals, "Price cache decimals should have changed");

        // Verify oracle still returns original decimals
        assertEq(
            oracle.decimals(),
            originalDecimals,
            "Oracle should still return original decimals"
        );

        // Update prices (with new decimal scale in cache policy)
        // Prices in cache policy are now in new decimal scale
        _setPRICEPrices(address(baseToken), 2e9); // 2 USD in 9 decimals
        _setPRICEPrices(address(quoteToken), 1e9); // 1 USD in 9 decimals

        // Store prices
        _storePrices();

        // Warp
        _warp();

        // Change current prices but don't store
        _setPRICEPrices(address(baseToken), 15e9); // 15 USD
        _setPRICEPrices(address(quoteToken), 5e9); // 5 USD

        // Get new round data
        (uint80 newRoundId, int256 newAnswer, , uint256 updatedAt, ) = oracle.latestRoundData();

        assertEq(newRoundId, lastStoredRoundId, "Round ID should match pair round");

        // Price calculation should use original decimals
        // Cache policy returns prices in new decimals (9), but oracle should scale to original (18)
        // basePrice = 2e9 (9 decimals), quotePrice = 1e9 (9 decimals)
        // Expected: (2e9 / 1e9) * 10^18 = 2e18 (18 decimals, original scale)
        uint256 expectedPrice = (2e9 * 10 ** originalDecimals) / 1e9;
        assertEq(
            newAnswer,
            /// forge-lint: disable-next-line(unsafe-typecast)
            int256(expectedPrice),
            "Price should be calculated with original decimals"
        );

        // Verify AggregatorV2 interface functions also use original decimals
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestAnswer(),
            newAnswer,
            "latestAnswer should return price with original decimals"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestTimestamp(),
            updatedAt,
            "latestTimestamp should return correct timestamp"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).latestRound(),
            uint256(newRoundId),
            "latestRound should return correct round ID"
        );
    }

    // when cached prices are fresh (within maxAge)
    //  [X] it returns cached prices even if live prices changed

    function test_whenCachedPricesAreFresh_returnsCachedPrices(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        // Change live prices without storing
        _setPRICEPrices(address(baseToken), 15e18); // live base
        _setPRICEPrices(address(quoteToken), 5e18); // live quote

        // Fuzz warp to a time strictly within maxAge so cache remains fresh
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE - 1));
        vm.warp(lastStoredTimestamp + warpDelta);

        // Cached ratio should still be BASE_PRICE / QUOTE_PRICE = 2
        (, int256 answer, , , ) = oracle.latestRoundData();

        // Expected cached answer:
        // (2e18 * 1e18) / 1e18 = 2e18
        assertEq(answer, 2e18, "Should return cached price while fresh");
    }

    function test_whenCachedAgeEqualsMaxAge_returnsCachedPrices() public givenPricesAreStored {
        // Change live prices without storing so we can distinguish cache vs live paths
        _setPRICEPrices(address(baseToken), 15e18); // live base
        _setPRICEPrices(address(quoteToken), 5e18); // live quote

        // Border case: cached age is exactly maxAge and should still be treated as fresh
        vm.warp(lastStoredTimestamp + DEFAULT_MAX_AGE);

        // Cached ratio remains BASE_PRICE / QUOTE_PRICE = 2
        (, int256 answer, , , ) = oracle.latestRoundData();

        // Expected cached answer:
        // (2e18 * 1e18) / 1e18 = 2e18
        assertEq(answer, 2e18, "Should return cached price at maxAge boundary");
    }

    // when cached prices are stale (older than maxAge)
    //  [X] it returns cached prices (round semantics)

    function test_whenCachedPricesAreStale_returnsCachedPrices(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        // Fuzz warp to a time strictly beyond maxAge so cache is stale
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(lastStoredTimestamp + warpDelta);

        // Change live prices without storing
        uint256 liveBase = 15e18;
        uint256 liveQuote = 5e18;
        _setPRICEPrices(address(baseToken), liveBase);
        _setPRICEPrices(address(quoteToken), liveQuote);

        // Round-style semantics always return cached values.
        (, int256 answer, , , ) = oracle.latestRoundData();

        // Expected cached answer:
        // (2e18 * 1e18) / 1e18 = 2e18
        assertEq(answer, 2e18, "Should return cached price even when cache is stale");
    }

    function test_whenOnlyQuoteUsdCacheChanges_returnsCachedPairRound()
        public
        givenPricesAreStored
    {
        // Move to a new block and update live quote price.
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(quoteToken), 4e18);

        // Refresh only the quote/USD cache. The direct base/quote pair cache should be unchanged.
        priceCache.cachePrice(address(quoteToken), UNIT_OF_ACCOUNT);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(roundId, lastStoredRoundId, "Round ID should remain the cached pair round");
        assertEq(answer, 2e18, "Answer should remain the cached pair price");
        assertEq(
            startedAt,
            lastStoredTimestamp,
            "StartedAt should remain the cached pair timestamp"
        );
        assertEq(
            updatedAt,
            lastStoredTimestamp,
            "UpdatedAt should remain the cached pair timestamp"
        );
        assertEq(answeredInRound, roundId, "AnsweredInRound should equal roundId");
    }

    function test_whenOnlyBaseUsdCacheChanges_returnsCachedPairRound() public givenPricesAreStored {
        // Move to a new block and update live base price.
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(baseToken), 8e18);

        // Refresh only the base/USD cache. The direct base/quote pair cache should be unchanged.
        priceCache.cachePrice(address(baseToken), UNIT_OF_ACCOUNT);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        assertEq(roundId, lastStoredRoundId, "Round ID should remain the cached pair round");
        assertEq(answer, 2e18, "Answer should remain the cached pair price");
        assertEq(
            startedAt,
            lastStoredTimestamp,
            "StartedAt should remain the cached pair timestamp"
        );
        assertEq(
            updatedAt,
            lastStoredTimestamp,
            "UpdatedAt should remain the cached pair timestamp"
        );
        assertEq(answeredInRound, roundId, "AnsweredInRound should equal roundId");
    }

    function test_whenQuoteTokenRemovedFromPRICE_reverts() public givenPricesAreStored {
        priceCache.setAssetApproval(address(quoteToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, address(quoteToken))
        );
        oracle.latestRoundData();
    }

    function test_whenBaseTokenRemovedFromPRICE_reverts() public givenPricesAreStored {
        priceCache.setAssetApproval(address(baseToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, address(baseToken))
        );
        oracle.latestRoundData();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
