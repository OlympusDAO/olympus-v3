// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerTimeToExpiryTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "admin" role
    //  [X] it reverts
    // when the new time to expiry is 0
    //  [X] it reverts
    // given the contract is not initialized
    //  [X] it sets the time to expiry
    // when the contract is deactivated
    //  [X] it sets the time to expiry
    // [X] it sets the time to expiry
    // [X] it emits an event

    function test_callerDoesNotHaveCdAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        auctioneer.setTimeToExpiry(100);
    }

    function test_contractNotInitialized() public {
        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(100);

        // Assert state
        assertEq(auctioneer.getTimeToExpiry(), 100, "time to expiry");
    }

    function test_newTimeToExpiryZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "time to expiry"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(0);
    }

    function test_contractInactive() public {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(100);

        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(100);

        // Assert state
        assertEq(auctioneer.getTimeToExpiry(), 100, "time to expiry");
    }

    function test_contractActive(uint48 timeToExpiry_) public givenEnabled {
        uint48 timeToExpiry = uint48(bound(timeToExpiry_, 1, 1 weeks));

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(timeToExpiry);

        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(timeToExpiry);

        // Assert state
        assertEq(auctioneer.getTimeToExpiry(), timeToExpiry, "time to expiry");
    }
}
