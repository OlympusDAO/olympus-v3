// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerActivateTest is ConvertibleDepositAuctioneerTest {
    event Activated();

    // when the caller does not have the "emergency_shutdown" role
    //  [X] it reverts
    // when the contract is already activated
    //  [X] the state is unchanged
    //  [X] it does not emit an event
    // when the contract is not activated
    //  [X] it activates the contract
    //  [X] it emits an event

    function test_callerDoesNotHaveEmergencyShutdownRole_reverts(address caller_) public {
        // Ensure caller is not emergency address
        vm.assume(caller_ != emergency);

        // Expect revert
        _expectRoleRevert("emergency_shutdown");

        // Call function
        vm.prank(caller_);
        auctioneer.activate();
    }

    function test_contractActivated() public givenContractActive {
        // Expect no events
        vm.expectEmit(0);

        // Call function
        vm.prank(emergency);
        auctioneer.activate();

        // Assert state
        assertEq(auctioneer.locallyActive(), true);
    }

    function test_contractInactive() public givenContractInactive {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Activated();

        // Call function
        vm.prank(emergency);
        auctioneer.activate();

        // Assert state
        assertEq(auctioneer.locallyActive(), true);
    }
}
