// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleLoanRepayTest is ConvertibleDepositFacilityTest {
    uint256 internal _recipientBalanceBefore;
    uint256 internal _operatorSharesInAssetsBefore;
    uint256 internal _availableDepositsBefore;
    uint256 public constant BORROW_AMOUNT = 1e18;

    function _takeSnapshot() internal {
        _recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        _availableDepositsBefore = facility.getAvailableDeposits(iReserveToken);
    }

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
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
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
    }

    // when the amount is greater than the borrowed amount
    //  [X] it reverts

    function test_whenAmountGreaterThanBorrowed_reverts(
        uint256 amount_
    )
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
        amount_ = bound(amount_, BORROW_AMOUNT + 1, type(uint256).max);

        // Expect revert
        _expectRevertExceedsBorrowed(amount_, BORROW_AMOUNT);

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, amount_, recipient);
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
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, BORROW_AMOUNT, recipient);
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
        amount_ = bound(
            amount_,
            5, // 1 risks a ZERO_SHARES error
            BORROW_AMOUNT
        );
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, amount_, recipient);

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
            _operatorSharesInAssetsBefore + amount_,
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
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            previousDepositActual - BORROW_AMOUNT + amount_,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator have increased
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            previousDepositActual - BORROW_AMOUNT + amount_,
            "committed deposits for operator"
        );
    }
}
