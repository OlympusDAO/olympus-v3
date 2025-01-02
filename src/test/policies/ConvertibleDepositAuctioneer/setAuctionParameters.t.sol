// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerAuctionParametersTest is ConvertibleDepositAuctioneerTest {
    event AuctionParametersUpdated(uint256 newTarget, uint256 newTickSize, uint256 newMinPrice);

    // when the caller does not have the "heart" role
    //  [X] it reverts
    // when the new target is 0
    //  [X] it succeeds
    // when the new tick size is 0
    //  [X] it reverts
    // when the new min price is 0
    //  [X] it succeeds
    // when the contract is deactivated
    //  [X] it sets the parameters
    // [X] it sets the parameters
    // [X] it emits an event

    // TODO determine expected behaviour of remainder

    function test_callerDoesNotHaveHeartRole_reverts(address caller_) public {
        // Ensure caller is not heart
        vm.assume(caller_ != heart);

        // Expect revert
        _expectRoleRevert("heart");

        // Call function
        vm.prank(caller_);
        auctioneer.setAuctionParameters(100, 100, 100);
    }

    function test_targetZero()
        public
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
        givenContractActive
    {
        uint48 lastUpdate = block.timestamp;

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(0, 101, 102);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(0, 101, 102);

        // Assert state
        _assertState(0, 101, 102, TICK_STEP, TIME_TO_EXPIRY, lastUpdate);
    }

    function test_tickSizeZero_reverts() public givenContractActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "tick size"
            )
        );

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 0, 102);
    }

    function test_minPriceZero() public givenContractActive {
        uint48 lastUpdate = block.timestamp;

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(100, 101, 0);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 0);

        // Assert state
        _assertState(100, 101, 0, TICK_STEP, TIME_TO_EXPIRY, lastUpdate);
    }

    function test_contractInactive()
        public
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
        givenContractInactive
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(100, 101, 102);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 102);

        // Assert state
        _assertState(100, 101, 102, TICK_STEP, TIME_TO_EXPIRY, 0);
    }

    function test_contractActive()
        public
        givenContractActive
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(100, 101, 102);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 102);

        // Assert state
        _assertState(100, 101, 102, TICK_STEP, TIME_TO_EXPIRY, 0);
    }
}
