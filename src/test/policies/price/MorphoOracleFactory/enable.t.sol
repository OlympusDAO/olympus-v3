// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";

contract MorphoOracleFactoryEnableTest is MorphoOracleFactoryTest {
    function test_whenEnableDataIsEmpty_succeedsWithoutRecache()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(uint256(oldTimestamp) + uint256(DEFAULT_MAX_AGE) + 1);
        uint256 latestPermissibleTimestamp = block.timestamp - DEFAULT_MAX_AGE;

        vm.prank(admin);
        factory.disable("");

        vm.prank(admin);
        factory.enable("");

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        assertEq(newTimestamp, oldTimestamp, "Cache timestamp should not be refreshed");

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracle.MorphoOracle_Stale.selector,
                oldTimestamp,
                latestPermissibleTimestamp
            )
        );
        IMorphoOracle(oracle).price();
    }

    function test_whenFactoryIsReenabledAndOraclePairCacheIsStale_recachesBeforeOraclesAreLive()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        uint48 oldTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        vm.warp(uint256(oldTimestamp) + uint256(DEFAULT_MAX_AGE) + 1);

        vm.prank(admin);
        factory.disable("");

        address[] memory baseTokens = new address[](1);
        baseTokens[0] = address(collateralToken);
        address[] memory quoteTokens = new address[](1);
        quoteTokens[0] = address(loanToken);

        vm.prank(admin);
        factory.enable(abi.encode(baseTokens, quoteTokens));

        uint48 newTimestamp = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        assertGt(newTimestamp, oldTimestamp, "Cache timestamp should be refreshed");

        uint256 price = IMorphoOracle(oracle).price();
        assertEq(price, 2e36, "Oracle should be live immediately after re-enable");
    }

    function test_whenEnableIncludesUnknownPair_revertsInvalidTokenPair()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        vm.prank(admin);
        factory.disable("");

        address unknownBase = makeAddr("UNKNOWN_BASE");
        address[] memory baseTokens = new address[](1);
        baseTokens[0] = unknownBase;
        address[] memory quoteTokens = new address[](1);
        quoteTokens[0] = address(loanToken);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidTokenPair.selector,
                unknownBase,
                address(loanToken)
            )
        );

        vm.prank(admin);
        factory.enable(abi.encode(baseTokens, quoteTokens));
    }

    function test_whenEnableIncludesFlippedPair_revertsInvalidTokenPair()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        vm.prank(admin);
        factory.disable("");

        address[] memory baseTokens = new address[](1);
        baseTokens[0] = address(loanToken);
        address[] memory quoteTokens = new address[](1);
        quoteTokens[0] = address(collateralToken);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidTokenPair.selector,
                address(loanToken),
                address(collateralToken)
            )
        );

        vm.prank(admin);
        factory.enable(abi.encode(baseTokens, quoteTokens));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
