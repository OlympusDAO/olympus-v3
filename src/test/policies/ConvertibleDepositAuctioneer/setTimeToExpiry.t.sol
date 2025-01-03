// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerTimeToExpiryTest is ConvertibleDepositAuctioneerTest {
    event TimeToExpiryUpdated(uint48 newTimeToExpiry);

    // when the caller does not have the "cd_admin" role
    //  [X] it reverts
    // when the new time to expiry is 0
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the time to expiry
    // [X] it sets the time to expiry
    // [X] it emits an event

    function test_callerDoesNotHaveCdAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("cd_admin");

        // Call function
        vm.prank(caller_);
        auctioneer.setTimeToExpiry(100);
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

    function test_contractInactive()
        public
        givenContractActive
        givenAuctionParametersStandard
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
        givenContractInactive
    {
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

    function test_contractActive(
        uint48 timeToExpiry_
    )
        public
        givenContractActive
        givenAuctionParametersStandard
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
    {
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
