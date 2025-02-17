// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {MockGohm} from "src/test/mocks/MockGohm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockLender} from "src/test/mocks/MockCallbackLender.sol";

import {Cooler} from "src/external/cooler/Cooler.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

// Tests for Cooler
//
// [X] constructor
//     [X] immutable variables are properly stored
// [X] requestLoan
//     [X] new request is stored
//     [X] user and cooler new collateral balances are correct
// [X] rescindRequest
//     [X] only owner can rescind
//     [X] only active requests can be rescinded
//     [X] request is updated
//     [X] user and cooler new collateral balances are correct
// [X] clearRequest
//     [X] only active requests can be cleared
//     [X] request cleared and a new loan is created
//     [X] user and lender new debt balances are correct
//     [X] callback: only enabled if lender == requester
// [X] repayLoan
//     [X] only possible before expiry
//     [X] loan is updated
//     [X] recipient (lender): new collateral and debt balances are correct
//     [X] recipient (others): new collateral and debt balances are correct
//     [X] callback (true): cannot perform a reentrancy attack
// [X] setRepaymentAddress
//     [X] only the lender can change the recipient
//     [X] loan recipient is properly updated
// [X] extendLoan
//     [X] only possible before expiry
//     [X] only possible by lender
//     [X] loan is properly updated
// [X] claimDefaulted
//     [X] only possible after expiry
//     [X] lender and cooler new collateral balances are correct
// [X] delegateVoting
//     [X] only owner can delegate
//     [X] collateral voting power is properly delegated
// [X] approveTransfer
//     [X] only the lender can approve a transfer
//     [X] approval stored
// [X] transferOwnership
//     [X] only the approved addresses can transfer
//     [X] loan lender and recipient are properly updated

