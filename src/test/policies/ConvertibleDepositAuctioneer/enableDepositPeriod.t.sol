// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerEnableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodEnableQueued(address indexed depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public givenEnabled {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the contract is not enabled
    //  [X] it queues the enable (now allowed while disabled)

    function test_givenContractNotEnabled_queuesEnable() public {
        // Expect queued event (should work while disabled)
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Verify it was queued
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, false, "period should not be enabled yet");
        assertEq(isPendingEnabled, true, "period should be pending enabled");
    }

    // when the deposit period is zero
    //  [X] it reverts

    function test_whenDepositPeriodIsZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "deposit period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(0);
    }

    // given the deposit period is already enabled
    //  [X] it reverts

    function test_givenDepositPeriodAlreadyEnabled_reverts()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Expect revert
        _expectDepositPeriodInvalidState(iReserveToken, PERIOD_MONTHS, true);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period was previously enabled
    //  [X] the tick for the deposit period is initialized

    function test_givenDepositPeriodPreviouslyEnabled()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodDisabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Warp forward, so we know the timestamp will be different
        vm.warp(block.timestamp + 1);

        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state - period should NOT be enabled yet (only queued)
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, false, "deposit period should not be enabled yet");
        assertEq(isPendingEnabled, true, "deposit period should be pending enabled");

        assertEq(auctioneer.getDepositPeriodsCount(), 0, "deposit periods count should still be 0");

        // The tick should not be initialized yet
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }

    // given there is another deposit period enabled
    //  [X] the deposit period is added to the deposit periods array
    //  [X] the deposit period is enabled
    //  [X] the tick for the deposit period is initialized
    //  [X] an event is emitted

    function test_givenOtherDepositPeriodEnabled()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnableQueued(address(iReserveToken), PERIOD_MONTHS_TWO);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS_TWO);

        // Assert state - new period should NOT be enabled yet (only queued)
        (bool isEnabledPeriodTwo, bool isPendingEnabledPeriodTwo) = auctioneer
            .isDepositPeriodEnabled(PERIOD_MONTHS_TWO);
        assertEq(isEnabledPeriodTwo, false, "new period should not be enabled yet");
        assertEq(isPendingEnabledPeriodTwo, true, "new period should be pending enabled");

        assertEq(
            auctioneer.getDepositPeriodsCount(),
            1,
            "count should still be 1 (existing period)"
        );

        // Original period should still be enabled
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, true, "existing period should still be enabled");
        assertEq(isPendingEnabled, true, "existing period pending should match current state");
    }

    // [X] the deposit period is added to the deposit periods array
    // [X] the deposit period is enabled
    // [X] the tick for the deposit period is initialized
    // [X] an event is emitted

    function test_success() public givenEnabled {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state - period should NOT be enabled yet (only queued)
        (bool isEnabled, bool isPendingEnabled) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(isEnabled, false, "deposit period should not be enabled yet");
        assertEq(isPendingEnabled, true, "period should be pending enabled");

        assertEq(auctioneer.getDepositPeriodsCount(), 0, "deposit periods count should still be 0");

        // The tick should not be initialized yet
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }

    /// @notice Test that queueing enable after enable for same period reverts
    function test_enableAfterEnable_reverts() public givenEnabled {
        // Queue first enable
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Expect revert when trying to enable again
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodInvalidState
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                true // effective state would be enabled
            )
        );

        // Call function again
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    /// @notice Test enable -> disable -> enable sequence works correctly
    function test_enableDisableEnableSequence() public givenEnabled {
        // Queue enable
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Queue disable (should work since effective state becomes enabled then disabled)
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Queue enable again (should work since effective state is now disabled)
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Check final pending state - after enable -> disable -> enable sequence
        (bool finalIsEnabled, bool finalIsPendingEnabled) = auctioneer.isDepositPeriodEnabled(
            PERIOD_MONTHS
        );
        assertEq(finalIsEnabled, false, "period should not be enabled yet");
        assertEq(finalIsPendingEnabled, true, "period should end up pending enabled");
    }
}
