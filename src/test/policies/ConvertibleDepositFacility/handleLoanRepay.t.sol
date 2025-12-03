// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleLoanRepayTest is ConvertibleDepositFacilityTest {
    uint256 internal _recipientBalanceBefore;
    uint256 internal _operatorSharesInAssetsBefore;
    uint256 internal _availableDepositsBefore;
    uint256 internal _committedDepositsBefore;
    uint256 internal _committedDepositsOperatorBefore;
    uint256 public constant BORROW_AMOUNT = 1e18;

    function _takeSnapshot() internal {
        _recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        _availableDepositsBefore = facility.getAvailableDeposits(iReserveToken);
        _committedDepositsBefore = facility.getCommittedDeposits(iReserveToken);
        _committedDepositsOperatorBefore = facility.getCommittedDeposits(iReserveToken, OPERATOR);
    }

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, 1e18, BORROW_AMOUNT, recipient);
    }

    // given the caller is not authorized
    //  [X] it reverts

    function test_givenCallerNotAuthorized_reverts(
        address caller_
    ) public givenLocallyActive givenOperatorAuthorized(OPERATOR) {
        vm.assume(caller_ != OPERATOR);

        // Expect revert
        _expectRevertUnauthorizedOperator(caller_);

        // Call function
        vm.prank(caller_);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, 1e18, BORROW_AMOUNT, recipient);
    }

    // when the amount is less than one share
    //  [X] it reverts

    function test_whenAmountLessThanOneShare_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenVaultHasDeposit(1000e18)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, BORROW_AMOUNT, recipient)
        givenReserveTokenSpendingIsApprovedByRecipient
        givenVaultAccruesYield(iVault, 10_000e18)
    {
        amount_ = bound(amount_, 1, vault.previewMint(1) - 1);

        // Expect revert
        vm.expectRevert("ZERO_SHARES");

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, amount_, BORROW_AMOUNT, recipient);
    }

    // when the amount is greater than the borrowed amount
    //  given there is a second loan
    //   [X] _committedDeposits is increased by the amount repaid, capped at the principal amount of the first loan

    function test_whenAmountGreaterThanBorrowed_givenSecondLoan(
        uint256 amount_
    ) public givenLocallyActive givenOperatorAuthorized(OPERATOR) givenVaultHasDeposit(1000e18) {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, RESERVE_TOKEN_AMOUNT);

        // First loan
        {
            _mintReserveToken(recipient, RESERVE_TOKEN_AMOUNT);
            _approveReserveTokenSpendingByDepositManager(recipient, RESERVE_TOKEN_AMOUNT);
            previousDepositActual = _mintReceiptToken(recipient, RESERVE_TOKEN_AMOUNT);
            _commitReceiptToken(OPERATOR, previousDepositActual);
            vm.prank(OPERATOR);
            previousBorrowActual = facility.handleBorrow(
                iReserveToken,
                PERIOD_MONTHS,
                BORROW_AMOUNT,
                recipient
            );
        }

        // Second loan
        {
            _mintReserveToken(recipient, RESERVE_TOKEN_AMOUNT);
            _approveReserveTokenSpendingByDepositManager(recipient, RESERVE_TOKEN_AMOUNT);
            previousDepositActual = _mintReceiptToken(recipient, RESERVE_TOKEN_AMOUNT);
            _commitReceiptToken(OPERATOR, previousDepositActual);
            vm.prank(OPERATOR);
            previousBorrowActual = facility.handleBorrow(
                iReserveToken,
                PERIOD_MONTHS,
                BORROW_AMOUNT,
                recipient
            );
        }

        // Prepare repayment amount
        {
            _mintReserveToken(recipient, amount_);
            _approveReserveTokenSpendingByDepositManager(recipient, amount_);
        }

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleLoanRepay(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            BORROW_AMOUNT,
            recipient
        );

        // Assert that the recipient's balance has decreased by the amount
        assertEq(
            iReserveToken.balanceOf(recipient),
            _recipientBalanceBefore - amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have increased by the amount
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertApproxEqAbs(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore + actualAmount,
            5,
            "operator shares in assets"
        );

        // Assert that the available deposits have not increased
        // Committed amount increased, borrowed amount decreased
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            _availableDepositsBefore,
            "available deposits"
        );

        // Assert that the overall committed deposits have increased
        // Capped at the principal amount of the first loan
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            _committedDepositsBefore + BORROW_AMOUNT,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator have increased
        // Capped at the principal amount of the first loan
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            _committedDepositsOperatorBefore + BORROW_AMOUNT,
            "committed deposits for operator"
        );
    }

    //  [X] it transfers the tokens from the payer to the deposit manager
    //  [X] it updates the operator shares
    //  [X] it updates the committed deposits
    //  [X] it updates the committed deposits for the operator

    function test_whenAmountGreaterThanBorrowed(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenVaultHasDeposit(1000e18)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, BORROW_AMOUNT, recipient)
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, RESERVE_TOKEN_AMOUNT);

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleLoanRepay(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            BORROW_AMOUNT,
            recipient
        );

        // Assert that the recipient's balance has decreased by the amount
        assertEq(
            iReserveToken.balanceOf(recipient),
            _recipientBalanceBefore - amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have increased by the amount
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertApproxEqAbs(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore + actualAmount,
            5,
            "operator shares in assets"
        );

        // Assert that the available deposits have not increased
        // Committed amount increased, borrowed amount decreased
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            _availableDepositsBefore,
            "available deposits"
        );

        // Assert that the overall committed deposits have increased
        // Capped at the principal amount of the loan
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            _committedDepositsBefore + BORROW_AMOUNT,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator have increased
        // Capped at the principal amount of the loan
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            _committedDepositsOperatorBefore + BORROW_AMOUNT,
            "committed deposits for operator"
        );
    }

    // given the payer has not approved the deposit manager to spend the tokens
    //  [X] it reverts

    function test_givenPayerHasInsufficientAllowance_reverts()
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, BORROW_AMOUNT, recipient)
    {
        // Expect revert
        _expectRevertReserveTokenInsufficientAllowance();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(
            iReserveToken,
            PERIOD_MONTHS,
            BORROW_AMOUNT,
            BORROW_AMOUNT,
            recipient
        );
    }

    // [X] it transfers the tokens from the payer to the deposit manager
    // [X] it updates the operator shares
    // [X] it updates the committed deposits
    // [X] it updates the committed deposits for the operator

    function test_success(
        uint256 amount_,
        uint256 yieldAmount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenVaultHasDeposit(1000e18)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, BORROW_AMOUNT, recipient)
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        amount_ = bound(
            amount_,
            vault.previewMint(1), // At least one share in assets, otherwise it will revert
            BORROW_AMOUNT
        );

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleLoanRepay(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            BORROW_AMOUNT,
            recipient
        );

        // Assert that the recipient's balance has decreased by the amount
        assertEq(
            iReserveToken.balanceOf(recipient),
            _recipientBalanceBefore - amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have increased by the amount
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertApproxEqAbs(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore + actualAmount,
            5,
            "operator shares in assets"
        );

        // Assert that the available deposits have not increased
        // Committed amount increased, borrowed amount decreased
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            _availableDepositsBefore,
            "available deposits"
        );

        // Assert that the overall committed deposits have increased
        // amount_ < BORROW_AMOUNT, so there's no cap
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            _committedDepositsBefore + actualAmount,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator have increased
        // amount_ < BORROW_AMOUNT, so there's no cap
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            _committedDepositsOperatorBefore + actualAmount,
            "committed deposits for operator"
        );
    }
}
