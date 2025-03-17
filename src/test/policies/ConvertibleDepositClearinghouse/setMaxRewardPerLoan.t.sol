// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract SetMaxRewardPerLoanCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    event MaxRewardPerLoanSet(uint256 maxRewardPerLoan);

    // given the caller is not an admin
    //  [X] it reverts
    // [X] the max reward per loan is set
    // [X] the event is emitted

    function test_callerNotAdmin(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        clearinghouse.setMaxRewardPerLoan(100);
    }

    function test_success(uint256 maxRewardPerLoan_) public {
        uint256 maxRewardPerLoan = uint256(bound(maxRewardPerLoan_, 0, type(uint256).max));

        // Expect event
        vm.expectEmit();
        emit MaxRewardPerLoanSet(maxRewardPerLoan);

        // Call function
        vm.prank(ADMIN);
        clearinghouse.setMaxRewardPerLoan(maxRewardPerLoan);

        // Assertions
        assertEq(clearinghouse.maxRewardPerLoan(), maxRewardPerLoan);
    }
}
