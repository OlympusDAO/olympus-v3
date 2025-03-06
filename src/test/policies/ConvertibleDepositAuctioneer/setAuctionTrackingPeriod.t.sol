// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerSetAuctionTrackingPeriodTest is
    ConvertibleDepositAuctioneerTest
{
    // given the caller does not have the admin role
    //  [X] it reverts
    // when the auction tracking period is 0
    //  [X] it reverts
    // given the contract is deactivated
    //  [X] the array length is set to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index
    // given the previous auction tracking period is less
    //  [X] the array length is increased to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index
    // given the previous auction tracking period is the same
    //  [X] the array length is unchanged
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index
    // given the previous auction tracking period is greater
    //  [X] the array length is reduced to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    //  [X] it resets the auction results
    //  [X] it resets the auction results index
    // given there are previous auction results
    //  [X] it resets the auction results

    function test_callerDoesNotHaveAdminRole_reverts() public givenEnabled {
        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(recipient);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD);
    }

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

    function test_previousAuctionResults() public givenEnabled givenRecipientHasBid(1e18) {
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
