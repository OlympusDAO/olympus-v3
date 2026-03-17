// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableIsStaleTest is MorphoOracleCloneableTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), true, "Cache older than maxAge should be stale");
    }

    function test_givenInconsistentTimestamps_returnsTrue(uint48 warpDelta_) public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE * 30));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(collateralToken));

        assertEq(oracle.isStale(), true, "Inconsistent timestamps should be stale");
    }

    function test_gasSnapshot_isStale() public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.isStale");
        oracle.isStale();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
