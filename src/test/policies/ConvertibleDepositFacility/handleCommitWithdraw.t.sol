// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleCommitWithdrawTest is ConvertibleDepositFacilityTest {
    event AssetCommitWithdrawn(address indexed asset, address indexed operator, uint256 amount);

    uint256 public constant COMMIT_AMOUNT = 1e18;
    address public constant OPERATOR_TWO = address(0xDDD);

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, COMMIT_AMOUNT, recipient);
    }

    // given the caller is not an authorized operator
    //  [X] it reverts

    function test_givenCallerNotAuthorized_reverts(
        address caller_
    ) public givenLocallyActive givenOperatorAuthorized(OPERATOR) {
        vm.assume(caller_ != OPERATOR);

        // Expect revert
        _expectRevertUnauthorizedOperator(caller_);

        // Call function
        vm.prank(caller_);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, COMMIT_AMOUNT, recipient);
    }

    // given the operator has not committed funds
    //  given another operator has committed funds
    //   [X] it reverts

    function test_givenOperatorNoCommitment_givenOtherOperatorCommitment_amountGreaterThanCommitted_reverts(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenOperatorAuthorized(OPERATOR_TWO)
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR_TWO, amount_, 0);

        // Call function
        vm.prank(OPERATOR_TWO);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    //  [X] it reverts

    function test_givenOperatorNoCommitment_amountGreaterThanCommitted_reverts(
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
    {
        amount_ = bound(amount_, 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR, amount_, 0);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // when the amount is greater than the committed amount
    //  [X] it reverts

    function test_amountGreaterThanCommitted_reverts(
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
        amount_ = bound(amount_, previousDepositActual - COMMIT_AMOUNT + 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientCommitments(OPERATOR, amount_, COMMIT_AMOUNT);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // given the caller has not approved spending of the receipt tokens
    //  [X] it reverts

    function test_givenSpendingNotApproved_reverts()
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
        // Expect revert
        _expectRevertReceiptTokenInsufficientAllowance(address(depositManager), 0, COMMIT_AMOUNT);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, COMMIT_AMOUNT, recipient);
    }

    // [X] it burns the receipt tokens from the caller
    // [X] it transfers the deposit tokens to the recipient
    // [X] it emits an event
    // [X] it decreases the committed deposits by the amount
    // [X] it decreases the available deposits by the amount

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenOperatorAuthorized(OPERATOR)
        givenAddressHasConvertibleDepositTokenDefault(recipient)
        givenAddressHasConvertibleDepositTokenDefault(OPERATOR)
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
        givenReceiptTokenSpendingIsApproved(OPERATOR, address(depositManager), COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMIT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetCommitWithdrawn(address(iReserveToken), OPERATOR, amount_);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitWithdraw(iReserveToken, PERIOD_MONTHS, amount_, recipient);

        // Assert tokens
        assertEq(
            depositManager.balanceOf(OPERATOR, receiptTokenId),
            previousDepositActual - amount_,
            "operator receipt token balance"
        );
        assertEq(iReserveToken.balanceOf(recipient), amount_, "recipient token balance");

        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            COMMIT_AMOUNT - amount_,
            "committed deposits"
        );
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            COMMIT_AMOUNT - amount_,
            "committed deposits per operator"
        );
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            previousDepositActual * 2 - COMMIT_AMOUNT,
            "available deposits"
        );
    }
}
