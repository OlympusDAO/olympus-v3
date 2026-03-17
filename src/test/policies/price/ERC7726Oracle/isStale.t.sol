// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";

contract ERC7726OracleIsStaleTest is ERC7726OracleTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, true, "Cache older than maxAge should be stale");
    }

    function test_givenInconsistentTimestamps_returnsTrue(uint48 warpDelta_) public {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE * 30));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(collateralToken));

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, true, "Inconsistent timestamps should be stale");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
