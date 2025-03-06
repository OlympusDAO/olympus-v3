// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerRedemptionPeriodTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "admin" role
    //  [X] it reverts
    // when the new redemption period is 0
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the redemption period
    // [X] it sets the redemption period
    // [X] it emits an event

    function test_callerDoesNotHaveCdAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        auctioneer.setRedemptionPeriod(100);
    }

    function test_newRedemptionPeriodZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "redemption period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.setRedemptionPeriod(0);
    }

    function test_contractDisabled() public {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionPeriodUpdated(100);

        // Call function
        vm.prank(admin);
        auctioneer.setRedemptionPeriod(100);

        // Assert state
        assertEq(auctioneer.getRedemptionPeriod(), 100, "redemption period");
    }

    function test_contractActive(uint48 redemptionPeriod_) public givenEnabled {
        uint48 redemptionPeriod = uint48(bound(redemptionPeriod_, 1, 1 weeks));

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit RedemptionPeriodUpdated(redemptionPeriod);

        // Call function
        vm.prank(admin);
        auctioneer.setRedemptionPeriod(redemptionPeriod);

        // Assert state
        assertEq(auctioneer.getRedemptionPeriod(), redemptionPeriod, "redemption period");
    }
}
