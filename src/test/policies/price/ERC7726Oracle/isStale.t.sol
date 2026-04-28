// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

contract ERC7726OracleIsStaleTest is ERC7726OracleTest {
    // given the cache is fresh
    //  [X] it returns false

    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Fresh cache should not be stale");
    }

    // given the cache is older than maxAge
    //  [X] it returns true

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, true, "Cache older than maxAge should be stale");
    }

    // given only the base/USD cache changes
    //  [X] it returns false

    function test_givenOnlyBaseUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 pairTimestampBefore = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);
        uint48 pairTimestampAfter = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(
            pairTimestampAfter,
            pairTimestampBefore,
            "Direct pair timestamp should not change when only base/USD is refreshed"
        );
        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    // given only the quote/USD cache changes
    //  [X] it returns false

    function test_givenOnlyQuoteUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 pairTimestampBefore = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);
        uint48 pairTimestampAfter = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(
            pairTimestampAfter,
            pairTimestampBefore,
            "Direct pair timestamp should not change when only quote/USD is refreshed"
        );
        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    // given both base/USD and quote/USD caches change
    //  [X] it returns false

    function test_givenBaseAndQuoteUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 pairTimestampBefore = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        _setPRICEPrices(address(collateralToken), 3e18);
        _setPRICEPrices(address(loanToken), 2e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);
        uint48 pairTimestampAfter = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(
            pairTimestampAfter,
            pairTimestampBefore,
            "Direct pair timestamp should not change when only USD legs are refreshed"
        );
        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    function test_gasSnapshot_isStale() public {
        vm.startSnapshotGas("ERC7726OracleCloneable.isStale");
        oracle.isStale(address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    // given the base asset is not approved
    //  [X] it reverts

    function test_givenBaseAssetIsNotApproved_reverts() public {
        address unapprovedBase = makeAddr("UNAPPROVED_BASE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedBase));
        oracle.isStale(unapprovedBase, address(loanToken));
    }

    // given the quote asset is not approved
    //  [X] it reverts

    function test_givenQuoteAssetIsNotApproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, unapprovedQuote));
        oracle.isStale(address(collateralToken), unapprovedQuote);
    }

    // given the base asset is unit of account
    //  [X] it returns false
    //  [X] given the cache is older than maxAge, it returns true

    function test_givenBaseAssetIsUnitOfAccount_returnsFalse() public {
        priceCache.cachePrice(UNIT_OF_ACCOUNT, address(loanToken));

        bool stale = oracle.isStale(UNIT_OF_ACCOUNT, address(loanToken));
        assertEq(stale, false, "Unit-of-account pair should be fresh");
    }

    function test_givenBaseAssetIsUnitOfAccount_givenCacheOlderThanMaxAge_returnsTrue() public {
        priceCache.cachePrice(UNIT_OF_ACCOUNT, address(loanToken));
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        bool stale = oracle.isStale(UNIT_OF_ACCOUNT, address(loanToken));
        assertEq(stale, true, "Unit-of-account pair should be stale");
    }

    // given the quote asset is unit of account
    //  [X] it returns false
    //  [X] given the cache is older than maxAge, it returns true

    function test_givenQuoteAssetIsUnitOfAccount_returnsFalse() public {
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);

        bool stale = oracle.isStale(address(collateralToken), UNIT_OF_ACCOUNT);
        assertEq(stale, false, "Unit-of-account pair should be fresh");
    }

    function test_givenQuoteAssetIsUnitOfAccount_givenCacheOlderThanMaxAge_returnsTrue() public {
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        bool stale = oracle.isStale(address(collateralToken), UNIT_OF_ACCOUNT);
        assertEq(stale, true, "Unit-of-account pair should be stale");
    }

    // given the base asset is a registered non-contract asset
    //  given non-contract asset decimals are not set
    //   [X] it reverts
    //  given non-contract asset decimals are set
    //   [X] it returns false
    //   [X] given the cache is older than maxAge, it returns true
    //  given the asset is no longer approved in PRICE
    //   [X] it reverts

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreNotSet_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        priceCache.removeNonContractAssetMetadata(registeredNonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );
        oracle.isStale(registeredNonContractAsset, address(loanToken));
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_returnsFalse()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));

        bool stale = oracle.isStale(registeredNonContractAsset, address(loanToken));
        assertEq(stale, false, "Registered non-contract asset pair should be fresh");
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_givenCacheOlderThanMaxAge_returnsTrue()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        bool stale = oracle.isStale(registeredNonContractAsset, address(loanToken));
        assertEq(stale, true, "Registered non-contract asset pair should be stale");
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenMetadataIsUpdated_returnsTrue()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));

        priceCache.setNonContractAssetMetadata(registeredNonContractAsset, 9, "NCA2");

        bool stale = oracle.isStale(registeredNonContractAsset, address(loanToken));
        assertEq(stale, true, "Metadata updates should invalidate cached base-asset pairs");
    }

    // given the quote asset is a registered non-contract asset
    //  given non-contract asset decimals are not set
    //   [X] it reverts
    //  given non-contract asset decimals are set
    //   [X] it returns false
    //   [X] given the cache is older than maxAge, it returns true
    //  given the asset is no longer approved in PRICE
    //   [X] it reverts

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreNotSet_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        priceCache.removeNonContractAssetMetadata(registeredNonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                registeredNonContractAsset
            )
        );
        oracle.isStale(address(collateralToken), registeredNonContractAsset);
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_returnsFalse()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);

        bool stale = oracle.isStale(address(collateralToken), registeredNonContractAsset);
        assertEq(stale, false, "Registered non-contract asset pair should be fresh");
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenNonContractAssetDecimalsAreSet_givenCacheOlderThanMaxAge_returnsTrue()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        bool stale = oracle.isStale(address(collateralToken), registeredNonContractAsset);
        assertEq(stale, true, "Registered non-contract asset pair should be stale");
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenMetadataIsUpdated_returnsTrue()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);

        priceCache.setNonContractAssetMetadata(registeredNonContractAsset, 9, "NCA2");

        bool stale = oracle.isStale(address(collateralToken), registeredNonContractAsset);
        assertEq(stale, true, "Metadata updates should invalidate cached quote-asset pairs");
    }

    function test_givenBaseAssetIsRegisteredNonContractAsset_givenAssetIsNoLongerApprovedInPRICE_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(registeredNonContractAsset, address(loanToken));
        priceCache.setAssetApproval(registeredNonContractAsset, false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, registeredNonContractAsset)
        );
        oracle.isStale(registeredNonContractAsset, address(loanToken));
    }

    function test_givenQuoteAssetIsRegisteredNonContractAsset_givenAssetIsNoLongerApprovedInPRICE_reverts()
        public
    {
        _setPRICEPrices(registeredNonContractAsset, 3e18);
        _setNonContractAssetMetadata(registeredNonContractAsset, 8, "NCA");
        priceCache.cachePrice(address(collateralToken), registeredNonContractAsset);
        priceCache.setAssetApproval(registeredNonContractAsset, false);

        vm.expectRevert(
            abi.encodeWithSelector(PRICE_ASSET_NOT_APPROVED_SELECTOR, registeredNonContractAsset)
        );
        oracle.isStale(address(collateralToken), registeredNonContractAsset);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
