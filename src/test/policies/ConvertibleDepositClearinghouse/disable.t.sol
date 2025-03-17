// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract DisableCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the caller is not an admin or emergency
    //  [X] it reverts
    // given the contract is not enabled
    //  [X] it reverts
    // [X] the contract is disabled
    // [X] the contract is deactivated in CHREG

    function test_callerNotAdminOrEmergency(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != EMERGENCY);

        // Expect revert
        _expectNotAuthorized();

        // Call function
        vm.prank(caller_);
        clearinghouse.disable("");
    }

    function test_notEnabled() public givenDisabled {
        // Expect revert
        _expectNotEnabled();

        // Call function
        vm.prank(ADMIN);
        clearinghouse.disable("");
    }

    function test_success() public {
        // Call function
        vm.prank(ADMIN);
        clearinghouse.disable("");

        // Assertions
        assertEq(clearinghouse.isEnabled(), false);

        // Assertions on CHREG
        assertEq(CHREG.activeCount(), 0);
        assertEq(CHREG.registryCount(), 1);
        assertEq(CHREG.registry(0), address(clearinghouse));
    }
}
