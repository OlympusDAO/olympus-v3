// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerSetAuctionTrackingPeriodTest is
    ConvertibleDepositAuctioneerTest
{
    // given the caller does not have the admin role
    //  [X] it reverts

    function test_callerDoesNotHaveManagerOrAdminRole_reverts(address caller_) public givenEnabled {
        // Ensure caller is not manager or admin
        vm.assume(caller_ != manager && caller_ != admin);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD);
    }

    // when the auction tracking period is 0
    //  [X] it reverts

    function test_auctionTrackingPeriodZero_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "auction tracking period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(0);
    }

    // given the contract is not initialized
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index

    function test_contractNotInitialized() public {
        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD + 1);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD + 1,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD + 1,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD + 1);
        _assertAuctionResultsNextIndex(0);
    }

    // given the contract is deactivated
    //  [X] the array length is set to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index

    function test_contractDisabled() public {
        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD + 1);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD + 1,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD + 1,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD + 1);
        _assertAuctionResultsNextIndex(0);
    }

    // given the previous auction tracking period is less
    //  [X] the array length is increased to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index

    function test_previousTrackingPeriodLess() public givenEnabled {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionTrackingPeriodUpdated(AUCTION_TRACKING_PERIOD + 1);

        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD + 1);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD + 1,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD + 1,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD + 1);
        _assertAuctionResultsNextIndex(0);
    }

    // given the previous auction tracking period is the same
    //  [X] the array length is unchanged
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index

    function test_previousTrackingPeriodSame() public givenEnabled {
        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD);
        _assertAuctionResultsNextIndex(0);
    }

    // given the previous auction tracking period is greater
    //  [X] the array length is reduced to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index

    function test_previousTrackingPeriodGreater() public givenEnabled {
        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD - 1);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD - 1,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD - 1,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD - 1);
        _assertAuctionResultsNextIndex(0);
    }

    // given there are previous auction results
    //  [X] it resets the auction results

    function test_previousAuctionResults()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenRecipientHasBid(1e18)
    {
        // Warp to the next day and trigger storage of the previous day's results
        vm.warp(block.timestamp + 1 days);
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        vm.prank(admin);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD);

        // Assert state
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD,
            "auction tracking period"
        );
        assertEq(
            auctioneer.getAuctionResults().length,
            AUCTION_TRACKING_PERIOD,
            "auction results length"
        );
        _assertAuctionResultsEmpty(AUCTION_TRACKING_PERIOD);
        _assertAuctionResultsNextIndex(0);
    }
}
