// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerEnableTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "admin" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin address
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    // when the contract is already enabled
    //  [X] it reverts

    function test_contractEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectNotDisabledRevert();

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    // when the contract is disabled
    //  when the enable parameters length is incorrect
    //   [X] it reverts

    function test_enableParamsLengthIncorrect_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "enable data"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.AuctionParameters({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE
                })
            )
        );
    }

    // when the tick size is greater than the target
    //  [X] it reverts

    function test_tickSizeGreaterThanTarget_reverts(uint256 tickSize_) public {
        tickSize_ = bound(tickSize_, TARGET + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: tickSize_,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    //  when the tick size is 0
    //   [X] it reverts

    function test_tickSizeZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: 0,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    //  when the min price is 0
    //   [X] it reverts

    function test_minPriceZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "min price"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: 0,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    //  when the tick step is < 100e2
    //   [X] it reverts

    function test_tickStepOutOfBounds_reverts(uint24 tickStep_) public {
        uint24 tickStep = uint24(bound(tickStep_, 0, 100e2 - 1));

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick step"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: tickStep,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );
    }

    //  when the auction tracking period is 0
    //   [X] it reverts

    function test_auctionTrackingPeriodZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "auction tracking period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: 0
                })
            )
        );
    }

    //  [X] it activates the contract
    //  [X] it emits an event
    //  [X] it sets the auction parameters
    //  [X] it sets the tick step
    //  [X] it sets the auction tracking period
    //  [X] it sets the previous tick
    //  [X] it sets the last update to the current block timestamp
    //  [X] it resets the day state
    //  [X] it resets the auction results history and index

    function test_contractDisabled()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
        givenDisabled
    {
        uint48 lastUpdate = uint48(block.timestamp);
        uint48 newBlock = lastUpdate + 1;

        // Warp to change the block timestamp
        vm.warp(newBlock);

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(address(iReserveToken), TARGET, TICK_SIZE, MIN_PRICE);

        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(address(iReserveToken), TICK_STEP);

        vm.expectEmit(true, true, true, true);
        emit AuctionTrackingPeriodUpdated(address(iReserveToken), AUCTION_TRACKING_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit Enabled();

        // Call function
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        assertEq(auctioneer.getTickStep(), TICK_STEP, "tick step");
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD,
            "auction tracking period"
        );
        assertEq(auctioneer.isEnabled(), true, "enabled");

        // Day state is reset
        _assertDayState(0);

        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, newBlock);

        _assertAuctionResults(0, 0, 0, 0, 0, 0, 0);
        _assertAuctionResultsNextIndex(0);
    }

    /// @notice Test that pending deposit period changes are processed when the contract is enabled
    function test_pendingChangesProcessedOnEnable() public {
        // Queue some changes while contract is disabled
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS_TWO);

        // Verify changes are pending
        (bool isEnabled1, bool isPendingEnabled1) = auctioneer.getDepositPeriodState(PERIOD_MONTHS);
        (bool isEnabled2, bool isPendingEnabled2) = auctioneer.getDepositPeriodState(
            PERIOD_MONTHS_TWO
        );
        assertEq(isEnabled1, false, "period 1 should not be enabled yet");
        assertEq(isPendingEnabled1, true, "period 1 should be pending enabled");
        assertEq(isEnabled2, false, "period 2 should not be enabled yet");
        assertEq(isPendingEnabled2, true, "period 2 should be pending enabled");

        // Enable the contract - this should process pending changes
        vm.prank(admin);
        auctioneer.enable(
            abi.encode(
                IConvertibleDepositAuctioneer.EnableParams({
                    target: TARGET,
                    tickSize: TICK_SIZE,
                    minPrice: MIN_PRICE,
                    tickStep: TICK_STEP,
                    auctionTrackingPeriod: AUCTION_TRACKING_PERIOD
                })
            )
        );

        // Verify periods are now actually enabled
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            true,
            "period 1 should be enabled"
        );
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS_TWO),
            true,
            "period 2 should be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 2, "should have 2 enabled periods");

        // Verify no pending changes remain
        (bool finalEnabled1, bool finalPending1) = auctioneer.getDepositPeriodState(PERIOD_MONTHS);
        (bool finalEnabled2, bool finalPending2) = auctioneer.getDepositPeriodState(
            PERIOD_MONTHS_TWO
        );
        assertEq(finalEnabled1, true, "period 1 should be enabled");
        assertEq(finalPending1, true, "period 1 pending should match current");
        assertEq(finalEnabled2, true, "period 2 should be enabled");
        assertEq(finalPending2, true, "period 2 pending should match current");
    }
}
