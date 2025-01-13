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
    // given the previous auction tracking period is less
    //  [X] the array length is increased to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    // given the previous auction tracking period is the same
    //  [X] the array length is unchanged
    //  [X] it sets the auction tracking period
    //  [X] it emits an event
    // given the previous auction tracking period is greater
    //  [X] the array length is reduced to the tracking period
    //  [X] it sets the auction tracking period
    //  [X] it emits an event

    function test_callerDoesNotHaveAdminRole_reverts() public {
        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(recipient);
        auctioneer.setAuctionTrackingPeriod(AUCTION_TRACKING_PERIOD);
    }

    function test_auctionTrackingPeriodZero_reverts() public {
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

    function test_previousTrackingPeriodLess() public {
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
    }

    function test_previousTrackingPeriodSame() public {
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
    }

    function test_previousTrackingPeriodGreater() public {
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
    }
}
