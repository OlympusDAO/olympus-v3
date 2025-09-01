// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {FullMath} from "src/libraries/FullMath.sol";

contract DepositRedemptionVaultBorrowAgainstRedemptionTest is DepositRedemptionVaultTest {
    event LoanCreated(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 amount,
        address facility
    );

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // given the redemption id is invalid
    //  [X] it reverts

    function test_givenRedemptionIdIsInvalid_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidRedemptionId(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // given the facility is not authorized
    //  [X] it reverts

    function test_givenFacilityIsNotAuthorized_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenFacilityIsDeauthorized(address(cdFacility))
    {
        // Expect revert
        _expectRevertFacilityNotRegistered(address(cdFacility));

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // given the borrow percentage is 0
    //  [X] it reverts

    function test_givenBorrowPercentageIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenMaxBorrowPercentage(iReserveToken, 0)
    {
        // Expect revert
        _expectRevertMaxBorrowPercentageNotSet(iReserveToken);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // given the interest rate is 0
    //  [X] it reverts

    function test_givenInterestRateIsZero_reverts()
        public
        givenLocallyActive
        givenCommitted(recipient, iReserveToken, PERIOD_MONTHS, COMMITMENT_AMOUNT)
        givenAnnualInterestRate(iReserveToken, 0)
    {
        // Expect revert
        _expectRevertInterestRateNotSet(iReserveToken);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // given there is already a loan against the redemption
    //  [X] it reverts

    function test_givenLoanAlreadyExists_reverts()
        public
        givenLocallyActive
        givenCommittedDefault(COMMITMENT_AMOUNT)
        givenLoan(recipient, 0)
    {
        // Expect revert
        _expectRevertLoanIncorrectState(recipient, 0);

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
    }

    // [X] it creates a new loan record
    // [X] the due date is the deposit period term in the future fro now
    // [X] the principal is the amount specified
    // [X] the interest is the principal * interest rate * deposit period / 12
    // [X] the loan id is 0
    // [X] the total borrowed is the new amount
    // [X] it emits a LoanCreated event
    // [X] it transfers the deposit tokens to the caller
    // [X] the redemption vault retains custody of the receipt tokens

    function test_success(
        uint48 elapsed_
    ) public givenLocallyActive givenCommittedDefault(COMMITMENT_AMOUNT) {
        elapsed_ = uint48(bound(elapsed_, 0, PERIOD_MONTHS * 30 days));
        vm.warp(block.timestamp + elapsed_);

        // Calculations
        uint256 expectedInterest = (LOAN_AMOUNT * 10e2 * PERIOD_MONTHS) / (100e2 * 12);
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanCreated(recipient, 0, LOAN_AMOUNT, address(cdFacility));

        vm.startSnapshotGas("borrowAgainstRedemption");

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        vm.stopSnapshotGas();

        // Assert loan
        _assertLoan(recipient, 0, LOAN_AMOUNT, expectedInterest, false, expectedDueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, LOAN_AMOUNT, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, 0, COMMITMENT_AMOUNT);

        // Assert that the available deposits are correct
        // Deposited amount - committed amount = 0
        _assertAvailableDeposits(0);
    }

    function test_givenOtherDeposits(
        uint48 elapsed_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositTokenDefault(COMMITMENT_AMOUNT)
        givenCommittedDefault(COMMITMENT_AMOUNT)
    {
        elapsed_ = uint48(bound(elapsed_, 0, PERIOD_MONTHS * 30 days));
        vm.warp(block.timestamp + elapsed_);

        // Calculations
        uint256 expectedInterest = (LOAN_AMOUNT * 10e2 * PERIOD_MONTHS) / (100e2 * 12);
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit LoanCreated(recipient, 0, LOAN_AMOUNT, address(cdFacility));

        vm.startSnapshotGas("borrowAgainstRedemption");

        // Call function
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);

        vm.stopSnapshotGas();

        // Assert loan
        _assertLoan(recipient, 0, LOAN_AMOUNT, expectedInterest, false, expectedDueDate);

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, LOAN_AMOUNT, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(recipient, _previousDepositActualAmount, COMMITMENT_AMOUNT);

        // Assert that the available deposits are correct
        // Only the deposit amount for which redemption has not started
        _assertAvailableDeposits(_previousDepositActualAmount);
    }

    function test_givenCommitmentAmountFuzz(
        uint256 commitmentAmount_
    )
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipientTwo,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositTokenDefault(RESERVE_TOKEN_AMOUNT)
        givenVaultAccruesYield(iVault, 3e18) // Ensures that there are rounding inconsistencies when depositing/withdrawing from the vault
    {
        commitmentAmount_ = bound(commitmentAmount_, 1e17, 5e18);
        uint256 expectedLoanAmount = (90e2 * commitmentAmount_) / 100e2;

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        // Expect event
        // 3rd arg is not tracked as it cannot always be predicted
        vm.expectEmit(true, true, true, false);
        emit LoanCreated(recipient, 0, expectedLoanAmount, address(cdFacility));

        vm.startSnapshotGas("borrowAgainstRedemptionCommitmentFuzz");

        // Call function
        vm.prank(recipient);
        uint256 actualLoanAmount = redemptionVault.borrowAgainstRedemption(0);

        vm.stopSnapshotGas();

        // Calculations
        uint256 expectedInterest = FullMath.mulDivUp(
            actualLoanAmount,
            10e2 * PERIOD_MONTHS,
            100e2 * 12
        ); // Post-borrow as we need the actual loan amount
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Assert actual loan amount is as expected
        assertApproxEqAbs(
            actualLoanAmount,
            expectedLoanAmount,
            5,
            "actual loan amount is unexpected"
        );

        // Assert loan record
        _assertLoan(
            recipient,
            0,
            actualLoanAmount,
            actualLoanAmount,
            expectedInterest,
            false,
            expectedDueDate
        );

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, actualLoanAmount, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(
            recipient,
            _previousDepositActualAmount - commitmentAmount_,
            commitmentAmount_
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            actualLoanAmount,
            "getBorrowedAmount"
        );

        // Assert committed funds have been reduced
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            commitmentAmount_ - actualLoanAmount,
            "committed deposits"
        );
    }

    function test_givenCommitmentAmountFuzz_givenYieldAmountFuzz(
        uint256 depositAmount_,
        uint256 commitmentAmount_,
        uint256 yieldAmount_,
        uint256 yieldAmountTwo_
    ) public givenLocallyActive givenVaultHasDeposit(1000e18) {
        depositAmount_ = bound(depositAmount_, 1e18, 50e18);
        commitmentAmount_ = bound(commitmentAmount_, 1e16, depositAmount_ / 2);
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);
        yieldAmountTwo_ = bound(yieldAmountTwo_, 1e16, 50e18);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        // Deposit
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, depositAmount_);

        // Commit funds
        _startRedemption(recipient, iReserveToken, PERIOD_MONTHS, commitmentAmount_);

        uint256 expectedLoanAmount = (90e2 * commitmentAmount_) / 100e2;

        // Expect event
        // 3rd arg is not tracked as it cannot always be predicted
        vm.expectEmit(true, true, true, false);
        emit LoanCreated(recipient, 0, expectedLoanAmount, address(cdFacility));

        vm.startSnapshotGas("borrowAgainstRedemptionCommitmentFuzz");

        // Call function
        vm.prank(recipient);
        uint256 actualLoanAmount = redemptionVault.borrowAgainstRedemption(0);

        vm.stopSnapshotGas();

        // Calculations
        uint256 expectedInterest = FullMath.mulDivUp(
            actualLoanAmount,
            10e2 * PERIOD_MONTHS,
            100e2 * 12
        ); // Post-borrow as we need the actual loan amount
        uint48 expectedDueDate = uint48(block.timestamp + PERIOD_MONTHS * 30 days);

        // Assert actual loan amount is as expected
        assertApproxEqAbs(
            actualLoanAmount,
            expectedLoanAmount,
            5,
            "actual loan amount is unexpected"
        );

        // Assert loan record
        _assertLoan(
            recipient,
            0,
            actualLoanAmount,
            actualLoanAmount,
            expectedInterest,
            false,
            expectedDueDate
        );

        // Assert deposit token balances
        _assertDepositTokenBalances(recipient, actualLoanAmount, 0, 0);

        // Assert receipt token balances
        _assertReceiptTokenBalances(
            recipient,
            _previousDepositActualAmount - commitmentAmount_,
            commitmentAmount_
        );

        // Assert borrowed amount on DepositManager
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(cdFacility)),
            actualLoanAmount,
            "getBorrowedAmount"
        );

        // Assert committed funds have been reduced
        assertEq(
            cdFacility.getCommittedDeposits(iReserveToken, address(redemptionVault)),
            commitmentAmount_ - actualLoanAmount,
            "committed deposits"
        );
    }
}
