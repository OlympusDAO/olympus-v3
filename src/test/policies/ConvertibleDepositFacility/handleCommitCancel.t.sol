// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleCommitCancelTest is ConvertibleDepositFacilityTest {
    event AssetCommitCancelled(address indexed asset, address indexed operator, uint256 amount);

    uint256 public constant COMMIT_AMOUNT = 1e18;

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitCancel(iReserveToken, PERIOD_MONTHS, COMMIT_AMOUNT);
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
        facility.handleCommitCancel(iReserveToken, PERIOD_MONTHS, COMMIT_AMOUNT);
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
        facility.handleCommitCancel(iReserveToken, PERIOD_MONTHS, amount_);
    }

    // [X] it does not transfer any tokens
    // [X] it emits an event
    // [X] it decreases the committed deposits by the amount
    // [X] it increases the available deposits by the amount

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
        givenCommitted(OPERATOR, COMMIT_AMOUNT)
    {
        amount_ = bound(amount_, 1, COMMIT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetCommitCancelled(address(iReserveToken), OPERATOR, amount_);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommitCancel(iReserveToken, PERIOD_MONTHS, amount_);

        // Assert state
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
            previousDepositActual - COMMIT_AMOUNT + amount_,
            "available deposits"
        );
    }
}
