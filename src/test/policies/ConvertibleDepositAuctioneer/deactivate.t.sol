// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerDeactivateTest is ConvertibleDepositAuctioneerTest {
    event Deactivated();

    // when the caller does not have the "emergency_shutdown" role
    //  [X] it reverts
    // when the contract is already deactivated
    //  [X] the state is unchanged
    //  [X] it does not emit an event
    // when the contract is active
    //  [X] it deactivates the contract
    //  [X] it emits an event

    function test_callerDoesNotHaveEmergencyShutdownRole_reverts(address caller_) public {
        // Ensure caller is not emergency address
        vm.assume(caller_ != emergency);

        // Expect revert
        _expectRoleRevert("emergency_shutdown");

        // Call function
        vm.prank(caller_);
        auctioneer.deactivate();
    }

    function test_contractInactive() public givenInitialized givenContractInactive {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Call function
        vm.prank(emergency);
        auctioneer.deactivate();

        // Assert state
        assertEq(auctioneer.locallyActive(), false);
        // lastUpdate has not changed
        assertEq(auctioneer.getState().lastUpdate, lastUpdate);
    }

    function test_contractActive() public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Deactivated();

        // Call function
        vm.prank(emergency);
        auctioneer.deactivate();

        // Assert state
        assertEq(auctioneer.locallyActive(), false);
        // lastUpdate has not changed
        assertEq(auctioneer.getState().lastUpdate, lastUpdate);
    }
}
