// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";

contract PriceCacheDecimalsTest is PriceCacheTest {
    // Scenarios: PCACHE-DECIMALS-P01.
    function test_returnsPriceModuleUsdScale() public view {
        assertEq(cache.decimals(), PRICE_DECIMALS, "Cache decimals should match PRICE decimals");
    }

    // Scenarios: PCACHE-DECIMALS-P02.
    function test_whenPRICEDecimalsChange_returnsUpdatedScale() public {
        priceModule.setPriceDecimals(UPDATED_PRICE_DECIMALS);
        assertEq(
            cache.decimals(),
            UPDATED_PRICE_DECIMALS,
            "Cache decimals should track updated PRICE decimals"
        );
    }

    // Scenarios: PCACHE-DECIMALS-P03.
    function test_whenPRICEModuleIsUpgraded_returnsNewModuleScale() public {
        _upgradePriceModuleAndReconfigure(UPDATED_PRICE_DECIMALS);
        assertEq(
            cache.decimals(),
            UPDATED_PRICE_DECIMALS,
            "Cache decimals should reflect upgraded PRICE module"
        );
    }

    // Scenarios: PCACHE-DECIMALS-L01.
    function test_givenInactivePaused_whenDecimalsQueried(
        address caller_
    ) public givenCachePaused givenCacheInactive {
        vm.prank(caller_);
        assertEq(cache.decimals(), 18, "PRICE scale stays readable");
    }

    // Scenarios: PCACHE-DECIMALS-N01.
    function test_whenPriceScaleSpansUint8(address caller_, uint8 decimals_) public {
        priceModule.setPriceDecimals(decimals_);
        vm.prank(caller_);
        assertEq(cache.decimals(), decimals_, "exact module scale");
    }

    // Scenarios: PCACHE-DECIMALS-N01.
    function test_whenPriceScaleBoundarySeeds() public {
        test_whenPriceScaleSpansUint8(address(this), 0);
        test_whenPriceScaleSpansUint8(address(this), 1);
        test_whenPriceScaleSpansUint8(address(this), type(uint8).max);
    }

    // Scenarios: PCACHE-DECIMALS-T01.
    function test_whenPriceScaleReadFails_reverts() public {
        vm.mockCallRevert(
            address(priceModule),
            abi.encodeWithSignature("decimals()"),
            abi.encodeWithSelector(MetadataReadFailed.selector)
        );
        vm.expectRevert(MetadataReadFailed.selector);
        cache.decimals();
    }

    // Scenarios: PCACHE-DECIMALS-T01.
    function test_givenUnconfigured_whenDecimalsQueried_reverts() public {
        PriceCache fresh = new PriceCache(kernel, 18, "USD");
        _expectMetadataAbiFailure();
        fresh.decimals();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
