// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract SetLoanToCollateralCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    event LoanToCollateralSet(uint16 loanToCollateral);

    // given the caller is not an admin
    //  [X] it reverts
    // [X] the loan to collateral is set
    // [X] the event is emitted

    function test_callerNotAdmin(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        clearinghouse.setLoanToCollateral(100);
    }

    function test_success(uint16 loanToCollateral_) public {
        uint16 loanToCollateral = uint16(bound(loanToCollateral_, 0, type(uint16).max));

        // Expect event
        vm.expectEmit();
        emit LoanToCollateralSet(loanToCollateral);

        // Call function
        vm.prank(ADMIN);
        clearinghouse.setLoanToCollateral(loanToCollateral);

        // Assertions
        assertEq(clearinghouse.loanToCollateral(), loanToCollateral);
    }
}
