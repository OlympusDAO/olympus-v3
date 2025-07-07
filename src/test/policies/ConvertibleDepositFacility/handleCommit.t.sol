// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityHandleCommitTest is ConvertibleDepositFacilityTest {
    event AssetCommitted(address indexed asset, address indexed operator, uint256 amount);

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
        facility.handleCommit(iReserveToken, COMMIT_AMOUNT);
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
        facility.handleCommit(iReserveToken, COMMIT_AMOUNT);
    }

    // given there are no committed funds
    //  when the amount is greater than the deposits
    //   [X] it reverts

    function test_givenNoDeposits_whenAmountGreaterThanCapacity_reverts(
        uint256 amount_
    ) public givenLocallyActive givenOperatorAuthorized(OPERATOR) {
        amount_ = bound(amount_, 1, type(uint256).max);

        // Expect revert
        _expectRevertInsufficientDeposits(amount_, 0);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommit(iReserveToken, amount_);
    }

    // when the amount is greater than the available deposits
    //  [X] it reverts

    function test_amountGreaterThanCapacity_reverts(
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
        _expectRevertInsufficientDeposits(amount_, previousDepositActual);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommit(iReserveToken, amount_);
    }

    // given an operator has committed funds
    //  [X] it does not transfer any tokens
    //  [X] it emits an event
    //  [X] it increases the committed deposits by the amount
    //  [X] it reduces the available deposits by the amount

    function test_givenCommittedFunds(
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
        amount_ = bound(amount_, 1, previousDepositActual - COMMIT_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetCommitted(address(iReserveToken), OPERATOR_TWO, amount_);

        // Call function
        vm.prank(OPERATOR_TWO);
        facility.handleCommit(iReserveToken, amount_);

        // Assert state
        assertEq(
            facility.getCommittedDeposits(iReserveToken),
            COMMIT_AMOUNT + amount_,
            "committed deposits"
        );
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR_TWO),
            amount_,
            "committed deposits per operator"
        );
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            previousDepositActual - COMMIT_AMOUNT - amount_,
            "available deposits"
        );
    }

    // [X] it does not transfer any tokens
    // [X] it emits an event
    // [X] it increases the committed deposits by the amount
    // [X] it reduces the available deposits by the amount

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
        amount_ = bound(amount_, 1, previousDepositActual);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetCommitted(address(iReserveToken), OPERATOR, amount_);

        // Call function
        vm.prank(OPERATOR);
        facility.handleCommit(iReserveToken, amount_);

        // Assert state
        assertEq(facility.getCommittedDeposits(iReserveToken), amount_, "committed deposits");
        assertEq(
            facility.getCommittedDeposits(iReserveToken, OPERATOR),
            amount_,
            "committed deposits per operator"
        );
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            previousDepositActual - amount_,
            "available deposits"
        );
    }
}