contract CoolerTest is Test {
    MockGohm internal collateral;
    MockERC20 internal debt;

    address owner;
    address lender;
    address others;

    CoolerFactory internal coolerFactory;
    Cooler internal cooler;

    // CoolerFactory Expected events
    event Clear(address cooler, uint256 reqID);
    event Repay(address cooler, uint256 loanID, uint256 amount);
    event Rescind(address cooler, uint256 reqID);
    event Request(address cooler, address collateral, address debt, uint256 reqID);

    // Parameter Bounds
    uint256 public constant INTEREST_RATE = 5e15; // 0.5%
    uint256 public constant LOAN_TO_COLLATERAL = 10 * 1e18; // 10 debt : 1 collateral
    uint256 public constant DURATION = 30 days; // 1 month
    uint256 public constant DECIMALS = 1e18;
    uint256 public constant MAX_DEBT = 5000 * 1e18;
    uint256 public constant MAX_COLLAT = 1000 * 1e18;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Deploy mocks
        collateral = new MockGohm("Collateral", "COLLAT", 18);
        debt = new MockERC20("Debt", "DEBT", 18);

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(3);
        owner = users[0];
        lender = users[1];
        others = users[2];
        deal(address(debt), lender, MAX_DEBT);
        deal(address(debt), others, MAX_DEBT);
        deal(address(collateral), owner, MAX_COLLAT);
        deal(address(collateral), others, MAX_COLLAT);

        // Deploy system contracts
        coolerFactory = new CoolerFactory();
    }

    // -- Helper Functions ---------------------------------------------------

    function _initCooler() internal returns (Cooler) {
        vm.prank(owner);
        return Cooler(coolerFactory.generateCooler(collateral, debt));
    }

    function _requestLoan(uint256 amount_) internal returns (uint256, uint256) {
        uint256 reqCollateral = _collateralFor(amount_);

        vm.startPrank(owner);
        // aprove collateral so that it can be transferred by cooler
        collateral.approve(address(cooler), amount_);
        uint256 reqID = cooler.requestLoan(amount_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);
        vm.stopPrank();
        return (reqID, reqCollateral);
    }

    function _clearLoan(
        uint256 reqID_,
        uint256 reqAmount_,
        bool directRepay_,
        bool callbackRepay_
    ) internal returns (uint256) {
        vm.startPrank(lender);
        // aprove debt so that it can be transferred from the cooler
        debt.approve(address(cooler), reqAmount_);
        // if repayTo == false, don't send repayment to the lender
        address repayTo = (directRepay_) ? lender : others;
        uint256 loanID = cooler.clearRequest(reqID_, repayTo, callbackRepay_);
        vm.stopPrank();
        return loanID;
    }

    function _collateralFor(uint256 amount_) public pure returns (uint256) {
        return (amount_ * DECIMALS) / LOAN_TO_COLLATERAL;
    }

    function _interestFor(
        uint256 amount_,
        uint256 rate_,
        uint256 duration_
    ) public pure returns (uint256) {
        uint256 interest = (rate_ * duration_) / 365 days;
        return (amount_ * interest) / DECIMALS;
    }

    // -- Cooler: Constructor ---------------------------------------------------

    function test_constructor() public {
        vm.prank(owner);
        cooler = Cooler(coolerFactory.generateCooler(collateral, debt));
        assertEq(address(collateral), address(cooler.collateral()));
        assertEq(address(debt), address(cooler.debt()));
        assertEq(address(coolerFactory), address(cooler.factory()));
    }

    // -- REQUEST LOAN ---------------------------------------------------

    function testFuzz_requestLoan(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        uint256 reqCollateral = (amount_ * DECIMALS) / LOAN_TO_COLLATERAL;
        // balances before requesting the loan
        uint256 initOwnerCollateral = collateral.balanceOf(owner);
        uint256 initCoolerCollateral = collateral.balanceOf(address(cooler));

        vm.startPrank(owner);
        // aprove collateral so that it can be transferred by cooler
        collateral.approve(address(cooler), amount_);
        uint256 reqID = cooler.requestLoan(amount_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);
        vm.stopPrank();

        Cooler.Request memory req = cooler.getRequest(reqID);
        // check: request storage
        assertEq(0, reqID);
        assertEq(amount_, req.amount);
        assertEq(INTEREST_RATE, req.interest);
        assertEq(LOAN_TO_COLLATERAL, req.loanToCollateral);
        assertEq(DURATION, req.duration);
        assertEq(true, req.active);
        assertEq(owner, req.requester);
        // check: collateral balances
        assertEq(collateral.balanceOf(owner), initOwnerCollateral - reqCollateral);
        assertEq(collateral.balanceOf(address(cooler)), initCoolerCollateral + reqCollateral);
    }

    // -- RESCIND LOAN ---------------------------------------------------

    function testFuzz_rescindLoan(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        (uint256 reqID, uint256 reqCollateral) = _requestLoan(amount_);
        // balances after requesting the loan
        uint256 initOwnerCollateral = collateral.balanceOf(owner);
        uint256 initCoolerCollateral = collateral.balanceOf(address(cooler));

        vm.prank(owner);
        cooler.rescindRequest(reqID);
        Cooler.Request memory req = cooler.getRequest(reqID);

        // check: request storage
        assertEq(false, req.active);
        // check: collateral balances
        assertEq(collateral.balanceOf(owner), initOwnerCollateral + reqCollateral);
        assertEq(collateral.balanceOf(address(cooler)), initCoolerCollateral - reqCollateral);
    }

    function testFuzz_rescindLoan_multipleRequestAndRecindFirstOne(uint256 amount_) public {
        // test inputs
        uint256 amount1_ = bound(amount_, 0, MAX_DEBT / 3);
        uint256 amount2_ = 2 * amount1_;
        // test setup
        cooler = _initCooler();

        // Request ID = 1
        vm.startPrank(owner);
        // aprove collateral so that it can be transferred by cooler
        collateral.approve(address(cooler), amount1_);
        uint256 reqID1 = cooler.requestLoan(amount1_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);
        vm.stopPrank();

        Cooler.Request memory req1 = cooler.getRequest(reqID1);
        // check: request storage
        assertEq(0, reqID1);
        assertEq(amount1_, req1.amount);
        assertEq(INTEREST_RATE, req1.interest);
        assertEq(LOAN_TO_COLLATERAL, req1.loanToCollateral);
        assertEq(DURATION, req1.duration);
        assertEq(true, req1.active);
        assertEq(owner, req1.requester);

        // Request ID = 2
        vm.startPrank(others);
        // aprove collateral so that it can be transferred by cooler
        collateral.approve(address(cooler), amount2_);
        uint256 reqID2 = cooler.requestLoan(amount2_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);
        vm.stopPrank();

        Cooler.Request memory req2 = cooler.getRequest(reqID2);
        // check: request storage
        assertEq(1, reqID2);
        assertEq(amount2_, req2.amount);
        assertEq(INTEREST_RATE, req2.interest);
        assertEq(LOAN_TO_COLLATERAL, req2.loanToCollateral);
        assertEq(DURATION, req2.duration);
        assertEq(true, req2.active);
        assertEq(others, req2.requester);

        // Rescind Request ID = 1
        vm.prank(owner);
        cooler.rescindRequest(reqID1);

        req1 = cooler.getRequest(reqID1);
        req2 = cooler.getRequest(reqID2);
        // check: request storage
        assertEq(0, reqID1);
        assertEq(amount1_, req1.amount);
        assertEq(INTEREST_RATE, req1.interest);
        assertEq(LOAN_TO_COLLATERAL, req1.loanToCollateral);
        assertEq(DURATION, req1.duration);
        assertEq(false, req1.active);
        assertEq(owner, req1.requester);
        assertEq(1, reqID2);
        assertEq(amount2_, req2.amount);
        assertEq(INTEREST_RATE, req2.interest);
        assertEq(LOAN_TO_COLLATERAL, req2.loanToCollateral);
        assertEq(DURATION, req2.duration);
        assertEq(true, req2.active);
        assertEq(others, req2.requester);
    }

    function testRevertFuzz_rescind_onlyOwner(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);

        // only owner can rescind
        vm.prank(others);
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.rescindRequest(reqID);
    }

    function testRevertFuzz_rescind_onlyActive(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);

        vm.startPrank(owner);
        cooler.rescindRequest(reqID);
        // only possible to rescind active requests
        vm.expectRevert(Cooler.Deactivated.selector);
        cooler.rescindRequest(reqID);
        vm.stopPrank();
    }

    // -- CLEAR REQUEST --------------------------------------------------

    function testFuzz_clearRequest(uint256 amount_, address recipient_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        // balances after requesting the loan
        uint256 initOwnerDebt = debt.balanceOf(owner);
        uint256 initLenderDebt = debt.balanceOf(lender);

        vm.startPrank(lender);
        // aprove debt so that it can be transferred by cooler
        debt.approve(address(cooler), amount_);
        uint256 loanID = cooler.clearRequest(reqID, recipient_, callbackRepay);
        vm.stopPrank();

        Cooler.Request memory request = cooler.getRequest(reqID);
        // check: request storage
        assertEq(false, request.active);

        Cooler.Loan memory loan = cooler.getLoan(loanID);
        // check: loan storage
        assertEq(amount_, loan.principal);
        assertEq(_interestFor(amount_, INTEREST_RATE, DURATION), loan.interestDue);
        assertEq(_collateralFor(amount_), loan.collateral);
        assertEq(block.timestamp + DURATION, loan.expiry);
        assertEq(lender, loan.lender);
        assertEq(recipient_, loan.recipient);
        assertEq(false, loan.callback);

        // check: debt balances
        assertEq(debt.balanceOf(owner), initOwnerDebt + amount_);
        assertEq(debt.balanceOf(lender), initLenderDebt - amount_);
    }

    function testFuzz_clearRequest_callbackFalse(uint256 amount_, address recipient_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);

        vm.startPrank(lender);
        // aprove debt so that it can be transferred by cooler
        debt.approve(address(cooler), amount_);
        uint256 loanID = cooler.clearRequest(reqID, recipient_, callbackRepay);
        vm.stopPrank();

        // since lender doesn't implement callbacks they are not enabled.
        Cooler.Loan memory loan = cooler.getLoan(loanID);
        assertEq(false, loan.callback);
    }

    function testFuzz_clearRequest_callbackTrue_requesterIsNotLender(
        uint256 amount_,
        address recipient_
    ) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);

        vm.startPrank(lender);
        // aprove debt so that it can be transferred by cooler
        debt.approve(address(cooler), amount_);
        uint256 loanID = cooler.clearRequest(reqID, recipient_, callbackRepay);
        vm.stopPrank();

        // since lender isn't the requester (not trusted) callbacks are not enabled.
        Cooler.Loan memory loan = cooler.getLoan(loanID);
        assertEq(false, loan.callback);
    }

    function testRevertFuzz_clearRequest_deactivated(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);

        vm.prank(owner);
        cooler.rescindRequest(reqID);

        vm.startPrank(lender);
        // aprove debt so that it can be transferred by cooler
        debt.approve(address(cooler), amount_);
        // only possible to clear active requests
        vm.expectRevert(Cooler.Deactivated.selector);
        cooler.clearRequest(reqID, lender, callbackRepay);
        vm.stopPrank();
    }

    // -- REPAY LOAN ---------------------------------------------------

    function testFuzz_repayLoan_directTrue_callbackFalse(
        uint256 amount_,
        uint256 repayAmount_
    ) public {
        // test inputs
        repayAmount_ = bound(repayAmount_, 0, MAX_DEBT);
        amount_ = bound(amount_, repayAmount_, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;

        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // cache init vaules
        uint256 decollatAmount;
        uint256 initLoanCollat = _collateralFor(amount_);
        uint256 initInterest = _interestFor(amount_, INTEREST_RATE, DURATION);
        if (repayAmount_ > initInterest) {
            decollatAmount = (initLoanCollat * (repayAmount_ - initInterest)) / amount_;
        } else {
            decollatAmount = 0;
        }

        {
            // block scoping to prevent "stack too deep" compiler error
            // balances after clearing the loan
            uint256 initOwnerDebt = debt.balanceOf(owner);
            uint256 initLenderDebt = debt.balanceOf(lender);
            uint256 initOwnerCollat = collateral.balanceOf(owner);
            uint256 initCoolerCollat = collateral.balanceOf(address(cooler));

            vm.startPrank(owner);
            // aprove debt so that it can be transferred by cooler
            debt.approve(address(cooler), amount_);
            cooler.repayLoan(loanID, repayAmount_);
            vm.stopPrank();

            // check: debt and collateral balances
            assertEq(debt.balanceOf(owner), initOwnerDebt - repayAmount_, "owner: debt balance");
            assertEq(debt.balanceOf(lender), initLenderDebt + repayAmount_, "lender: debt balance");
            assertEq(
                collateral.balanceOf(owner),
                initOwnerCollat + decollatAmount,
                "owner: collat balance"
            );
            assertEq(
                collateral.balanceOf(address(cooler)),
                initCoolerCollat - decollatAmount,
                "cooler: collat balance"
            );
        }

        // compute rest of initial vaules
        uint256 repaidInterest;
        uint256 repaidPrincipal;
        if (repayAmount_ >= initInterest) {
            repaidInterest = initInterest;
            repaidPrincipal = repayAmount_ - initInterest;
        } else {
            repaidInterest = repayAmount_;
            repaidPrincipal = 0;
        }

        Cooler.Loan memory loan = cooler.getLoan(loanID);

        // check: loan storage
        assertEq(initLoanCollat - decollatAmount, loan.collateral, "outstanding collat");
        assertEq(amount_ - repaidPrincipal, loan.principal, "outstanding principal debt");
        assertEq(initInterest - repaidInterest, loan.interestDue, "outstanding interest debt");
    }

    function testFuzz_repayLoan_directFalse_callbackFalse(
        uint256 amount_,
        uint256 repayAmount_
    ) public {
        // test inputs
        repayAmount_ = bound(repayAmount_, 1e10, MAX_DEBT); // min > 0 to have some decollateralization
        amount_ = bound(amount_, repayAmount_, MAX_DEBT);
        bool directRepay = false;
        bool callbackRepay = false;

        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // cache init vaules
        uint256 decollatAmount;
        uint256 initLoanCollat = _collateralFor(amount_);
        uint256 initInterest = _interestFor(amount_, INTEREST_RATE, DURATION);
        if (repayAmount_ > initInterest) {
            decollatAmount = (initLoanCollat * (repayAmount_ - initInterest)) / amount_;
        } else {
            decollatAmount = 0;
        }

        {
            // block scoping to prevent "stack too deep" compiler error
            // balances after clearing the loan
            uint256 initOwnerDebt = debt.balanceOf(owner);
            uint256 initLenderDebt = debt.balanceOf(lender);
            uint256 initOthersDebt = debt.balanceOf(others);

            vm.startPrank(owner);
            // aprove debt so that it can be transferred by cooler
            debt.approve(address(cooler), amount_);
            cooler.repayLoan(loanID, repayAmount_);
            vm.stopPrank();

            // check: debt and collateral balances
            assertEq(debt.balanceOf(owner), initOwnerDebt - repayAmount_, "owner: debt balance");
            assertEq(debt.balanceOf(lender), initLenderDebt, "lender: debt balance");
            assertEq(debt.balanceOf(others), initOthersDebt + repayAmount_, "others: debt balance");
        }

        // compute rest of initial vaules
        uint256 repaidInterest;
        uint256 repaidPrincipal;
        if (repayAmount_ >= initInterest) {
            repaidInterest = initInterest;
            repaidPrincipal = repayAmount_ - initInterest;
        } else {
            repaidInterest = repayAmount_;
            repaidPrincipal = 0;
        }

        Cooler.Loan memory loan = cooler.getLoan(loanID);

        // check: loan storage
        assertEq(initLoanCollat - decollatAmount, loan.collateral, "outstanding collat");
        assertEq(amount_ - repaidPrincipal, loan.principal, "outstanding principal debt");
        assertEq(initInterest - repaidInterest, loan.interestDue, "outstanding interest debt");
    }

    function testRevertFuzz_repayLoan_defaulted(uint256 amount_, uint256 repayAmount_) public {
        // test inputs
        repayAmount_ = bound(repayAmount_, 1e10, MAX_DEBT); // min > 0 to have some decollateralization
        amount_ = bound(amount_, repayAmount_, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // block.timestamp > loan expiry
        vm.warp(block.timestamp + DURATION + 1);

        vm.startPrank(owner);
        // aprove debt so that it can be transferred by cooler
        debt.approve(address(cooler), amount_);
        // can't repay a defaulted loan
        vm.expectRevert(Cooler.Default.selector);
        cooler.repayLoan(loanID, repayAmount_);
        vm.stopPrank();
    }

    // -- SET DIRECT REPAYMENT -------------------------------------------

    function testFuzz_setRepaymentAddress(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.startPrank(lender);
        // turn direct repay off
        cooler.setRepaymentAddress(loanID, address(0));
        Cooler.Loan memory loan = cooler.getLoan(loanID);
        // check: loan storage
        assertEq(address(0), loan.recipient);

        // turn direct repay on
        cooler.setRepaymentAddress(loanID, lender);
        loan = cooler.getLoan(loanID);
        // check: loan storage
        assertEq(lender, loan.recipient);
        vm.stopPrank();
    }

    function testRevertFuzz_setRepaymentAddress_onlyLender(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.prank(others);
        // only lender turn toggle the direct repay
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.setRepaymentAddress(loanID, address(0));
    }

    // -- CLAIM DEFAULTED ------------------------------------------------

    function testFuzz_claimDefaulted(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // block.timestamp > loan expiry
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(lender);
        cooler.claimDefaulted(loanID);

        Cooler.Loan memory loan = cooler.getLoan(loanID);

        // check: loan storage
        // - only amount and collateral are cleared
        assertEq(0, loan.principal);
        assertEq(0, loan.interestDue);
        assertEq(0, loan.collateral);
        // - the rest of the variables are untouched
        assertEq(block.timestamp - 1, loan.expiry);
        assertEq(lender, loan.lender);
        assertEq(lender, loan.recipient);
        assertEq(false, loan.callback);
    }

    function test_claimDefaulted_multipleLoansAndFirstOneDefaults(uint256 amount_) public {
        // test inputs
        uint256 amount1_ = bound(amount_, 0, MAX_DEBT / 3);
        uint256 amount2_ = 2 * amount1_;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        // Request ID = 1
        vm.startPrank(owner);
        collateral.approve(address(cooler), amount1_);
        uint256 reqID1 = cooler.requestLoan(amount1_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);
        vm.stopPrank();
        // Request ID = 2
        vm.startPrank(others);
        collateral.approve(address(cooler), amount2_);
        uint256 reqID2 = cooler.requestLoan(
            amount2_,
            INTEREST_RATE / 2,
            LOAN_TO_COLLATERAL,
            DURATION * 2
        );
        vm.stopPrank();
        // Clear both requests
        vm.startPrank(lender);
        debt.approve(address(cooler), amount1_ + amount2_);
        uint256 loanID1 = cooler.clearRequest(reqID1, lender, callbackRepay);
        uint256 loanID2 = cooler.clearRequest(reqID2, lender, callbackRepay);
        vm.stopPrank();

        // block.timestamp > loan expiry
        vm.warp(block.timestamp + DURATION + 1);

        // claim defaulted loan ID = 1
        vm.prank(lender);
        cooler.claimDefaulted(loanID1);

        Cooler.Loan memory loan1 = cooler.getLoan(loanID1);
        Cooler.Loan memory loan2 = cooler.getLoan(loanID2);

        // check: loan ID = 1 storage
        assertEq(0, loan1.principal, "loanAmount1");
        assertEq(0, loan1.interestDue, "loanInterest1");
        assertEq(0, loan1.collateral, "loanCollat1");
        assertEq(block.timestamp - 1, loan1.expiry, "loanExpiry1");
        assertEq(lender, loan1.lender, "loanLender1");
        assertEq(lender, loan1.recipient, "loanRecipient1");
        assertEq(false, loan1.callback, "loanCallback1");

        // check: loan ID = 2 storage
        assertEq(amount2_, loan2.principal, "loanAmount2");
        assertEq(
            _interestFor(amount2_, INTEREST_RATE / 2, DURATION * 2),
            loan2.interestDue,
            "loanInterest2"
        );
        assertEq(_collateralFor(amount2_), loan2.collateral, "loanCollat2");
        assertEq(51 * 365 * 24 * 60 * 60 + DURATION * 2, loan2.expiry, "loanExpiry2");
        assertEq(lender, loan2.lender, "loanLender2");
        assertEq(lender, loan2.recipient, "loanDirect2");
        assertEq(false, loan2.callback, "loanCallback2");
    }

    function testRevertFuzz_defaulted_notExpired(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // block.timestamp <= loan expiry
        vm.warp(block.timestamp + DURATION);

        vm.prank(lender);
        // can't default a non-expired loan
        vm.expectRevert(Cooler.NotExpired.selector);
        cooler.claimDefaulted(loanID);
    }

    // -- DELEGATE VOTING ------------------------------------------------

    function testFuzz_delegateVoting(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        _requestLoan(amount_);

        vm.prank(owner);
        cooler.delegateVoting(others);
        assertEq(others, collateral.delegates(address(cooler)));
    }

    function testRevertFuzz_delegateVoting_onlyOwner(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        // test setup
        cooler = _initCooler();
        _requestLoan(amount_);

        vm.prank(others);
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.delegateVoting(others);
    }

    // -- APPROVE TRANSFER ---------------------------------------------------

    function testFuzz_approve(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.prank(lender);
        cooler.approveTransfer(others, loanID);

        assertEq(others, cooler.approvals(loanID));
    }

    function testRevertFuzz_approve_onlyLender(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.prank(others);
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.approveTransfer(others, loanID);
    }

    // -- TRANSFER OWNERSHIP ---------------------------------------------

    function testFuzz_transfer(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // the lender approves the transfer
        vm.prank(lender);
        cooler.approveTransfer(others, loanID);
        // the transfer is accepted
        vm.prank(others);
        cooler.transferOwnership(loanID);

        Cooler.Loan memory loan = cooler.getLoan(loanID);
        // check: loan storage
        assertEq(others, loan.lender);
        assertEq(others, loan.recipient);
        assertEq(address(0), cooler.approvals(loanID));
    }

    function testRevertFuzz_transfer_onlyApproved(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.prank(others);
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.transferOwnership(loanID);
    }

    // -- EXTEND LOAN ------------------------------------------------------

    function testFuzz_extendLoanTerms_severalTimes(uint256 amount_, uint8 times_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT / 2);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        vm.warp((block.timestamp + initLoan.expiry) / 2);
        // simulate owner repaying interest to lender before extending the loan.
        // repayment is made using `repayLoan` to alter the `interestDue` and later
        // on assert that extending the loan doesn't touch the interest owed.
        vm.startPrank(owner);
        debt.approve(address(cooler), initLoan.interestDue);
        cooler.repayLoan(loanID, initLoan.interestDue);
        vm.stopPrank();

        Cooler.Loan memory repaidLoan = cooler.getLoan(loanID);

        // cache balances after owner has repaid the interest to the lender
        uint256 initOwnerDebt = debt.balanceOf(owner);
        uint256 initLenderDebt = debt.balanceOf(lender);

        // lender decides to extend the loan
        vm.prank(lender);
        cooler.extendLoanTerms(loanID, times_);

        Cooler.Loan memory extendedloan = cooler.getLoan(loanID);

        // check: debt balances didn't change
        assertEq(debt.balanceOf(owner), initOwnerDebt);
        assertEq(debt.balanceOf(lender), initLenderDebt);
        // check: loan storage
        assertEq(
            extendedloan.expiry,
            repaidLoan.expiry + repaidLoan.request.duration * times_,
            "expiry"
        );
        assertEq(extendedloan.interestDue, repaidLoan.interestDue, "interest");
    }

    function testRevertFuzz_extendLoanTerms_onlyLender(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        vm.prank(owner);
        // only extendable by the lender
        vm.expectRevert(Cooler.OnlyApproved.selector);
        cooler.extendLoanTerms(loanID, 1);
    }

    function testRevertFuzz_extendLoanTerms_defaulted(uint256 amount_) public {
        // test inputs
        amount_ = bound(amount_, 0, MAX_DEBT);
        bool directRepay = true;
        bool callbackRepay = false;
        // test setup
        cooler = _initCooler();
        (uint256 reqID, ) = _requestLoan(amount_);
        uint256 loanID = _clearLoan(reqID, amount_, directRepay, callbackRepay);

        // block.timestamp > loan expiry
        vm.warp(block.timestamp + DURATION * 2 + 1);

        vm.prank(lender);
        // can't extend an expired loan
        vm.expectRevert(Cooler.Default.selector);
        cooler.extendLoanTerms(loanID, 1);
    }
}
