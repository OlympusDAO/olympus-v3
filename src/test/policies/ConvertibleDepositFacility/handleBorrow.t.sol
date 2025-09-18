// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract ConvertibleDepositFacilityHandleBorrowTest is ConvertibleDepositFacilityTest {
    uint256 public constant COMMIT_AMOUNT = 1e18;
    uint256 public constant BORROW_AMOUNT = 1e18;

    // ========== TESTS ========== //
    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, BORROW_AMOUNT, recipient);
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
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, BORROW_AMOUNT, recipient);
    }

    // when the amount is greater than the available deposits
    //  [X] it reverts

    function test_whenAmountGreaterThanAvailableDeposits_reverts(
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
    {
        amount_ = bound(amount_, previousDepositActual + 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR, amount_, previousDepositActual);

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // when the amount is greater than the committed funds
    //  [X] it reverts

    function test_whenAmountGreaterThanCommittedFunds_reverts(
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
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, COMMIT_AMOUNT + 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR, amount_, COMMIT_AMOUNT);

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // [X] it transfers the tokens to the recipient
    // [X] it reduces the operator shares
    // [X] it reduces the available deposits
    // [X] it reduces the committed deposits for the facility
    // [X] it reduces the committed deposits for the operator

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
    {
        amount_ = bound(amount_, BORROW_AMOUNT, previousDepositActual);
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        // Accrue yield
        _accrueYield(iVault, yieldAmount_);

        uint256 recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, uint256 operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        uint256 availableDepositsBefore = facility.getAvailableDeposits(iReserveToken);

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleBorrow(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            recipient
        );

        // Assert that the actual amount is the amount
        assertApproxEqAbs(actualAmount, amount_, 5, "actual amount");

        // Assert that the recipient's balance has increased by the actual amount
        assertEq(
            iReserveToken.balanceOf(recipient),
            recipientBalanceBefore + actualAmount,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have decreased by the amount
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertApproxEqAbs(
            operatorSharesInAssetsAfter,
            operatorSharesInAssetsBefore - amount_,
            5,
            "operator shares in assets"
        );

        // Assert that the available deposits remains the same
        // Committed deposits reduced, borrowed amount increased
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            availableDepositsBefore,
            "available deposits"
        );

        // Assert that the committed deposits have decreased by the amount
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            previousDepositActual - amount_,
            "committed deposits"
        );
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            previousDepositActual - amount_,
            "committed deposits for operator"
        );
    }

    // given multiple operators have commitments
    //  when an operator attempts to borrow more than committed
    //   [X] it reverts

    function test_multipleOperators_whenAmountGreaterThanCommittedFunds_reverts(
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
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, COMMIT_AMOUNT + 1, type(uint256).max);

        // Perform actions for the second operator
        // Doing it here to avoid stack too deep
        {
            // Authorise operator
            vm.prank(admin);
            facility.authorizeOperator(OPERATOR_TWO);

            // Mint, approve, deposit
            _mintReserveToken(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);
            _approveReserveTokenSpendingByDepositManager(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);
            _mintReceiptToken(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);

            // Commit
            _commitReceiptToken(OPERATOR_TWO, COMMIT_AMOUNT);

            previousDepositActual = receiptTokenManager.balanceOf(OPERATOR, receiptTokenId);
        }

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR, amount_, COMMIT_AMOUNT);

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    //  [X] it transfers the tokens to the recipient
    //  [X] it reduces the operator shares
    //  [X] it reduces the available deposits
    //  [X] it reduces the committed deposits for the facility
    //  [X] it reduces the committed deposits for the operator
    //  [X] it does not change the committed deposit for operator two

    function test_multipleOperators(
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
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMIT_AMOUNT);

        // Perform actions for the second operator
        // Doing it here to avoid stack too deep
        {
            // Authorise operator
            vm.prank(admin);
            facility.authorizeOperator(OPERATOR_TWO);

            // Mint, approve, deposit
            _mintReserveToken(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);
            _approveReserveTokenSpendingByDepositManager(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);
            _mintReceiptToken(OPERATOR_TWO, RESERVE_TOKEN_AMOUNT);

            // Commit
            _commitReceiptToken(OPERATOR_TWO, COMMIT_AMOUNT);
        }

        uint256 recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, uint256 operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        uint256 availableDepositsBefore = facility.getAvailableDeposits(iReserveToken);

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleBorrow(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            recipient
        );

        // Assert that the actual amount is the amount
        assertEq(actualAmount, amount_, "actual amount");

        // Assert that the recipient's balance has increased by the amount
        assertEq(
            iReserveToken.balanceOf(recipient),
            recipientBalanceBefore + amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have decreased by the amount
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertApproxEqAbs(
            operatorSharesInAssetsAfter,
            operatorSharesInAssetsBefore - amount_,
            5,
            "operator shares in assets"
        );

        // Assert that the available deposits remains the same
        // Committed deposits reduced, borrowed amount increased
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            availableDepositsBefore,
            "available deposits"
        );

        // Assert that the committed deposits have decreased by the amount
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            COMMIT_AMOUNT * 2 - amount_,
            "committed deposits"
        );
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            COMMIT_AMOUNT - amount_,
            "committed deposits for operator"
        );
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR_TWO),
            COMMIT_AMOUNT,
            "committed deposits for operator two"
        );
    }
}
