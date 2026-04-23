// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";

contract ERC7726OracleFactoryEnableTest is ERC7726OracleFactoryTest {
    function test_whenEnableDataIsEmpty_succeedsWithoutRecache()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        vm.warp(uint256(oldTimestamp) + uint256(DEFAULT_MAX_AGE) + 1);

        vm.prank(admin);
        factory.disable("");

        vm.prank(admin);
        factory.enable("");

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        assertEq(newTimestamp, oldTimestamp, "Cache timestamp should not be refreshed");

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726Oracle.ERC7726Oracle_Stale.selector,
                oldTimestamp,
                DEFAULT_MAX_AGE
            )
        );
        IERC7726Oracle(oracle).getQuote(1e18, address(baseToken), address(quoteToken));
    }

    function test_whenFactoryIsReenabledWithPairData_recachesBeforeOraclesAreLive()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        priceCache.cachePrice(address(baseToken), address(quoteToken));
        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        vm.warp(uint256(oldTimestamp) + uint256(DEFAULT_MAX_AGE) + 1);

        vm.prank(admin);
        factory.disable("");

        address[] memory baseTokens = new address[](1);
        baseTokens[0] = address(baseToken);
        address[] memory quoteTokens = new address[](1);
        quoteTokens[0] = address(quoteToken);

        vm.prank(admin);
        factory.enable(abi.encode(baseTokens, quoteTokens));

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(baseToken), address(quoteToken))
            .updatedAt;
        assertGt(newTimestamp, oldTimestamp, "Cache timestamp should be refreshed");

        uint256 quoteAmount = IERC7726Oracle(oracle).getQuote(
            1e18,
            address(baseToken),
            address(quoteToken)
        );
        assertEq(quoteAmount, 2e18, "Oracle should be live immediately after re-enable");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
