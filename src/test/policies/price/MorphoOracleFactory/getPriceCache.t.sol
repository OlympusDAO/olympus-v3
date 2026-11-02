// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";

contract MorphoOracleFactoryGetPriceCacheTest is MorphoOracleFactoryTest {
    function test_whenFactoryIsDeployed_returnsConfiguredPriceCache() public {
        MockPriceCache localCache = new MockPriceCache(address(kernel));
        MorphoOracleFactory localFactory = new MorphoOracleFactory(kernel, address(localCache));
        assertEq(
            localFactory.getPriceCache(),
            address(localCache),
            "Price cache should be set from constructor"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
