// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";

contract PriceCacherTaskVersionTest is PriceCacherTaskTest {
    // Scenarios: PCACHER-VERSION-P01.
    function test_whenAnyCallerQueriesVersion(address caller_) public {
        vm.record();
        vm.prank(caller_);
        (uint8 major, uint8 minor) = cacher.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
        (, bytes32[] memory writes) = vm.accesses(address(cacher));
        assertEq(writes.length, 0, "version writes nothing");
    }

    // Scenarios: PCACHER-VERSION-L01.
    function test_givenInactivePaused_whenVersionQueried(address caller_) public {
        vm.prank(admin);
        cacher.disable("");
        _setTaskMembership(false);
        vm.mockCallRevert(address(priceCache), bytes(""), hex"deadbeef");
        test_whenAnyCallerQueriesVersion(caller_);
    }
}
