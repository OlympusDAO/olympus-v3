// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerAuctionParametersTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "heart" role
    //  [X] it reverts
    // given the contract is not initialized
    //  [X] it sets the parameters
    // when the new target is 0
    //  [X] it succeeds
    //  [X] the current tick capacity is the new tick size
    // when the new tick size is 0
    //  [X] it reverts
    // when the new min price is 0
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the parameters
    //  [X] it emits an event
    //  [X] it does not change the current tick capacity
    //  [X] it does not change the current tick price
    // given the tick price has never been set
    // [X] it sets the parameters
    // [X] it emits an event
    // [X] it does not set the tick capacity
    // [X] it does not set the tick price

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

    function test_contractNotInitialized() public {
        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 102);

        // Assert state
        _assertState(100, 101, 102, 0);
    }

    function test_targetZero() public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 0;
        uint256 newTickSize = 101;
        uint256 newMinPrice = 102;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertState(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        _assertCurrentTick(newTickSize, newMinPrice);
    }

    function test_tickSizeZero_reverts() public givenInitialized {
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

    function test_minPriceZero_reverts() public givenInitialized {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "min price"
            )
        );

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 0);
    }

    function test_contractInactive()
        public
        givenInitialized
        givenRecipientHasBid(1e18)
        givenContractInactive
    {
        uint256 lastCapacity = auctioneer.getCurrentTick().capacity;
        uint256 lastPrice = auctioneer.getCurrentTick().price;

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 100;
        uint256 newTickSize = 101;
        uint256 newMinPrice = 102;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertState(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        // Values are unchanged
        _assertCurrentTick(lastCapacity, lastPrice);
    }

    function test_contractActive() public givenInitialized givenRecipientHasBid(1e18) {
        uint256 lastCapacity = auctioneer.getCurrentTick().capacity;
        uint256 lastPrice = auctioneer.getCurrentTick().price;

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 100;
        uint256 newTickSize = 101;
        uint256 newMinPrice = 102;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertState(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        // Values are unchanged
        _assertCurrentTick(lastCapacity, lastPrice);
    }
}
