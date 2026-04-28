// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";

contract MorphoOracleFactoryGetPriceCacheTest is MorphoOracleFactoryTest {
    MockPriceCache internal _localCache;
    MorphoOracleFactory internal _localFactory;

    modifier givenPriceCacheAndFactory() {
        _localCache = new MockPriceCache(address(kernel));
        _localFactory = new MorphoOracleFactory(kernel, address(_localCache));
        _;
    }

    function test_whenFactoryIsDeployed_returnsConfiguredPriceCache()
        public
        givenPriceCacheAndFactory
    {
        assertEq(
            _localFactory.getPriceCache(),
            address(_localCache),
            "Price cache should be set from constructor"
        );
    }

    function test_whenPriceCacheIsUpdated_returnsUpdatedPriceCache() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache(address(kernel));

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
