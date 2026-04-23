// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleFactoryTest} from "./ChainlinkOracleFactoryTest.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";

contract ChainlinkOracleFactoryEnableTest is ChainlinkOracleFactoryTest {
    function test_whenFactoryIsReenabledAndPairCacheIsMissing_recachesBeforeOraclesAreLive()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(
            address(baseToken),
            address(quoteToken),
            DEFAULT_MAX_AGE
        );

        priceCache.clearCachedPrice(address(baseToken), address(quoteToken));

        vm.prank(admin);
        factory.disable("");

        address[] memory baseTokens = new address[](1);
        baseTokens[0] = address(baseToken);
        address[] memory quoteTokens = new address[](1);
        quoteTokens[0] = address(quoteToken);

        vm.prank(admin);
        factory.enable(abi.encode(baseTokens, quoteTokens));

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IChainlinkOracle(oracle).latestRoundData();

        int256 expectedAnswer = 2e18;
        assertGt(roundId, 0, "Round ID should be non-zero");
        assertEq(answer, expectedAnswer, "Oracle should be live immediately after re-enable");
        assertGt(updatedAt, 0, "UpdatedAt should be recached");
        assertEq(startedAt, updatedAt, "StartedAt should match updatedAt");
        assertEq(answeredInRound, roundId, "AnsweredInRound should equal roundId");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
