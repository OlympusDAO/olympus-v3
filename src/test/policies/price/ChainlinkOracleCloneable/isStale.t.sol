// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract ChainlinkOracleCloneableIsStaleTest is ChainlinkOracleCloneableTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public givenPricesAreStored {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(lastStoredTimestamp + warpDelta);

        assertEq(oracle.isStale(), false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(lastStoredTimestamp + warpDelta);

        assertEq(oracle.isStale(), true, "Cache older than maxAge should be stale");
    }

    function test_givenOnlyBaseUsdCacheChanges_returnsFalse(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));

        // Refreshing the base-USD price should not affect the freshness of base-quote price
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(baseToken), 3e18);
        priceCache.cachePrice(address(baseToken), UNIT_OF_ACCOUNT);

        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_givenOnlyQuoteUsdCacheChanges_returnsFalse(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));

        // Refreshing the quote-USD price should not affect the freshness of base-quote price
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(quoteToken), 2e18);
        priceCache.cachePrice(address(quoteToken), UNIT_OF_ACCOUNT);

        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_givenBaseAndQuoteCacheChanges_returnsFalse(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));

        // Refreshing the base-quote price should not make it stale
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(baseToken), 3e18);
        _setPRICEPrices(address(quoteToken), 2e18);
        priceCache.cachePrice(address(baseToken), address(quoteToken));

        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_gasSnapshot_isStale() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.isStale");
        oracle.isStale();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenBaseTokenRemovedFromPRICE_reverts() public givenPricesAreStored {
        priceCache.setAssetApproval(address(baseToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, address(baseToken))
        );
        oracle.isStale();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
