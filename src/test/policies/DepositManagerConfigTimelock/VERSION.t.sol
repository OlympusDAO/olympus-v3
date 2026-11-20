// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockVersionTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-VERSION-P01.
    function test_whenVersionQueried(address caller_) public {
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _configTimelock.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // Scenarios: DMCT-VERSION-L01.
    function test_givenPausedInactive_whenVersionQueried(address caller_) public {
        _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _configTimelock.VERSION();
        assertEq(major, 1, "major independent of lifecycle");
        assertEq(minor, 0, "minor independent of lifecycle");
    }
}
