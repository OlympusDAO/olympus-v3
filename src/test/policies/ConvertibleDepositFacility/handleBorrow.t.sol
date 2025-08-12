// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract ConvertibleDepositFacilityHandleBorrowTest is ConvertibleDepositFacilityTest {
    // ========== TESTS ========== //
    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
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
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, 1e18, recipient);
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

    // [X] it transfers the tokens to the recipient
    // [X] it updates the operator shares

    function test_success(
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
        amount_ = bound(amount_, 1e18, previousDepositActual);

        uint256 recipientBalanceBefore = iReserveToken.balanceOf(recipient);
        (, uint256 operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );

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
        assertEq(
            operatorSharesInAssetsAfter,
            operatorSharesInAssetsBefore - amount_,
            "operator shares in assets"
        );

        // Assert that the available deposits have decreased by the amount
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            operatorSharesInAssetsAfter - (previousDepositActual - amount_),
            "available deposits"
        );
    }
}
