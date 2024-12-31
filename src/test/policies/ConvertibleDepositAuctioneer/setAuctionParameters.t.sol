// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerAuctionParametersTest is ConvertibleDepositAuctioneerTest {
    event AuctionParametersUpdated(uint256 newTarget, uint256 newTickSize, uint256 newMinPrice);

    // when the caller does not have the "heart" role
    //  [X] it reverts
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

    function test_contractInactive() public givenContractInactive {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(100, 101, 102);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 102);

        // Assert state
        assertEq(auctioneer.target(), 100);
        assertEq(auctioneer.tickSize(), 101);
        assertEq(auctioneer.minPrice(), 102);
    }

    function test_contractActive() public givenContractActive {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdated(100, 101, 102);

        // Call function
        vm.prank(heart);
        auctioneer.setAuctionParameters(100, 101, 102);

        // Assert state
        assertEq(auctioneer.target(), 100);
        assertEq(auctioneer.tickSize(), 101);
        assertEq(auctioneer.minPrice(), 102);
    }
}
