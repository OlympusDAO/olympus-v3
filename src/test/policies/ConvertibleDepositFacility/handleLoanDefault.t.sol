// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleLoanDefaultTest is ConvertibleDepositFacilityTest {
    uint256 internal _recipientBalanceBefore;
    uint256 internal _operatorSharesInAssetsBefore;
    uint256 internal _committedDepositsBefore;
    uint256 internal _committedDepositsOperatorBefore;
    uint256 internal _committedDepositsOperatorTwoBefore;

    function _takeSnapshot() internal {
        _recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        _committedDepositsBefore = facility.getCommittedDeposits(iReserveToken);
        _committedDepositsOperatorBefore = facility.getCommittedDeposits(iReserveToken, OPERATOR);
        _committedDepositsOperatorTwoBefore = facility.getCommittedDeposits(
            iReserveToken,
            OPERATOR_TWO
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
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
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
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
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
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // given the payer has not approved the deposit manager to spend the receipt tokens
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
        _expectRevertReceiptTokenInsufficientAllowance(address(depositManager), 0, 1e18);

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
    }

    // [X] it burns the receipt tokens from the payer for the default amount
    // [X] the operator shares remain the same
    // [X] the committed deposits remain the same
    // [X] the committed deposits for the operator remain the same

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, previousDepositActual, recipient)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            previousBorrowActual
        )
    {
        amount_ = bound(amount_, 1, previousBorrowActual);

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, amount_, recipient);

        // Assert that the recipient's balance has decreased by the amount
        assertEq(
            receiptTokenManager.balanceOf(
                recipient,
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS, address(facility))
            ),
            _recipientBalanceBefore - amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have not changed
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertEq(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore,
            "operator shares in assets"
        );

        // Assert that the available deposits have not changed
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            operatorSharesInAssetsAfter - (previousDepositActual - previousBorrowActual),
            "available deposits"
        );

        // Assert that the overall committed deposits are the same
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            _committedDepositsBefore,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator are the same
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            _committedDepositsOperatorBefore,
            "committed deposits for operator"
        );
    }

    // given there are multiple operators
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
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenCommitted(OPERATOR, previousDepositActual)
        givenBorrowed(OPERATOR, previousDepositActual, recipient)
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            previousBorrowActual
        )
    {
        amount_ = bound(amount_, 1, previousBorrowActual);

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
            _commitReceiptToken(OPERATOR_TWO, 1e18);
        }

        _takeSnapshot();

        // Call function
        vm.prank(OPERATOR);
        facility.handleLoanDefault(iReserveToken, PERIOD_MONTHS, amount_, recipient);

        // Assert that the recipient's balance has decreased by the amount
        assertEq(
            receiptTokenManager.balanceOf(
                recipient,
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS, address(facility))
            ),
            _recipientBalanceBefore - amount_,
            "recipient balance"
        );

        // Assert that the operator's shares in assets have not changed
        (, uint256 operatorSharesInAssetsAfter) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertEq(
            operatorSharesInAssetsAfter,
            _operatorSharesInAssetsBefore,
            "operator shares in assets"
        );

        // Assert that the available deposits have not changed
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            operatorSharesInAssetsAfter - (previousDepositActual - previousBorrowActual) - 1e18,
            "available deposits"
        );

        // Assert that the overall committed deposits are the same
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            _committedDepositsBefore,
            "committed deposits"
        );

        // Assert that the committed deposits for the operator are the same
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            _committedDepositsOperatorBefore,
            "committed deposits for operator"
        );

        // Assert that the committed deposits for operator two are the same
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR_TWO),
            _committedDepositsOperatorTwoBefore,
            "committed deposits for operator two"
        );
    }
}
