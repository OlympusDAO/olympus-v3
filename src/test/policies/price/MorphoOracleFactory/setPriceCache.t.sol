// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract MorphoOracleFactorySetPriceCacheTest is MorphoOracleFactoryTest {
    function test_whenCallerIsAdmin_setsPriceCache() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache();

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
