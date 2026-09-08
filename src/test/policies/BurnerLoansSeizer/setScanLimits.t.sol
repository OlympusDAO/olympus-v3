// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerSetScanLimitsTest is BurnerLoansSeizerTest {
    uint16 internal constant _UPDATED_CHECK_LIMIT = 20;
    uint8 internal constant _UPDATED_SEIZE_LIMIT = 10;
    uint16 internal constant _ALTERNATE_CHECK_LIMIT = 30;
    uint8 internal constant _ALTERNATE_SEIZE_LIMIT = 15;

    // setScanLimits
    // given admin or burner loans admin
    //  when setScanLimits is called
    //   then it sets scan limits
    function test_givenAdminOrBurnerLoansAdmin_setsScanLimits() public {
        vm.prank(admin);
        seizer.setScanLimits(_UPDATED_CHECK_LIMIT, _UPDATED_SEIZE_LIMIT);
        assertEq(seizer.maxBorrowersToCheck(), _UPDATED_CHECK_LIMIT, "admin check limit");
        assertEq(seizer.maxBorrowersToSeize(), _UPDATED_SEIZE_LIMIT, "admin seize limit");

        vm.prank(burnerLoansAdmin);
        seizer.setScanLimits(_ALTERNATE_CHECK_LIMIT, _ALTERNATE_SEIZE_LIMIT);
        assertEq(seizer.maxBorrowersToCheck(), _ALTERNATE_CHECK_LIMIT, "operator check limit");
        assertEq(seizer.maxBorrowersToSeize(), _ALTERNATE_SEIZE_LIMIT, "operator seize limit");
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
        seizer.setScanLimits(_UPDATED_CHECK_LIMIT, _UPDATED_SEIZE_LIMIT);

        assertEq(seizer.maxBorrowersToCheck(), 10, "check limit unchanged");
        assertEq(seizer.maxBorrowersToSeize(), 5, "seize limit unchanged");
    }

    // setScanLimits
    // when both limits are at their minimum accepted value
    //  then the exact lower boundary succeeds
    function test_whenScanLimitsAreAtMinimum_setsScanLimits() public {
        vm.prank(admin);
        seizer.setScanLimits(1, 1);

        assertEq(seizer.maxBorrowersToCheck(), 1, "minimum check limit");
        assertEq(seizer.maxBorrowersToSeize(), 1, "minimum seize limit");
    }

    // setScanLimits
    // when both limits are at their semantic maximum
    //  then the exact upper boundary succeeds
    function test_whenScanLimitsAreAtMaximum_setsScanLimits() public {
        uint16 maximumCheckLimit = seizer.MAX_BORROWERS_TO_CHECK();
        uint8 maximumSeizeLimit = seizer.MAX_BORROWERS_TO_SEIZE();

        vm.prank(admin);
        seizer.setScanLimits(maximumCheckLimit, maximumSeizeLimit);

        assertEq(seizer.maxBorrowersToCheck(), maximumCheckLimit, "maximum check limit");
        assertEq(seizer.maxBorrowersToSeize(), maximumSeizeLimit, "maximum seize limit");
    }

    // setScanLimits
    // given the seizer is disabled
    //  when an authorized caller updates the limits
    //   then configuration remains available while execution is paused
    function test_givenDisabled_setsScanLimits() public {
        vm.prank(admin);
        seizer.disable("");

        vm.prank(burnerLoansAdmin);
        seizer.setScanLimits(_UPDATED_CHECK_LIMIT, _UPDATED_SEIZE_LIMIT);

        assertEq(seizer.maxBorrowersToCheck(), _UPDATED_CHECK_LIMIT, "disabled check limit");
        assertEq(seizer.maxBorrowersToSeize(), _UPDATED_SEIZE_LIMIT, "disabled seize limit");
    }
}
