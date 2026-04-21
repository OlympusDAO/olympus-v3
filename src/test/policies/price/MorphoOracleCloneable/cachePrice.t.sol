// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";
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

contract MorphoOracleCloneableCachePricesTest is MorphoOracleCloneableTest {
    function test_whenOracleIsNotEnabled_reverts() public givenOracleIsDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleDisabled.selector,
                address(oracle)
            )
        );
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrice();
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

        MorphoOracleCloneable(address(oracle)).cachePrice();

        assertEq(cache.cachePriceCallCount(), 1, "Price cache should receive direct cache write");
        assertEq(
            cache.lastAsset(),
            address(collateralToken),
            "Asset should match oracle collateral"
        );
        assertEq(cache.lastQuote(), address(loanToken), "Quote should match oracle loan");
    }

    function test_whenPricesAreFresh_cachePricesIfNecessaryDoesNotRecache() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.cachePrice(address(collateralToken), address(loanToken));

        vm.warp(block.timestamp + 1);
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            cache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(cache.cachePriceCallCount(), 1, "Fresh cache should not be re-cached");
    }

    function test_whenPricesAreStale_cachePricesIfNecessaryRecaches() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.cachePrice(address(collateralToken), address(loanToken));

        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);
        MorphoOracleCloneable(address(oracle)).cachePriceIfNecessary();

        assertEq(
            cache.cachePriceIfNecessaryCallCount(),
            1,
            "Price cache should receive conditional cache call"
        );
        assertEq(cache.cachePriceCallCount(), 2, "Stale cache should be re-cached");
    }

    function test_whenPriceCachePolicyIsDisabled_cachePriceReverts() public {
        MockPriceCache cache = _deployConfiguredPriceCache();
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        MorphoOracleCloneable(address(oracle)).cachePrice();
    }

    function _deployConfiguredPriceCache() internal returns (MockPriceCache cache) {
        cache = new MockPriceCache();
        cache.setUsdPrice(address(collateralToken), 2e18);
        cache.setUsdPrice(address(loanToken), 1e18);
        cache.setPairAllowed(address(collateralToken), address(loanToken), true);

        vm.prank(admin);
        factory.setPriceCache(address(cache));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
