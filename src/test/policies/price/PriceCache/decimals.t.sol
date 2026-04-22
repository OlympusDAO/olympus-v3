// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheDecimalsTest is PriceCacheTest {
    function test_returnsPriceModuleUsdScale() public view {
        assertEq(cache.decimals(), 18, "Cache decimals should match PRICE decimals");
    }

    function test_whenPRICEDecimalsChange_returnsUpdatedScale() public {
        priceModule.setPriceDecimals(9);
        assertEq(cache.decimals(), 9, "Cache decimals should track updated PRICE decimals");
    }

    function test_whenPRICEModuleIsUpgraded_returnsNewModuleScale() public {
        _upgradePriceModuleAndReconfigure(9);
        assertEq(cache.decimals(), 9, "Cache decimals should reflect upgraded PRICE module");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
