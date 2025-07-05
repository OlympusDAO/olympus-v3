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

    // when the amount is greater than the available capacity
    //  [X] it reverts

    function test_whenAmountGreaterThanCapacity_reverts(
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
        amount_ = bound(amount_, previousDepositActual + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_BorrowingLimitExceeded.selector,
                address(iReserveToken),
                address(facility),
                amount_,
                previousDepositActual
            )
        );

        // Call function
        vm.prank(OPERATOR);
        facility.handleBorrow(iReserveToken, PERIOD_MONTHS, amount_, recipient);
    }

    // [X] it transfers the tokens to the recipient

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
    {
        amount_ = bound(amount_, 1e18, previousDepositActual);

        // Call function
        vm.prank(OPERATOR);
        uint256 actualAmount = facility.handleBorrow(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            recipient
        );

        // Assert
        assertEq(actualAmount, amount_, "actual amount");
        assertEq(iReserveToken.balanceOf(recipient), amount_, "recipient balance");
    }
}
