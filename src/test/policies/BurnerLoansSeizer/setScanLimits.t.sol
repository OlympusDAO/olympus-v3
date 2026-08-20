// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerSetScanLimitsTest is BurnerLoansSeizerTest {
    // setScanLimits
    // given admin or burner loans admin
    //  when setScanLimits is called
    //   then it sets scan limits
    function test_givenAdminOrBurnerLoansAdmin_setsScanLimits() public {
        vm.prank(admin);
        seizer.setScanLimits(20, 10);
        assertEq(seizer.maxBorrowersToCheck(), 20, "admin check limit");
        assertEq(seizer.maxBorrowersToSeize(), 10, "admin seize limit");

        vm.prank(burnerLoansAdmin);
        seizer.setScanLimits(30, 15);
        assertEq(seizer.maxBorrowersToCheck(), 30, "operator check limit");
        assertEq(seizer.maxBorrowersToSeize(), 15, "operator seize limit");
    }

    // setScanLimits
    // given invalid scan limits
    //  when setScanLimits is called
    //   then it reverts
    function test_givenInvalidScanLimits_reverts(uint16 checkLimit_, uint8 seizeLimit_) public {
        bool invalid = checkLimit_ == 0 ||
            checkLimit_ > seizer.MAX_BORROWERS_TO_CHECK() ||
            seizeLimit_ == 0 ||
            seizeLimit_ > seizer.MAX_BORROWERS_TO_SEIZE() ||
            seizeLimit_ > checkLimit_;
        vm.assume(invalid);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidScanLimits.selector,
                checkLimit_,
                seizeLimit_
            )
        );
        vm.prank(admin);
        seizer.setScanLimits(checkLimit_, seizeLimit_);
    }

    // setScanLimits
    // given unauthorized caller
    //  when setScanLimits is called
    //   then it reverts without changing configuration
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        seizer.setScanLimits(20, 10);

        assertEq(seizer.maxBorrowersToCheck(), 10, "check limit unchanged");
        assertEq(seizer.maxBorrowersToSeize(), 5, "seize limit unchanged");
    }
}
