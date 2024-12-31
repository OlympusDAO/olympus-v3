// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerTickStepTest is ConvertibleDepositAuctioneerTest {
    event TickStepUpdated(uint256 newTickStep);

    // when the caller does not have the "cd_admin" role
    //  [X] it reverts
    // when the value is 0
    //  [X] it reverts
    // when the contract is deactivated
    //  [X] it sets the tick step
    // [X] it sets the tick step
    // [X] it emits an event

    function test_callerDoesNotHaveCdAdminRole_reverts(address caller_) public {
        // Ensure caller is not admin
        vm.assume(caller_ != admin);

        // Expect revert
        _expectRoleRevert("cd_admin");

        // Call function
        vm.prank(caller_);
        auctioneer.setTickStep(100);
    }

    function test_valueIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "tick step"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(0);
    }

    function test_contractInactive() public givenContractInactive {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(100);

        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(100);

        // Assert state
        assertEq(auctioneer.tickStep(), 100);
    }

    function test_contractActive(uint256 tickStep_) public givenContractActive {
        uint256 tickStep = bound(tickStep_, 1, 10e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TickStepUpdated(tickStep_);

        // Call function
        vm.prank(admin);
        auctioneer.setTickStep(tickStep_);

        // Assert state
        assertEq(auctioneer.tickStep(), tickStep_);
    }
}
