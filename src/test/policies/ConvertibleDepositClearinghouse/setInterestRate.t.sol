// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract SetInterestRateCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    event InterestRateSet(uint256 interestRate);

    // given the caller is not an admin
    //  [X] it reverts
    // [X] the interest rate is set
    // [X] the event is emitted

    function test_callerNotAdmin(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        clearinghouse.setInterestRate(100);
    }

    function test_success(uint256 interestRate_) public {
        uint256 interestRate = uint256(bound(interestRate_, 0, type(uint256).max));

        // Expect event
        vm.expectEmit();
        emit InterestRateSet(interestRate);

        // Call function
        vm.prank(ADMIN);
        clearinghouse.setInterestRate(interestRate);

        // Assertions
        assertEq(clearinghouse.interestRate(), interestRate);
    }
}
