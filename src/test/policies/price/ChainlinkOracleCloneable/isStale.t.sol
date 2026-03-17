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

    function test_givenInconsistentTimestamps_returnsTrue(
        uint48 warpDelta_
    ) public givenPricesAreStored {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE * 30));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(baseToken));

        assertEq(oracle.isStale(), true, "Inconsistent timestamps should be treated as stale");
    }

    function test_gasSnapshot_isStale() public givenPricesAreStored {
        vm.startSnapshotGas("ChainlinkOracleCloneable.isStale");
        oracle.isStale();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
