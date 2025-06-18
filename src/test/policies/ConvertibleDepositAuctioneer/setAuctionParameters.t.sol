// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerAuctionParametersTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "cd_emissionmanager" role
    //  [X] it reverts
    // when the new target is 0
    //  [X] it reverts
    // when the new tick size is 0
    //  [X] it reverts
    // when the new min price is 0
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the parameters
    //  [X] it emits an event
    //  [X] it does not change the current tick capacity
    //  [X] it does not change the current tick price
    //  [X] it does not change the day state
    //  [X] it does not change the auction results
    //  [X] it does not change the auction results index
    // when the new tick size is less than the current tick capacity
    //  [X] the tick capacity is set to the new tick size
    // when the new tick size is >= the current tick capacity
    //  [X] the tick capacity is unchanged
    // when the new min price is > than the current tick price
    //  [X] the tick price is set to the new min price
    // when the new min price is <= the current tick price
    //  [X] the tick price is unchanged
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

    function test_callerDoesNotHaveEmissionManagerRole_reverts(address caller_) public {
        // Ensure caller is not emissionManager
        vm.assume(caller_ != emissionManager);

        // Expect revert
        _expectRoleRevert("cd_emissionmanager");

        // Call function
        vm.prank(caller_);
        auctioneer.setAuctionParameters(100, 100, 100);
    }

    function test_contractNotInitialized() public {
        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice);
        _assertPreviousTick(
            0,
            newMinPrice, // Set to new min price. Will be overriden when initialized.
            newTickSize,
            0
        );
        _assertAuctionResultsEmpty(0);
        _assertAuctionResultsNextIndex(0);
    }

    function test_targetZero_reverts() public givenEnabled {
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "target"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(0, newTickSize, newMinPrice);
    }

    function test_tickSizeZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(21e9, 0, 16e18);
    }

    function test_minPriceZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "min price"
            )
        );

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(21e9, 11e9, 0);
    }

    function test_contractInactive() public givenEnabled givenRecipientHasBid(1e18) givenDisabled {
        uint256 lastConvertible = auctioneer.getDayState().convertible;
        uint256 lastDeposits = auctioneer.getDayState().deposits;
        int256[] memory lastAuctionResults = auctioneer.getAuctionResults();
        uint8 lastAuctionResultsIndex = auctioneer.getAuctionResultsNextIndex();
        uint256 lastCapacity = auctioneer.getPreviousTick().capacity;
        uint256 lastPrice = auctioneer.getPreviousTick().price;
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp to the next day
        vm.warp(lastUpdate + 1 days);

        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 14e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert current tick
        // Values are unchanged
        _assertPreviousTick(lastCapacity, lastPrice, newTickSize, lastUpdate);

        // Assert day state
        _assertDayState(lastDeposits, lastConvertible);

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

    function test_newTickSizeLessThanCurrentTickCapacity(uint256 newTickSize_) public givenEnabled {
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
        _assertPreviousTick(newTickSize, MIN_PRICE, newTickSize, lastUpdate);
    }

    function test_newTickSizeGreaterThanCurrentTickCapacity(
        uint256 newTickSize_
    ) public givenEnabled {
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
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, newTickSize, lastUpdate);
    }

    function test_newMinPriceGreaterThanCurrentTickPrice(uint256 newMinPrice_) public givenEnabled {
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
        _assertPreviousTick(TICK_SIZE, newMinPrice, TICK_SIZE, lastUpdate);
    }

    function test_newMinPriceLessThanCurrentTickPrice(uint256 newMinPrice_) public givenEnabled {
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
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, lastUpdate);
    }

    function test_calledOnDayTwo() public givenEnabled givenRecipientHasBid(1e18) {
        uint256 dayOneTarget = TARGET;
        uint256 dayOneConvertible = auctioneer.getDayState().convertible;

        // Warp to day two
        vm.warp(INITIAL_BLOCK + 1 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(dayOneConvertible, dayOneTarget, 0);

        // Set parameters
        uint256 dayTwoTarget = TARGET + 1;
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayTwoTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        uint256 dayTwoDeposit = 2e18;
        (uint256 dayTwoConvertible, ) = auctioneer.previewBid(dayTwoDeposit);
        _mintAndBid(recipient, dayTwoDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayTwoDeposit, dayTwoConvertible);

        // Assert auction results
        // Values are updated for the previous day
        _assertAuctionResults(int256(dayOneConvertible) - int256(dayOneTarget), 0, 0, 0, 0, 0, 0);
        _assertAuctionResultsNextIndex(1);
    }

    function test_calledOnDayEight() public givenEnabled givenRecipientHasBid(1e18) {
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
            (uint256 dayTwoConvertible, ) = auctioneer.previewBid(dayTwoDeposit);
            _mintAndBid(recipient, dayTwoDeposit);

            expectedAuctionResults[1] = int256(dayTwoConvertible) - int256(dayTwoTarget);
        }

        // Warp to day three
        vm.warp(INITIAL_BLOCK + 2 days);
        {
            uint256 dayThreeDeposit = 3e18;
            uint256 dayThreeTarget = TARGET + 2;
            _setAuctionParameters(dayThreeTarget, TICK_SIZE, MIN_PRICE);
            (uint256 dayThreeConvertible, ) = auctioneer.previewBid(dayThreeDeposit);
            _mintAndBid(recipient, dayThreeDeposit);

            expectedAuctionResults[2] = int256(dayThreeConvertible) - int256(dayThreeTarget);
        }

        // Warp to day four
        vm.warp(INITIAL_BLOCK + 3 days);
        {
            uint256 dayFourDeposit = 4e18;
            uint256 dayFourTarget = TARGET + 3;
            _setAuctionParameters(dayFourTarget, TICK_SIZE, MIN_PRICE);
            (uint256 dayFourConvertible, ) = auctioneer.previewBid(dayFourDeposit);
            _mintAndBid(recipient, dayFourDeposit);

            expectedAuctionResults[3] = int256(dayFourConvertible) - int256(dayFourTarget);
        }

        // Warp to day five
        vm.warp(INITIAL_BLOCK + 4 days);
        {
            uint256 dayFiveDeposit = 5e18;
            uint256 dayFiveTarget = TARGET + 4;
            _setAuctionParameters(dayFiveTarget, TICK_SIZE, MIN_PRICE);
            (uint256 dayFiveConvertible, ) = auctioneer.previewBid(dayFiveDeposit);
            _mintAndBid(recipient, dayFiveDeposit);

            expectedAuctionResults[4] = int256(dayFiveConvertible) - int256(dayFiveTarget);
        }

        // Warp to day six
        vm.warp(INITIAL_BLOCK + 5 days);
        {
            uint256 daySixDeposit = 6e18;
            uint256 daySixTarget = TARGET + 5;
            _setAuctionParameters(daySixTarget, TICK_SIZE, MIN_PRICE);
            (uint256 daySixConvertible, ) = auctioneer.previewBid(daySixDeposit);
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
            (daySevenConvertible, ) = auctioneer.previewBid(daySevenDeposit);
            _mintAndBid(recipient, daySevenDeposit);

            expectedAuctionResults[6] = int256(daySevenConvertible) - int256(daySevenTarget);
        }

        // Warp to day eight
        vm.warp(INITIAL_BLOCK + 7 days);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(daySevenConvertible, daySevenTarget, 6);

        // Call function
        uint256 dayEightTarget = TARGET + 7;
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayEightTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        uint256 dayEightDeposit = 8e18;
        (uint256 dayEightConvertible, ) = auctioneer.previewBid(dayEightDeposit);
        _mintAndBid(recipient, dayEightDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayEightDeposit, dayEightConvertible);

        // Assert auction results
        // Values are updated for the previous day
        _assertAuctionResults(expectedAuctionResults);
        _assertAuctionResultsNextIndex(0);
    }

    function test_calledOnDayNine() public givenEnabled givenRecipientHasBid(1e18) {
        // Warp to day two
        vm.warp(INITIAL_BLOCK + 1 days);
        uint256 dayTwoDeposit = 2e18;
        uint256 dayTwoTarget = TARGET + 1;
        _setAuctionParameters(dayTwoTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(dayTwoDeposit);
        _mintAndBid(recipient, dayTwoDeposit);

        // Warp to day three
        vm.warp(INITIAL_BLOCK + 2 days);
        uint256 dayThreeDeposit = 3e18;
        uint256 dayThreeTarget = TARGET + 2;
        _setAuctionParameters(dayThreeTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(dayThreeDeposit);
        _mintAndBid(recipient, dayThreeDeposit);

        // Warp to day four
        vm.warp(INITIAL_BLOCK + 3 days);
        uint256 dayFourDeposit = 4e18;
        uint256 dayFourTarget = TARGET + 3;
        _setAuctionParameters(dayFourTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(dayFourDeposit);
        _mintAndBid(recipient, dayFourDeposit);

        // Warp to day five
        vm.warp(INITIAL_BLOCK + 4 days);
        uint256 dayFiveDeposit = 5e18;
        uint256 dayFiveTarget = TARGET + 4;
        _setAuctionParameters(dayFiveTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(dayFiveDeposit);
        _mintAndBid(recipient, dayFiveDeposit);

        // Warp to day six
        vm.warp(INITIAL_BLOCK + 5 days);
        uint256 daySixDeposit = 6e18;
        uint256 daySixTarget = TARGET + 5;
        _setAuctionParameters(daySixTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(daySixDeposit);
        _mintAndBid(recipient, daySixDeposit);

        // Warp to day seven
        vm.warp(INITIAL_BLOCK + 6 days);
        uint256 daySevenDeposit = 7e18;
        uint256 daySevenTarget = TARGET + 6;
        _setAuctionParameters(daySevenTarget, TICK_SIZE, MIN_PRICE);
        auctioneer.previewBid(daySevenDeposit);
        _mintAndBid(recipient, daySevenDeposit);

        // Warp to day eight
        vm.warp(INITIAL_BLOCK + 7 days);
        uint256 dayEightDeposit = 8e18;
        uint256 dayEightTarget = TARGET + 7;
        _setAuctionParameters(dayEightTarget, TICK_SIZE, MIN_PRICE);
        (uint256 dayEightConvertible, ) = auctioneer.previewBid(dayEightDeposit);
        _mintAndBid(recipient, dayEightDeposit);

        // Warp to day nine
        vm.warp(INITIAL_BLOCK + 8 days);
        uint256 dayNineDeposit = 9e18;
        uint256 dayNineTarget = TARGET + 8;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionResult(dayEightConvertible, dayEightTarget, 0);

        // Call function
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(dayNineTarget, TICK_SIZE, MIN_PRICE);

        // Bid
        (uint256 dayNineConvertible, ) = auctioneer.previewBid(dayNineDeposit);
        _mintAndBid(recipient, dayNineDeposit);

        // Assert day state
        // Values are updated for the current day
        _assertDayState(dayNineDeposit, dayNineConvertible);

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
}
