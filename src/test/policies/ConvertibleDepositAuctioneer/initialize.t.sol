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
    // [X] it sets the auction parameters
    // [X] it sets the tick step
    // [X] it sets the time to expiry
    // [X] it initializes the current tick
    // [X] it activates the contract

    function test_callerNotAdmin_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("cd_admin");

        // Call function
        vm.prank(caller_);
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, TIME_TO_EXPIRY);
    }

    function test_contractAlreadyActive_reverts() public givenInitialized {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.CDAuctioneer_InvalidState.selector)
        );

        // Call function
        vm.prank(admin);
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, TIME_TO_EXPIRY);
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
        auctioneer.initialize(TARGET, 0, MIN_PRICE, TICK_STEP, TIME_TO_EXPIRY);
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
        auctioneer.initialize(TARGET, TICK_SIZE, 0, TICK_STEP, TIME_TO_EXPIRY);
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
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, tickStep, TIME_TO_EXPIRY);
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
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, 0);
    }

    function test_success() public {
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(TARGET, TICK_SIZE, MIN_PRICE);

        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(TICK_STEP);

        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(TIME_TO_EXPIRY);

        vm.expectEmit(true, true, true, true);
        emit Activated();

        // Call function
        vm.prank(admin);
        auctioneer.initialize(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, TIME_TO_EXPIRY);

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        assertEq(auctioneer.getTickStep(), TICK_STEP, "tick step");
        assertEq(auctioneer.getTimeToExpiry(), TIME_TO_EXPIRY, "time to expiry");
        assertEq(auctioneer.locallyActive(), true, "locally active");

        _assertPreviousTick(TICK_SIZE, MIN_PRICE, INITIAL_BLOCK);
    }
}
