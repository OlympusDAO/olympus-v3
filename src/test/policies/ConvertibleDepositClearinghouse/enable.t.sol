// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract EnableCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the caller is not an admin
    //  [X] it reverts
    // given the contract is already enabled
    //  [X] it reverts
    // [X] the contract is enabled
    // [X] the contract is activated in CHREG

    function test_callerNotAdmin(address caller_) public givenDisabled {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        clearinghouse.enable("");
    }

    function test_alreadyEnabled() public {
        // Expect revert
        _expectNotDisabled();

        // Call function
        vm.prank(ADMIN);
        clearinghouse.enable("");
    }

    function test_success() public givenDisabled {
        // Call function
        vm.prank(ADMIN);
        clearinghouse.enable("");

        // Assertions
        assertEq(clearinghouse.isEnabled(), true);

        // Assertions on CHREG
        assertEq(CHREG.activeCount(), 1);
        assertEq(CHREG.active(0), address(clearinghouse));
        assertEq(CHREG.registryCount(), 1);
        assertEq(CHREG.registry(0), address(clearinghouse));
    }
}
