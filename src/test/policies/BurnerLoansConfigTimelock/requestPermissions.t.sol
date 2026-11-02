// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";

contract BurnerLoansConfigTimelockRequestPermissionsTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-PERMISSIONS-P01.
    function test_givenEachLifecycleState_whenPermissionsRead_thenEmpty(address caller_) public {
        vm.prank(caller_);
        assertEq(_timelock.requestPermissions().length, 0, "Active permissions empty");
        _timelock.disable("");
        vm.prank(caller_);
        assertEq(_timelock.requestPermissions().length, 0, "Disabled permissions empty");
        _setState(_timelock, false, true);
        vm.prank(caller_);
        assertEq(_timelock.requestPermissions().length, 0, "Inactive permissions empty");
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        vm.prank(caller_);
        assertEq(fresh.requestPermissions().length, 0, "Before activation empty");
        vm.prank(address(_kernel));
        fresh.changeKernel(Kernel(address(0)));
        vm.prank(caller_);
        assertEq(fresh.requestPermissions().length, 0, "After migration empty");
    }
}
