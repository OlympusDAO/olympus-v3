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
    //  [X] it does not change the current tick capacity
    //  [X] it does not change the current tick price
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
    //  [X] it sets the parameters
    //  [X] it does not change the current tick capacity
    //  [X] it does not change the current tick price
    //  [X] it emits an event
    // when the new tick size is less than the current tick capacity
    //  [X] the tick capacity is set to the new tick size
    // when the new tick size is >= the current tick capacity
    //  [X] the tick capacity is unchanged
    // when the new min price is > than the current tick price
    //  [X] the tick price is set to the new min price
    // when the new min price is <= the current tick price
    //  [X] the tick price is unchanged

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
        _assertAuctionParameters(100, 101, 102, 0);
    }

    function test_targetZero() public givenInitialized {
        uint256 lastCapacity = auctioneer.getPreviousTick().capacity;
        uint256 lastPrice = auctioneer.getPreviousTick().price;

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 0;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 16e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        _assertPreviousTick(lastCapacity, lastPrice);
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
        auctioneer.setAuctionParameters(21e9, 0, 16e18);
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
        auctioneer.setAuctionParameters(21e9, 11e9, 0);
    }

    function test_contractInactive()
        public
        givenInitialized
        givenRecipientHasBid(1e18)
        givenContractInactive
    {
        uint256 lastCapacity = auctioneer.getPreviousTick().capacity;
        uint256 lastPrice = auctioneer.getPreviousTick().price;

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 16e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        // Values are unchanged
        _assertPreviousTick(lastCapacity, lastPrice);
    }

    function test_contractActive() public givenInitialized givenRecipientHasBid(1e18) {
        uint256 lastCapacity = auctioneer.getPreviousTick().capacity;
        uint256 lastPrice = auctioneer.getPreviousTick().price;

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTarget = 21e9;
        uint256 newTickSize = 11e9;
        uint256 newMinPrice = 16e18;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(newTarget, newTickSize, newMinPrice);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(newTarget, newTickSize, newMinPrice);

        // Assert state
        _assertAuctionParameters(newTarget, newTickSize, newMinPrice, lastUpdate);

        // Assert current tick
        // Values are unchanged
        _assertPreviousTick(lastCapacity, lastPrice);
    }

    function test_newTickSizeLessThanCurrentTickCapacity(
        uint256 newTickSize_
    ) public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTickSize = bound(newTickSize_, 1, TICK_SIZE);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert state
        _assertAuctionParameters(TARGET, newTickSize, MIN_PRICE, lastUpdate);

        // Assert current tick
        // Tick capacity has been adjusted to the new tick size
        _assertPreviousTick(newTickSize, MIN_PRICE);
    }

    function test_newTickSizeGreaterThanCurrentTickCapacity(
        uint256 newTickSize_
    ) public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newTickSize = bound(newTickSize_, TICK_SIZE, 2 * TICK_SIZE);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(TARGET, newTickSize, MIN_PRICE);

        // Assert state
        _assertAuctionParameters(TARGET, newTickSize, MIN_PRICE, lastUpdate);

        // Assert current tick
        // Tick capacity has been unchanged
        _assertPreviousTick(TICK_SIZE, MIN_PRICE);
    }

    function test_newMinPriceGreaterThanCurrentTickPrice(
        uint256 newMinPrice_
    ) public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newMinPrice = bound(newMinPrice_, MIN_PRICE + 1, 2 * MIN_PRICE);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, newMinPrice, lastUpdate);

        // Assert current tick
        // Tick price has been set to the new min price
        _assertPreviousTick(TICK_SIZE, newMinPrice);
    }

    function test_newMinPriceLessThanCurrentTickPrice(
        uint256 newMinPrice_
    ) public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        uint256 newMinPrice = bound(newMinPrice_, 1, MIN_PRICE);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, newMinPrice);

        // Assert state
        _assertAuctionParameters(TARGET, TICK_SIZE, newMinPrice, lastUpdate);

        // Assert current tick
        // Tick price has been unchanged
        _assertPreviousTick(TICK_SIZE, MIN_PRICE);
    }
}
