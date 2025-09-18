// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerDisableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodDisableQueued(address indexed depositAsset, uint8 depositPeriod);

    // given the contract is not enabled
    //  [X] it queues the disable (now allowed while disabled)

    function test_givenContractNotEnabled_queuesDisable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenDisabled
    {
        // Now try to disable the period while contract is disabled
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Verify it was queued
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, true, "period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");
    }

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public givenEnabled {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period is not enabled
    //  [X] it reverts

    function test_givenDepositPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositPeriodInvalidState(iReserveToken, PERIOD_MONTHS, false);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given there are no other deposit periods for the deposit asset
    //  [X] it removes the deposit period from the deposit asset's periods array
    //  [X] it removes the deposit asset from the deposit assets array
    //  [X] it disables the deposit asset and period
    //  [X] the tick is removed
    //  [X] an event is emitted

    function test_givenNoOtherDepositPeriods()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state - period should still be enabled (only queued for disable)
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, true, "deposit period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");

        assertEq(auctioneer.getDepositPeriodsCount(), 1, "deposit periods count should still be 1");
    }

    // [X] it removes the deposit period from the deposit periods array
    // [X] it disables the deposit period
    // [X] the tick is removed
    // [X] an event is emitted

    function test_givenOtherDepositPeriods()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
    {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state - both periods should still be enabled
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, true, "first period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");

        (bool isEnabledPeriodTwo, bool isPendingEnabledPeriodTwo) = auctioneer
            .isDepositPeriodEnabled(PERIOD_MONTHS_TWO);
        assertEq(isEnabledPeriodTwo, true, "second period should still be enabled");
        assertEq(
            isPendingEnabledPeriodTwo,
            true,
            "second period pending enabled should match current state"
        );

        assertEq(auctioneer.getDepositPeriodsCount(), 2, "count should still be 2");
    }

    /// @notice Test that queueing disable after disable for same period reverts
    function test_disableAfterDisable_reverts()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Queue first disable
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Expect revert when trying to disable again
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodInvalidState
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                false // effective state would be disabled
            )
        );

        // Call function again
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    /// @notice Test trying to disable a period that is not currently enabled reverts
    function test_disableNotEnabledPeriod_reverts() public givenEnabled {
        // Expect revert when trying to disable a period that was never enabled
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodInvalidState
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                false // effective state is disabled (never enabled)
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    /// @notice Test disable -> enable -> disable sequence works correctly
    function test_disableEnableDisableSequence()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Queue disable
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Queue enable (should work since effective state becomes disabled then enabled)
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Queue disable again (should work since effective state is now enabled)
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Check final pending state - after disable -> enable -> disable sequence
        (bool finalIsEnabled, bool finalIsPendingEnabled) = auctioneer.isDepositPeriodEnabled(
            PERIOD_MONTHS
        );
        assertEq(finalIsEnabled, true, "period should still be enabled");
        assertEq(finalIsPendingEnabled, false, "period should end up pending disabled");
    }

    // when the deposit period is 0
    //  [X] it reverts
    function test_givenDepositPeriodZero_reverts() public {
        // Expect revert
        bytes memory expectedError = abi.encodeWithSignature(
            "ConvertibleDepositAuctioneer_InvalidParams(string)",
            "deposit period"
        );
        vm.expectRevert(expectedError);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(0);
    }
}
