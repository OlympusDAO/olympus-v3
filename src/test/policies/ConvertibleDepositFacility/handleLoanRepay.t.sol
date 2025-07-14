// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleLoanRepayTest is ConvertibleDepositFacilityTest {
    uint256 internal _recipientBalanceBefore;
    uint256 internal _operatorSharesInAssetsBefore;

    function _takeSnapshot() internal {
        _recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
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
        givenBorrowed(OPERATOR, previousDepositActual, recipient)
    {
        amount_ = bound(amount_, previousBorrowActual + 1, type(uint256).max);

        // Expect revert
        _expectRevertExceedsBorrowed(amount_, previousBorrowActual);

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
        givenBorrowed(OPERATOR, previousDepositActual, recipient)
    {
        // Expect revert
        _expectRevertReserveTokenInsufficientAllowance();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanRepay(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
    }

    // [X] it transfers the tokens from the payer to the deposit manager
    // [X] it updates the operator shares

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, previousDepositActual, recipient)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            previousBorrowActual
        )
    {
        amount_ = bound(amount_, 1, previousBorrowActual);

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
        assertEq(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore + amount_,
            "operator shares in assets"
        );

        // Assert that the available deposits have increased by the amount
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            operatorSharesInAssetsAfter - (previousDepositActual - previousBorrowActual + amount_),
            "available deposits"
        );
    }
}
