// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerActivateTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "emergency_shutdown" role
    //  [X] it reverts
    // given the contract is not initialized
    //  [X] it reverts
    // when the contract is already activated
    //  [X] the state is unchanged
    //  [X] it does not emit an event
    //  [X] it does not change the last update
    // when the contract is not activated
    //  [X] it activates the contract
    //  [X] it emits an event
    //  [X] it sets the last update to the current block timestamp

    function test_callerDoesNotHaveEmergencyShutdownRole_reverts(address caller_) public {
        // Ensure caller is not emergency address
        vm.assume(caller_ != emergency);

        // Expect revert
        _expectRoleRevert("emergency_shutdown");

        // Call function
        vm.prank(caller_);
        auctioneer.activate();
    }

    function test_contractNotInitialized() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_NotInitialized.selector
            )
        );

        // Call function
        vm.prank(emergency);
        auctioneer.activate();
    }

    function test_contractActivated() public givenInitialized {
        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Call function
        vm.prank(emergency);
        auctioneer.activate();

        // Assert state
        assertEq(auctioneer.locallyActive(), true);
        // lastUpdate has not changed
        assertEq(auctioneer.getAuctionParameters().lastUpdate, lastUpdate);
    }

    function test_contractInactive() public givenInitialized givenContractInactive {
        uint48 lastUpdate = uint48(block.timestamp);
        uint48 newBlock = lastUpdate + 1;

        // Warp to change the block timestamp
        vm.warp(newBlock);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Activated();

        // Call function
        vm.prank(emergency);
        auctioneer.activate();

        // Assert state
        assertEq(auctioneer.locallyActive(), true);
        // lastUpdate has changed
        assertEq(auctioneer.getAuctionParameters().lastUpdate, newBlock);
    }
}
