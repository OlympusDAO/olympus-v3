// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
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

    // when oracle is not enabled
    //  [X] it reverts with ChainlinkOracle_NotEnabled

    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NotEnabled.selector);

        oracle.latestRoundData();
    }

    // when live prices become zero but cache already exists
    //  [X] it still returns cached round data

    function test_whenLivePricesAreZeroButCacheExists_returnsCachedPrice() public {
        // The oracle uses cached LAST values and does not fallback to live pricing.
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

    // when oracle is enabled
    //  [X] it returns correct round data
    //  [X] it returns correct price calculation
    //  [X] it returns timestamp as round ID
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

        // Verify round ID is the timestamp
        assertEq(roundId, uint80(lastStoredTimestamp), "Round ID should be the timestamp");

        // Verify answer is correct
        /// forge-lint: disable-next-line(unsafe-typecast)
        assertEq(answer, int256(expectedPrice), "Answer should be correct price");

        // Verify timestamps
        assertEq(startedAt, lastStoredTimestamp, "StartedAt should be the timestamp");
        assertEq(updatedAt, lastStoredTimestamp, "UpdatedAt should be the timestamp");

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

    function test_whenOracleIsEnabled_gasSnapshotLatestRoundData() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.latestRoundData");
        oracle.latestRoundData();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    // when PRICE decimals change
    //  [X] it continues to use original PRICE decimals
    //  [X] it returns correct price calculation with original decimals

    function test_whenPRICEDecimalsChange_continuesToUseOriginalDecimals() public {
        // Get original decimals
        uint8 originalDecimals = oracle.decimals();

        // Verify original decimals
        assertEq(originalDecimals, PRICE_DECIMALS, "Should have original PRICE decimals");

        // Change PRICE module decimals
        uint8 newDecimals = 9;
        priceModule.setPriceDecimals(newDecimals);

        // Verify PRICE module decimals changed
        assertEq(priceModule.decimals(), newDecimals, "PRICE module decimals should have changed");

        // Verify oracle still returns original decimals
        assertEq(
            oracle.decimals(),
            originalDecimals,
            "Oracle should still return original decimals"
        );

        // Update prices (with new decimal scale in PRICE module)
        // Prices in PRICE module are now in new decimal scale
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

        // Round ID should have changed (new timestamp)
        assertEq(newRoundId, lastStoredTimestamp, "Round ID should have changed");

        // Price calculation should use original decimals
        // PRICE module returns prices in new decimals (9), but oracle should scale to original (18)
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

        // Round-style semantics always return cached LAST values.
        (, int256 answer, , , ) = oracle.latestRoundData();

        // Expected cached answer:
        // (2e18 * 1e18) / 1e18 = 2e18
        assertEq(answer, 2e18, "Should return cached price even when cache is stale");
    }

    function test_whenBaseAndQuoteTimestampsDiffer_reverts() public givenPricesAreStored {
        // Move to a new block and update live prices.
        vm.warp(block.timestamp + 1);
        _setPRICEPrices(address(baseToken), 8e18);
        _setPRICEPrices(address(quoteToken), 4e18);

        // Refresh only base cache so LAST timestamps diverge.
        priceModule.cachePrice(address(baseToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkOracle.ChainlinkOracle_InconsistentTimestamps.selector,
                uint48(block.timestamp),
                uint48(block.timestamp - 1)
            )
        );
        oracle.latestRoundData();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
