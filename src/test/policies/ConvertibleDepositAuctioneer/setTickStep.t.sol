// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerTickStepTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "admin" role
    //  [X] it reverts
    // given the contract is not initialized
    //  [X] it sets the tick step
    // when the value is < 100e2
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the tick step
    // [X] it sets the tick step
    // [X] it emits an event

    function test_callerDoesNotHaveCdAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("admin");

        // Call function
        vm.prank(caller_);
        auctioneer.setTickStep(100e2);
    }

    function test_contractNotInitialized() public {
        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(100e2);

        // Assert state
        assertEq(auctioneer.getTickStep(), 100e2, "tick step");
    }

    function test_valueIsOutOfBounds_reverts(uint24 tickStep_) public {
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
        auctioneer.setTickStep(tickStep);
    }

    function test_contractInactive(uint24 tickStep_) public {
        uint24 tickStep = uint24(bound(tickStep_, 100e2, type(uint24).max));

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(tickStep);

        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(tickStep);

        // Assert state
        assertEq(auctioneer.getTickStep(), tickStep, "tick step");
    }

    function test_contractActive(uint24 tickStep_) public givenEnabled {
        uint24 tickStep = uint24(bound(tickStep_, 100e2, type(uint24).max));

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(tickStep);

        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(tickStep);

        // Assert state
        assertEq(auctioneer.getTickStep(), tickStep, "tick step");
    }
}
