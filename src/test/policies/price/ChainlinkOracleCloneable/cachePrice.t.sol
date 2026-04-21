// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract CachePriceCaller {
    IOracleFactory public factory;

    constructor(IOracleFactory factory_) {
        factory = factory_;
    }

    function cachePrice() external {
        factory.cacheOraclePrices();
    }
}

contract ChainlinkOracleCloneableCachePriceTest is ChainlinkOracleCloneableTest {
    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleDisabled.selector,
                address(oracle)
            )
        );
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenOracleAddressIsInvalid_reverts() public {
        CachePriceCaller caller = new CachePriceCaller(factory);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                address(caller)
            )
        );
        caller.cachePrice();
    }

    function test_whenOracleIsEnabled_cachesDirectPairThroughPriceCache() public {
        MockPriceCache cache = _deployConfiguredPriceCache();

        ChainlinkOracleCloneable(address(oracle)).cachePrice();

        assertEq(cache.cachePriceCallCount(), 1, "Price cache should receive direct cache write");
        assertEq(cache.lastAsset(), address(baseToken), "Asset should match oracle base");
        assertEq(cache.lastQuote(), address(quoteToken), "Quote should match oracle quote");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotRecache() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            cache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(cache.cachePriceCallCount(), 1, "Fresh cache should not be re-cached");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryRecaches() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        ChainlinkOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            cache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(cache.cachePriceCallCount(), 2, "Stale cache should be re-cached");
    }

    function test_whenOracleMaxAgeIsZero_cachePricesIfNecessaryRecachesNextBlock() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        address zeroMaxAgeOracleAddress = _createOracle(address(baseToken), address(quoteToken), 0);
        ChainlinkOracleCloneable zeroMaxAgeOracle = ChainlinkOracleCloneable(
            zeroMaxAgeOracleAddress
        );

        cache.cachePrice(address(baseToken), address(quoteToken));

        vm.warp(block.timestamp + 1);
        zeroMaxAgeOracle.cachePriceIfNecessary();

        assertEq(
            cache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(cache.cachePriceCallCount(), 2, "maxAge=0 should recache pair");
    }

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        ChainlinkOracleCloneable(address(oracle)).cachePrice();
    }

    function _deployConfiguredPriceCache() internal returns (MockPriceCache cache) {
        cache = new MockPriceCache();
        cache.setUsdPrice(address(baseToken), BASE_PRICE);
        cache.setUsdPrice(address(quoteToken), QUOTE_PRICE);
        cache.setPairAllowed(address(baseToken), address(quoteToken), true);

        vm.prank(admin);
        factory.setPriceCache(address(cache));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
