// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

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
        givenTickSize(TICK_SIZE)
        givenContractInactive
    {
        uint48 lastUpdate = block.timestamp;

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(100);

        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(100);

        // Assert state
        _assertState(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, 100, lastUpdate);
    }

    function test_contractActive(
        uint48 timeToExpiry_
    )
        public
        givenContractActive
        givenAuctionParametersStandard
        givenTickStep(TICK_STEP)
        givenTickSize(TICK_SIZE)
    {
        uint48 timeToExpiry = uint48(bound(timeToExpiry_, 1, 1 years));

        uint48 lastUpdate = block.timestamp;

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TimeToExpiryUpdated(timeToExpiry);

        // Call function
        vm.prank(admin);
        auctioneer.setTimeToExpiry(timeToExpiry);

        // Assert state
        _assertState(TARGET, TICK_SIZE, MIN_PRICE, TICK_STEP, timeToExpiry, lastUpdate);
    }
}
