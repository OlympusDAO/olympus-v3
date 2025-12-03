// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

contract ConvertibleDepositAuctioneerDisableTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "emergency" role
    //  [X] it reverts

    function test_callerDoesNotHaveEmergencyRole_reverts(address caller_) public givenEnabled {
        // Ensure caller is not emergency or admin address
        vm.assume(caller_ != emergency && caller_ != admin);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));

        // Call function
        vm.prank(caller_);
        auctioneer.disable("");
    }

    // when the contract is already disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectNotEnabledRevert();

        // Call function
        vm.prank(emergency);
        auctioneer.disable("");
    }

    // when the contract is enabled
    //  [X] it deactivates the contract
    //  [X] it emits an event
    //  [X] the day state is unchanged
    //  [X] the auction results history and index are unchanged

    function test_contractEnabled()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(1e18)
    {
        // Cache auction results
        int256[] memory auctionResults = auctioneer.getAuctionResults();
        uint8 nextIndex = auctioneer.getAuctionResultsNextIndex();

        uint48 lastUpdate = uint48(block.timestamp);

        // Warp to change the block timestamp
        vm.warp(lastUpdate + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Disabled();

        // Call function
        vm.prank(emergency);
        auctioneer.disable("");

        // Assert state
        assertEq(auctioneer.isEnabled(), false);
        // lastUpdate has not changed
        assertEq(auctioneer.getPreviousTick(PERIOD_MONTHS).lastUpdate, lastUpdate);
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

    /// @notice Test that pending changes are preserved when contract is disabled
    function test_pendingChangesPreservedOnDisable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Queue multiple changes
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS_TWO);

        // Verify pending changes exist
        (bool enabled1, bool pending1) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        (bool enabled2, bool pending2) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS_TWO);
        assertEq(enabled1, true, "period 1 should be enabled");
        assertEq(pending1, false, "period 1 should be pending disabled");
        assertEq(enabled2, false, "period 2 should not be enabled");
        assertEq(pending2, true, "period 2 should be pending enabled");

        // Disable the contract (should preserve pending changes)
        vm.prank(emergency);
        auctioneer.disable("");

        // Verify pending changes are preserved
        (bool finalEnabled1, bool finalPending1) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        (bool finalEnabled2, bool finalPending2) = auctioneer.isDepositPeriodEnabled(
            PERIOD_MONTHS_TWO
        );
        assertEq(finalEnabled1, true, "period 1 should still be enabled");
        assertEq(finalPending1, false, "period 1 should still be pending disabled");
        assertEq(finalEnabled2, false, "period 2 should still not be enabled");
        assertEq(finalPending2, true, "period 2 should still be pending enabled");

        // Verify contract is disabled
        assertEq(auctioneer.isEnabled(), false, "contract should be disabled");
    }

    /// @notice Test that empty pending changes don't cause issues on disable
    function test_emptyPendingChangesOnDisable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // No pending changes queued - verify current state
        (bool enabled, bool pending) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(enabled, true, "period should be enabled");
        assertEq(pending, true, "pending should match current (no changes queued)");

        // Should only emit the Disabled event
        vm.expectEmit(true, true, true, true);
        emit Disabled();

        // Disable the contract
        vm.prank(emergency);
        auctioneer.disable("");

        // Verify contract is disabled and state unchanged
        assertEq(auctioneer.isEnabled(), false, "contract should be disabled");
        (bool finalEnabled, bool finalPending) = auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS);
        assertEq(finalEnabled, true, "period should still be enabled");
        assertEq(finalPending, true, "pending should still match current");
    }
}
