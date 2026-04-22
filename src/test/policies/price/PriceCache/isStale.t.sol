// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheIsStaleTest is PriceCacheTest {
    function test_whenNoSnapshotExists_returnsTrue() public view {
        bool stale = cache.isStale(address(assetToken), address(quoteToken), 1 hours);
        assertEq(stale, true, "Missing snapshot should be stale");
    }

    function test_whenSnapshotIsFresh_returnsFalse(uint48 maxAge_, uint48 elapsed_) public {
        _cachePair();
        uint48 updatedAt = _cachedPair().updatedAt;

        maxAge_ = uint48(bound(uint256(maxAge_), 1, 365 days));
        elapsed_ = uint48(bound(uint256(elapsed_), 0, maxAge_));

        vm.warp(uint256(updatedAt) + uint256(elapsed_));
        bool stale = cache.isStale(address(assetToken), address(quoteToken), maxAge_);
        assertEq(stale, false, "Fresh snapshot should not be stale");
    }

    function test_whenSnapshotIsOlderThanMaxAge_returnsTrue(
        uint48 maxAge_,
        uint48 additionalAge_
    ) public {
        _cachePair();
        uint48 updatedAt = _cachedPair().updatedAt;

        maxAge_ = uint48(bound(uint256(maxAge_), 0, 365 days));
        additionalAge_ = uint48(bound(uint256(additionalAge_), 1, 365 days));

        vm.warp(uint256(updatedAt) + uint256(maxAge_) + uint256(additionalAge_));
        bool stale = cache.isStale(address(assetToken), address(quoteToken), maxAge_);
        assertEq(stale, true, "Snapshot older than maxAge should be stale");
    }

    function test_whenPRICEModuleIsUpgraded_returnsTrue() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        bool stale = cache.isStale(address(assetToken), address(quoteToken), 365 days);
        assertEq(stale, true, "Module upgrade should invalidate snapshot and report stale");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
