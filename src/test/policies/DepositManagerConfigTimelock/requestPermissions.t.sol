// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Permissions} from "src/Kernel.sol";

contract DepositManagerConfigTimelockRequestPermissionsTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-PERMISSIONS-P01.
    function test_whenPermissionsRequested(address caller_) public {
        vm.prank(caller_);
        Permissions[] memory permissions = _configTimelock.requestPermissions();
        assertEq(
            permissions.length,
            0,
            "configuration uses delegated operator authority, not module permissions"
        );
    }

    // Scenarios: DMCT-PERMISSIONS-L01.
    function test_givenPausedInactive_whenPermissionsRequested(address caller_) public {
        _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        vm.prank(caller_);
        Permissions[] memory permissions = _configTimelock.requestPermissions();
        assertEq(permissions.length, 0, "permission discovery independent of lifecycle");
    }
}
