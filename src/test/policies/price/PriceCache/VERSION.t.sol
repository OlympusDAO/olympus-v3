// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";

contract PriceCacheVersionTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-VERSION-P01.
    function test_whenAnyCallerQueriesVersion(address caller_) public {
        vm.prank(caller_);
        (uint8 major, uint8 minor) = cache.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // Scenarios: PCACHE-VERSION-L01.
    function test_givenInactivePaused_whenVersionQueried(
        address caller_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        vm.prank(caller_);
        (uint8 major, uint8 minor) = cache.VERSION();
        assertEq(major, 1, "major version independent of lifecycle");
        assertEq(minor, 0, "minor version independent of lifecycle");
    }
}
