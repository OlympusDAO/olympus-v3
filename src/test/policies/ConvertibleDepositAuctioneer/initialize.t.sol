// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerInitializeTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "admin" role
    //  [X] it reverts
    // when the contract is already active
    //  [X] it reverts
    // when the tick size is 0
    //  [X] it reverts
    // when the min price is 0
    //  [X] it reverts
    // when the tick step is < 100e2
    //  [X] it reverts
    // when the time to expiry is 0
    //  [X] it reverts
    // when the auction tracking period is 0
    //  [X] it reverts
    // given the contract is already initialized
    //  given the contract is disabled
    //   [X] it reverts
    //  [X] it reverts
    // [X] it sets the auction parameters
    // [X] it sets the tick step
    // [X] it sets the time to expiry
    // [X] it initializes the current tick
    // [X] it activates the contract
    // [X] it initializes the day state
    // [X] it initializes the auction results history and index

    function test_callerNotAdmin_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("cd_admin");

        // Call function
        vm.prank(caller_);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_contractAlreadyActive_reverts() public givenInitialized {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.CDAuctioneer_InvalidState.selector)
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_tickSizeZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            0,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_minPriceZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "min price"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            0,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_tickStepOutOfBounds_reverts(uint24 tickStep_) public {
        uint24 tickStep = uint24(bound(tickStep_, 0, 100e2 - 1));

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "tick step"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            tickStep,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_timeToExpiryZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "time to expiry"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, 0, AUCTION_TRACKING_PERIOD);
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
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, TIME_TO_EXPIRY, 0);
    }

    function test_contractInitialized_reverts() public givenInitialized {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.CDAuctioneer_InvalidState.selector)
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_contractInitialized_disabled_reverts()
        public
        givenInitialized
        givenContractInactive
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.CDAuctioneer_InvalidState.selector)
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );
    }

    function test_success() public {
        // Not yet initialized
        assertEq(auctioneer.initialized(), false, "initialized");

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(TARGET, TICK_SIZE, MIN_PRICE);

        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(TICK_STEP);

        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(TIME_TO_EXPIRY);

        vm.expectEmit(true, true, true, true);
        emit AuctionTrackingPeriodUpdated(AUCTION_TRACKING_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit Activated();

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD
        );

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        assertEq(auctioneer.getTickStep(), TICK_STEP, "tick step");
        assertEq(auctioneer.getTimeToExpiry(), TIME_TO_EXPIRY, "time to expiry");
        assertEq(
            auctioneer.getAuctionTrackingPeriod(),
            AUCTION_TRACKING_PERIOD,
            "auction tracking period"
        );
        assertEq(auctioneer.locallyActive(), true, "locally active");
        assertEq(auctioneer.initialized(), true, "initialized");

        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, INITIAL_BLOCK);

        _assertAuctionResults(0, 0, 0, 0, 0, 0, 0);
        _assertAuctionResultsNextIndex(0);
    }

    function test_auctionTrackingPeriodDifferent() public {
        // Not yet initialized
        assertEq(auctioneer.initialized(), false, "initialized");

        vm.expectEmit(true, true, true, true);
        emit AuctionTrackingPeriodUpdated(AUCTION_TRACKING_PERIOD + 1);

        // Call function
        vm.prank(admin);
        auctioneer.initialize(
            TARGET,
            TICK_SIZE,
            MIN_PRICE,
            TICK_STEP,
            TIME_TO_EXPIRY,
            AUCTION_TRACKING_PERIOD + 1
        );

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
}
