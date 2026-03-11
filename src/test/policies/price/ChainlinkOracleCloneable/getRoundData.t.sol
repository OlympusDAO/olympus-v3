// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract ChainlinkOracleCloneableGetRoundDataTest is ChainlinkOracleCloneableTest {
    // ========== TESTS ========== //

    // getRoundData
    // when factory is disabled
    //  [X] it reverts with ChainlinkOracle_NotEnabled

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NotEnabled.selector);

        oracle.getRoundData(0);
    }

    // when oracle is not enabled
    //  [X] it reverts with ChainlinkOracle_NotEnabled

    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NotEnabled.selector);

        oracle.getRoundData(0);
    }

    // when there is no stored price
    //  [X] it reverts with price zero

    function test_whenThereIsNoStoredPrice_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(baseToken))
        );

        // Call function
        oracle.getRoundData(0);
    }

    // when round ID matches latest round
    //  [X] it returns correct round data
    //  [X] it returns stored price (not live price)

    function test_whenRoundIdMatchesLatest_returnsCorrectRoundData()
        public
        givenPricesAreStored
        warp
    {
        // Change current prices but don't store
        _setPRICEPrices(address(baseToken), 10e18); // 10 USD
        _setPRICEPrices(address(quoteToken), 5e18); // 5 USD

        // Get latest round data
        (
            uint80 latestRoundId,
            int256 latestAnswer,
            uint256 latestStartedAt,
            uint256 latestUpdatedAt,
            uint80 latestAnsweredInRound
        ) = oracle.latestRoundData();

        // Get round data for latest round
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.getRoundData(latestRoundId);

        // Verify all fields match
        assertEq(roundId, latestRoundId, "Round ID should match");
        assertEq(answer, latestAnswer, "Answer should match");
        assertEq(startedAt, latestStartedAt, "StartedAt should match");
        assertEq(updatedAt, latestUpdatedAt, "UpdatedAt should match");
        assertEq(answeredInRound, latestAnsweredInRound, "AnsweredInRound should match");

        // Verify AggregatorV2 interface functions return correct values
        assertEq(
            AggregatorV2V3Interface(address(oracle)).getAnswer(uint256(latestRoundId)),
            answer,
            "getAnswer should return correct answer"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).getTimestamp(uint256(latestRoundId)),
            updatedAt,
            "getTimestamp should return correct timestamp"
        );

        // Verify stored price is returned (not live price)
        // Change current prices but don't store
        _setPRICEPrices(address(baseToken), 15e18); // 15 USD
        _setPRICEPrices(address(quoteToken), 5e18); // 5 USD

        // getRoundData should still return stored price
        (uint80 roundIdAfterChange, int256 answerAfterChange, , , ) = oracle.getRoundData(
            latestRoundId
        );
        assertEq(roundIdAfterChange, latestRoundId, "Round ID should still match");
        assertEq(answerAfterChange, answer, "Should return stored price, not live price");
    }

    // when round ID does not match latest round
    //  [X] it reverts with ChainlinkOracle_NoDataPresent
    //  [X] getAnswer reverts with ChainlinkOracle_NoDataPresent
    //  [X] getTimestamp reverts with ChainlinkOracle_NoDataPresent

    function test_whenRoundIdDoesNotMatchLatest_reverts(
        uint80 roundId_
    ) public givenPricesAreStored warp {
        // Get latest round ID
        (uint80 latestRoundId, , , , ) = oracle.latestRoundData();

        // Get a different round ID
        vm.assume(roundId_ != latestRoundId);

        // Expect revert for getRoundData
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NoDataPresent.selector);
        oracle.getRoundData(roundId_);

        // Expect revert for getAnswer
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NoDataPresent.selector);
        AggregatorV2V3Interface(address(oracle)).getAnswer(uint256(roundId_));

        // Expect revert for getTimestamp
        vm.expectRevert(IChainlinkOracle.ChainlinkOracle_NoDataPresent.selector);
        AggregatorV2V3Interface(address(oracle)).getTimestamp(uint256(roundId_));
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
        (uint80 newRoundId, int256 newAnswer, , , ) = oracle.latestRoundData();

        // Round ID should have changed (new timestamp)
        assertEq(newRoundId, lastStoredTimestamp, "Round ID should have changed");

        // Get round data for new round
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = oracle.getRoundData(newRoundId);

        // Verify round data matches
        assertEq(roundId, newRoundId, "Round ID should match");
        assertEq(answer, newAnswer, "Answer should match");
        assertEq(updatedAt, lastStoredTimestamp, "UpdatedAt should match");

        // Price calculation should use original decimals
        // PRICE module returns prices in new decimals (9), but oracle should scale to original (18)
        // basePrice = 2e9 (9 decimals), quotePrice = 1e9 (9 decimals)
        // Expected: (2e9 / 1e9) * 10^18 = 2e18 (18 decimals, original scale)
        uint256 expectedPrice = (2e9 * 10 ** originalDecimals) / 1e9;
        assertEq(
            answer,
            /// forge-lint: disable-next-line(unsafe-typecast)
            int256(expectedPrice),
            "Price should be calculated with original decimals"
        );

        // Verify AggregatorV2 interface functions also use original decimals
        assertEq(
            AggregatorV2V3Interface(address(oracle)).getAnswer(uint256(newRoundId)),
            answer,
            "getAnswer should return price with original decimals"
        );
        assertEq(
            AggregatorV2V3Interface(address(oracle)).getTimestamp(uint256(newRoundId)),
            updatedAt,
            "getTimestamp should return correct timestamp"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
