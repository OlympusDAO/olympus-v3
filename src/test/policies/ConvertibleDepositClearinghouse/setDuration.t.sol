// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract SetDurationCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    event DurationSet(uint48 duration);

    // given the caller is not an admin
    //  [X] it reverts
    // [X] the duration is set
    // [X] the event is emitted

    function test_callerNotAdmin(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        clearinghouse.setDuration(100);
    }

    function test_success(uint48 duration_) public {
        uint48 duration = uint48(bound(duration_, 0, type(uint48).max));

        // Expect event
        vm.expectEmit();
        emit DurationSet(duration);

        // Call function
        vm.prank(ADMIN);
        clearinghouse.setDuration(duration);

        // Assertions
        assertEq(clearinghouse.duration(), duration);
    }
}
