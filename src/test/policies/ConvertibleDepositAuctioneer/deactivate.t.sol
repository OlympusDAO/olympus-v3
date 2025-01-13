// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerDeactivateTest is ConvertibleDepositAuctioneerTest {
    event Deactivated();

    // when the caller does not have the "emergency_shutdown" role
    //  [X] it reverts
    // when the contract is already deactivated
    //  [X] it reverts
    // when the contract is active
    //  [X] it deactivates the contract
    //  [X] it emits an event
    //  [X] the day state is unchanged
    //  [X] the auction results history and index are unchanged

    function test_callerDoesNotHaveEmergencyShutdownRole_reverts(address caller_) public {
        // Ensure caller is not emergency address
        vm.assume(caller_ != emergency);

        // Expect revert
        _expectRoleRevert("emergency_shutdown");

        // Call function
        vm.prank(caller_);
        auctioneer.deactivate();
    }

    function test_contractInactive_reverts() public givenInitialized givenContractInactive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.CDAuctioneer_InvalidState.selector)
        );

        // Call function
        vm.prank(emergency);
        auctioneer.deactivate();
    }

    function test_contractActive() public givenInitialized givenRecipientHasBid(1e18) {
        // Cache auction results
        int256[] memory auctionResults = auctioneer.getAuctionResults();
        uint8 nextIndex = auctioneer.getAuctionResultsNextIndex();

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
        assertEq(auctioneer.getPreviousTick().lastUpdate, lastUpdate);
        // Auction results are unchanged
        _assertAuctionResults(
            auctionResults[0],
            auctionResults[1],
            auctionResults[2],
            auctionResults[3],
            auctionResults[4],
            auctionResults[5],
            auctionResults[6]
        );
        // Auction results index is unchanged
        _assertAuctionResultsNextIndex(nextIndex);
    }
}
