// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerAuctionParametersTest is ConvertibleDepositAuctioneerTest {
    // Additional events for pending changes
    event DepositPeriodEnabled(address indexed depositAsset, uint8 depositPeriod);
    event DepositPeriodDisabled(address indexed depositAsset, uint8 depositPeriod);

    // when the caller does not have the "cd_emissionmanager" role
    //  [X] it reverts

    function test_callerDoesNotHaveEmissionManagerRole_reverts(address caller_) public {
        // Ensure caller is not emissionManager
        vm.assume(caller_ != emissionManager);

        // Expect revert
        _expectRoleRevert("cd_emissionmanager");

        // Call function
        vm.prank(caller_);
        auctioneer.setAuctionParameters(100, 100, 100);
    }

    // when the new tick size is 0
    //  [X] it reverts

    function test_tickSizeZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(21e9, 0, 16e18);
    }

    // when the new min price is 0
    //  [X] it reverts

    function test_minPriceZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "min price"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(21e9, 11e9, 0);
    }

    // when the tick size is greater than the target
    //  [X] it reverts

    function test_tickSizeGreaterThanTarget_reverts(uint256 tickSize_) public givenEnabled {
        uint256 target = 21e9;
        tickSize_ = bound(tickSize_, target + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(target, tickSize_, 16e18);
    }

    // when the new target is 0
    //  [X] it sets the parameters

    function test_targetZero() public givenEnabled {
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(0, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(0, newTickSize, newMinPrice);
        // No assets defined, so tick is not initialized
        _assertPreviousTick(0, 0, newTickSize, 0);
        // _assertAuctionResultsEmpty(0);
        // _assertAuctionResultsNextIndex(0);
    }

    // given the contract is not initialized
    //  [X] it sets the parameters

    function test_contractNotInitialized() public {
        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice);
        // No assets defined, so tick is not initialized
        _assertPreviousTick(0, 0, newTickSize, 0);
        _assertAuctionResultsEmpty(0);
        _assertAuctionResultsNextIndex(0);
    }

    // when the contract is deactivated
    //  [X] it sets the parameters
    //  [X] it emits an event
    //  [X] it captures the current tick capacity
    //  [X] it captures the current tick price
    //  [X] it does not change the day state
    //  [X] it does not change the auction results
    //  [X] it does not change the auction results index

    function test_contractInactive()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
        givenDisabled
    {
        uint256 lastConvertible = auctioneer.getDayState().convertible;
        int256[] memory lastAuctionResults = auctioneer.getAuctionResults();
        uint8 lastAuctionResultsIndex = auctioneer.getAuctionResultsNextIndex();

        // Warp to change the block timestamp to the next day
        vm.warp(block.timestamp + 1 days);

        IConvertibleDepositAuctioneer.Tick memory previousTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(address(iReserveToken), newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert previously-stored tick was updated with the values before the new parameters were set
        _assertPreviousTick(
            previousTick.capacity,
            previousTick.price,
            newTickSize,
            uint48(block.timestamp)
        );

        // Assert day state
        _assertDayState(lastConvertible);

        // Assert auction results
        // Values are unchanged
        _assertAuctionResults(
            lastAuctionResults[0],
            lastAuctionResults[1],
            lastAuctionResults[2],
            lastAuctionResults[3],
            lastAuctionResults[4],
            lastAuctionResults[5],
            lastAuctionResults[6]
        );
        _assertAuctionResultsNextIndex(lastAuctionResultsIndex);
    }

    // when the contract is enabled
    //  [X] it sets the parameters
    //  [X] it emits an event
    //  [X] it captures the current tick capacity
    //  [X] it captures the current tick price
    //  [X] it resets the day state
    //  [X] it updates the auction results
    //  [X] it increments the auction results index

    function test_updatesCurrentTick()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint256 lastConvertible = auctioneer.getDayState().convertible;
        int256[] memory lastAuctionResults = auctioneer.getAuctionResults();
        uint8 lastAuctionResultsIndex = auctioneer.getAuctionResultsNextIndex();

        // Warp to change the block timestamp to the next day
        vm.warp(block.timestamp + 1 days);

        IConvertibleDepositAuctioneer.Tick memory previousTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(address(iReserveToken), newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert previously-stored tick was updated with the values before the new parameters were set
        _assertPreviousTick(
            previousTick.capacity,
            previousTick.price,
            newTickSize,
            uint48(block.timestamp)
        );

        // Assert day state is updated
        _assertDayState(0);

        // Assert auction results
        // Values are updated
        _assertAuctionResults(
            int256(lastConvertible) - int256(TARGET),
            lastAuctionResults[0],
            lastAuctionResults[1],
            lastAuctionResults[2],
            lastAuctionResults[3],
            lastAuctionResults[4],
            lastAuctionResults[5]
        );
        _assertAuctionResultsNextIndex(lastAuctionResultsIndex + 1);
    }

    // when the new tick size is less than the current tick capacity
    //  [X] the tick capacity is set to the new tick size

    function test_newTickSizeLessThanCurrentTickCapacity(
        uint256 newTickSize_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTickSize = bound(newTickSize_, 1, TICK_SIZE);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert state
        _assertAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert current tick
        // Tick capacity has been adjusted to the new tick size
        _assertPreviousTick(newTickSize, MIN_PRICE, newTickSize, uint48(block.timestamp));
    }

    // when the new tick size is >= the current tick capacity
    //  [X] the tick capacity is unchanged

    function test_newTickSizeGreaterThanCurrentTickCapacity(
        uint256 newTickSize_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTickSize = bound(newTickSize_, TICK_SIZE, 2 * TICK_SIZE);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert state
        _assertAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert current tick
        // Tick capacity has been unchanged
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, newTickSize, uint48(block.timestamp));
    }

    // when the new min price is > than the current tick price
    //  [X] the tick price is set to the new min price

    function test_newMinPriceGreaterThanCurrentTickPrice(
        uint256 newMinPrice_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newMinPrice = bound(newMinPrice_, MIN_PRICE + 1, 2 * MIN_PRICE);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert current tick
        // Tick price has been set to the new min price
        _assertPreviousTick(TICK_SIZE, newMinPrice, TICK_SIZE, uint48(block.timestamp));
    }

    // when the new min price is <= the current tick price
    //  [X] the tick price is unchanged

    function test_newMinPriceLessThanCurrentTickPrice(
        uint256 newMinPrice_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newMinPrice = bound(newMinPrice_, 1, MIN_PRICE);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert current tick
        // Tick price has been unchanged
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // given this is the first day of the auction cycle
    //  [X] the day state is reset
    //  [X] it records the previous day's auction results
    //  [X] it resets the auction results index
    //  [X] the AuctionResult event is emitted
    // given this is the second day of the auction cycle
    //  [X] the day state is reset
    //  [X] it resets the auction results history
    //  [X] it increments the auction results index
    //  [X] it records the previous day's auction results
    //  [X] the AuctionResult event is emitted
    // [X] the day state is reset
    // [X] it records the previous day's auction results
    // [X] it increments the auction results index
    // [X] the AuctionResult event is emitted

    function test_calledOnDayTwo()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint256 dayOneTarget = TARGET;
        uint256 dayOneConvertible = auctioneer.getDayState().convertible;

        // Warp to day two
        vm.warp(INITIAL_BLOCK + 1 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(address(iReserveToken), dayOneConvertible, dayOneTarget, 0);

        // Set parameters
        uint256 dayTwoTarget = TARGET + 1;
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayTwoTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        uint256 dayTwoDeposit = 2e18;
        uint256 dayTwoConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayTwoDeposit);
        _mintAndBid(recipient, dayTwoDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayTwoConvertible);

        // Assert auction results
        // Values are updated for the previous day
        _assertAuctionResults(int256(dayOneConvertible) - int256(dayOneTarget), 0, 0, 0, 0, 0, 0);
        _assertAuctionResultsNextIndex(1);
    }

    function test_calledOnDayEight()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        int256[] memory expectedAuctionResults = new int256[](7);
        {
            uint256 dayOneTarget = TARGET;
            uint256 dayOneConvertible = auctioneer.getDayState().convertible;

            expectedAuctionResults[0] = int256(dayOneConvertible) - int256(dayOneTarget);
        }

        // Warp to day two
        vm.warp(INITIAL_BLOCK + 1 days);
        {
            uint256 dayTwoDeposit = 2e18;
            uint256 dayTwoTarget = TARGET + 1;
            _setAuctionParameters(dayTwoTarget, TICK_SIZE, MIN_PRICE);
            uint256 dayTwoConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayTwoDeposit);
            _mintAndBid(recipient, dayTwoDeposit);

            expectedAuctionResults[1] = int256(dayTwoConvertible) - int256(dayTwoTarget);
        }

        // Warp to day three
        vm.warp(INITIAL_BLOCK + 2 days);
        {
            uint256 dayThreeDeposit = 3e18;
            uint256 dayThreeTarget = TARGET + 2;
            _setAuctionParameters(dayThreeTarget, TICK_SIZE, MIN_PRICE);
            uint256 dayThreeConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayThreeDeposit);
            _mintAndBid(recipient, dayThreeDeposit);

            expectedAuctionResults[2] = int256(dayThreeConvertible) - int256(dayThreeTarget);
        }

        // Warp to day four
        vm.warp(INITIAL_BLOCK + 3 days);
        {
            uint256 dayFourDeposit = 4e18;
            uint256 dayFourTarget = TARGET + 3;
            _setAuctionParameters(dayFourTarget, TICK_SIZE, MIN_PRICE);
            uint256 dayFourConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayFourDeposit);
            _mintAndBid(recipient, dayFourDeposit);

            expectedAuctionResults[3] = int256(dayFourConvertible) - int256(dayFourTarget);
        }

        // Warp to day five
        vm.warp(INITIAL_BLOCK + 4 days);
        {
            uint256 dayFiveDeposit = 5e18;
            uint256 dayFiveTarget = TARGET + 4;
            _setAuctionParameters(dayFiveTarget, TICK_SIZE, MIN_PRICE);
            uint256 dayFiveConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayFiveDeposit);
            _mintAndBid(recipient, dayFiveDeposit);

            expectedAuctionResults[4] = int256(dayFiveConvertible) - int256(dayFiveTarget);
        }

        // Warp to day six
        vm.warp(INITIAL_BLOCK + 5 days);
        {
            uint256 daySixDeposit = 6e18;
            uint256 daySixTarget = TARGET + 5;
            _setAuctionParameters(daySixTarget, TICK_SIZE, MIN_PRICE);
            uint256 daySixConvertible = auctioneer.previewBid(PERIOD_MONTHS, daySixDeposit);
            _mintAndBid(recipient, daySixDeposit);

            expectedAuctionResults[5] = int256(daySixConvertible) - int256(daySixTarget);
        }

        // Warp to day seven
        vm.warp(INITIAL_BLOCK + 6 days);
        uint256 daySevenTarget = TARGET + 6;
        uint256 daySevenConvertible;
        {
            uint256 daySevenDeposit = 7e18;
            _setAuctionParameters(daySevenTarget, TICK_SIZE, MIN_PRICE);
            daySevenConvertible = auctioneer.previewBid(PERIOD_MONTHS, daySevenDeposit);
            _mintAndBid(recipient, daySevenDeposit);

            expectedAuctionResults[6] = int256(daySevenConvertible) - int256(daySevenTarget);
        }

        // Warp to day eight
        vm.warp(INITIAL_BLOCK + 7 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(address(iReserveToken), daySevenConvertible, daySevenTarget, 6);

        // Call function
        uint256 dayEightTarget = TARGET + 7;
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayEightTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        uint256 dayEightDeposit = 8e18;
        uint256 dayEightConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayEightDeposit);
        _mintAndBid(recipient, dayEightDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayEightConvertible);

        // Assert auction results
        // Values are updated for the previous day
        _assertAuctionResults(expectedAuctionResults);
        _assertAuctionResultsNextIndex(0);
    }

    function test_calledOnDayNine()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        // Warp to day two
        vm.warp(INITIAL_BLOCK + 1 days);
        uint256 dayTwoDeposit = 2e18;
        uint256 dayTwoTarget = TARGET + 1;
        _setAuctionParameters(dayTwoTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, dayTwoDeposit);
        _mintAndBid(recipient, dayTwoDeposit);

        // Warp to day three
        vm.warp(INITIAL_BLOCK + 2 days);
        uint256 dayThreeDeposit = 3e18;
        uint256 dayThreeTarget = TARGET + 2;
        _setAuctionParameters(dayThreeTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, dayThreeDeposit);
        _mintAndBid(recipient, dayThreeDeposit);

        // Warp to day four
        vm.warp(INITIAL_BLOCK + 3 days);
        uint256 dayFourDeposit = 4e18;
        uint256 dayFourTarget = TARGET + 3;
        _setAuctionParameters(dayFourTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, dayFourDeposit);
        _mintAndBid(recipient, dayFourDeposit);

        // Warp to day five
        vm.warp(INITIAL_BLOCK + 4 days);
        uint256 dayFiveDeposit = 5e18;
        uint256 dayFiveTarget = TARGET + 4;
        _setAuctionParameters(dayFiveTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, dayFiveDeposit);
        _mintAndBid(recipient, dayFiveDeposit);

        // Warp to day six
        vm.warp(INITIAL_BLOCK + 5 days);
        uint256 daySixDeposit = 6e18;
        uint256 daySixTarget = TARGET + 5;
        _setAuctionParameters(daySixTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, daySixDeposit);
        _mintAndBid(recipient, daySixDeposit);

        // Warp to day seven
        vm.warp(INITIAL_BLOCK + 6 days);
        uint256 daySevenDeposit = 7e18;
        uint256 daySevenTarget = TARGET + 6;
        _setAuctionParameters(daySevenTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(PERIOD_MONTHS, daySevenDeposit);
        _mintAndBid(recipient, daySevenDeposit);

        // Warp to day eight
        vm.warp(INITIAL_BLOCK + 7 days);
        uint256 dayEightDeposit = 8e18;
        uint256 dayEightTarget = TARGET + 7;
        _setAuctionParameters(dayEightTarget, TICK_SIZE, MIN_PRICE);
        uint256 dayEightConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayEightDeposit);
        _mintAndBid(recipient, dayEightDeposit);

        // Warp to day nine
        vm.warp(INITIAL_BLOCK + 8 days);
        uint256 dayNineDeposit = 9e18;
        uint256 dayNineTarget = TARGET + 8;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(address(iReserveToken), dayEightConvertible, dayEightTarget, 0);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayNineTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        uint256 dayNineConvertible = auctioneer.previewBid(PERIOD_MONTHS, dayNineDeposit);
        _mintAndBid(recipient, dayNineDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayNineConvertible);

        // Assert auction results
        // Values are updated for the previous day
        _assertAuctionResults(
            int256(dayEightConvertible) - int256(dayEightTarget),
            0,
            0,
            0,
            0,
            0,
            0
        );
        _assertAuctionResultsNextIndex(1);
    }

    // ========== PENDING DEPOSIT PERIOD CHANGES TESTS ========== //

    /// @notice Test single pending enable gets processed correctly
    function test_singlePendingEnable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint8 newPeriod = PERIOD_MONTHS + 1;
        uint256 lastConvertible = auctioneer.getDayState().convertible;

        // Enable the period with the DepositManager first
        vm.startPrank(admin);
        depositManager.addAssetPeriod(iReserveToken, newPeriod, address(facility), 90e2);
        vm.stopPrank();

        // Queue the enable
        vm.prank(admin);
        auctioneer.enableDepositPeriod(newPeriod);

        // Verify period is not enabled yet
        assertEq(
            auctioneer.isDepositPeriodEnabled(newPeriod),
            false,
            "period should not be enabled yet"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 1, "count should still be 1");

        // New auction parameters
        uint256 newTarget = TARGET + 1e9;
        uint256 newTickSize = TICK_SIZE + 1e9;
        uint256 newMinPrice = MIN_PRICE + 1e18;

        // Expect the actual enable event when setAuctionParameters is called
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), newPeriod);

        // Call setAuctionParameters
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Verify the period is now enabled
        assertEq(auctioneer.isDepositPeriodEnabled(newPeriod), true, "period should be enabled");
        assertEq(auctioneer.getDepositPeriodsCount(), 2, "count should be 2");

        // Verify the new period was initialized with NEW parameters
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(newPeriod);
        assertEq(tick.price, newMinPrice, "new period should have new min price");
        assertEq(tick.capacity, newTickSize, "new period should have new tick size");
        assertEq(tick.lastUpdate, block.timestamp, "new period should have current timestamp");

        // Verify auction results were stored before the change
        int256[] memory results = auctioneer.getAuctionResults();
        assertEq(
            results[0],
            int256(lastConvertible) - int256(TARGET),
            "auction results should use old target"
        );
    }

    /// @notice Test single pending disable gets processed correctly
    function test_singlePendingDisable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint256 lastConvertible = auctioneer.getDayState().convertible;

        // Queue the disable for PERIOD_MONTHS
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Verify period is still enabled
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            true,
            "period should still be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 2, "count should still be 2");

        // New auction parameters
        uint256 newTarget = TARGET + 1e9;
        uint256 newTickSize = TICK_SIZE + 1e9;
        uint256 newMinPrice = MIN_PRICE + 1e18;

        // Expect the actual disable event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call setAuctionParameters
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Verify the period is now disabled
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            false,
            "period should be disabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 1, "count should be 1");

        // Verify the remaining period still works
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS_TWO),
            true,
            "other period should still be enabled"
        );

        // Verify auction results were stored before the change (with old count of 2)
        int256[] memory results = auctioneer.getAuctionResults();
        assertEq(
            results[0],
            int256(lastConvertible) - int256(TARGET),
            "auction results should use old target"
        );
    }

    /// @notice Test mixed enable/disable for different periods
    function test_mixedEnableDisableDifferentPeriods()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint8 newPeriod = PERIOD_MONTHS + 1;

        // Enable new period with DepositManager
        vm.startPrank(admin);
        depositManager.addAssetPeriod(iReserveToken, newPeriod, address(facility), 90e2);
        vm.stopPrank();

        // Queue enable for new period and disable for existing period
        vm.prank(admin);
        auctioneer.enableDepositPeriod(newPeriod);
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // New auction parameters
        uint256 newTarget = TARGET + 1e9;
        uint256 newTickSize = TICK_SIZE + 1e9;
        uint256 newMinPrice = MIN_PRICE + 1e18;

        // Expect both events
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), newPeriod);
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call setAuctionParameters
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Verify final state
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            false,
            "old period should be disabled"
        );
        assertEq(
            auctioneer.isDepositPeriodEnabled(newPeriod),
            true,
            "new period should be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 1, "count should be 1");

        // Verify new period has new parameters
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(newPeriod);
        assertEq(tick.price, newMinPrice, "new period should have new min price");
        assertEq(tick.capacity, newTickSize, "new period should have new tick size");
    }

    /// @notice Test enable then disable same period (final state should be disabled)
    function test_enableThenDisableSamePeriod()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        uint8 targetPeriod = PERIOD_MONTHS_TWO;

        // Queue enable then disable for the same period
        vm.prank(admin);
        auctioneer.enableDepositPeriod(targetPeriod);
        vm.prank(admin);
        auctioneer.disableDepositPeriod(targetPeriod);

        // New auction parameters
        uint256 newTarget = TARGET + 1e9;
        uint256 newTickSize = TICK_SIZE + 1e9;
        uint256 newMinPrice = MIN_PRICE + 1e18;

        // Should emit both events since both operations are processed
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), targetPeriod);
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), targetPeriod);

        // Call setAuctionParameters
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Verify final state is disabled
        assertEq(
            auctioneer.isDepositPeriodEnabled(targetPeriod),
            false,
            "period should be disabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 1, "count should still be 1");
    }

    /// @notice Test disable then enable same period (final state should be enabled)
    function test_disableThenEnableSamePeriod()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        // Queue disable then enable for the same period
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS_TWO);
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS_TWO);

        // New auction parameters
        uint256 newTarget = TARGET + 1e9;
        uint256 newTickSize = TICK_SIZE + 1e9;
        uint256 newMinPrice = MIN_PRICE + 1e18;

        // Both events should be emitted
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS_TWO);
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS_TWO);

        // Call setAuctionParameters
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Verify final state is enabled with new parameters
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS_TWO),
            true,
            "period should be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 2, "count should still be 2");

        // Verify it has new parameters (since it was re-enabled)
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(
            PERIOD_MONTHS_TWO
        );
        assertEq(tick.price, newMinPrice, "re-enabled period should have new min price");
        assertEq(tick.capacity, newTickSize, "re-enabled period should have new tick size");
    }
}
