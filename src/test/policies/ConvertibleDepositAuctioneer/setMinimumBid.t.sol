// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerMinimumBidTest is ConvertibleDepositAuctioneerTest {
    // ========== TESTS ========== //

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.setMinimumBid(1000e18);
    }

    // given the contract is not enabled
    //  [X] it sets the minimum bid

    function test_contractNotEnabled() public {
        uint256 minimumBid = 1000e18;

        // Call function
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Assert state
        assertEq(auctioneer.getMinimumBid(), minimumBid, "minimum bid");
    }

    // when setting minimum bid to 0
    //  [X] it sets the minimum bid to 0 (disables minimum)
    //

    function test_setMinimumBidToZero() public givenEnabled {
        // First set a non-zero minimum bid
        vm.prank(admin);
        auctioneer.setMinimumBid(1000e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MinimumBidUpdated(address(iReserveToken), 0);

        // Then set it to 0
        vm.prank(admin);
        auctioneer.setMinimumBid(0);

        // Assert state
        assertEq(auctioneer.getMinimumBid(), 0, "minimum bid");
    }

    // when setting minimum bid to non-zero value
    //  [X] it sets the minimum bid
    //  [X] it emits an event

    function test_setMinimumBidToNonZero(uint256 minimumBid_) public givenEnabled {
        uint256 minimumBid = bound(minimumBid_, 1, type(uint256).max);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MinimumBidUpdated(address(iReserveToken), minimumBid);

        // Call function
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Assert state
        assertEq(auctioneer.getMinimumBid(), minimumBid, "minimum bid");
    }

    // when the contract is active
    //  [X] it sets the minimum bid
    //  [X] it emits an event

    function test_contractActive(
        uint256 minimumBid_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        uint256 minimumBid = bound(minimumBid_, 0, type(uint256).max);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MinimumBidUpdated(address(iReserveToken), minimumBid);

        // Call function
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Assert state
        assertEq(auctioneer.getMinimumBid(), minimumBid, "minimum bid");
    }

    // when manager calls the function
    //  [X] it sets the minimum bid
    //  [X] it emits an event

    function test_managerCanSetMinimumBid(uint256 minimumBid_) public {
        uint256 minimumBid = bound(minimumBid_, 0, type(uint256).max);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MinimumBidUpdated(address(iReserveToken), minimumBid);

        // Call function as manager
        vm.prank(manager);
        auctioneer.setMinimumBid(minimumBid);

        // Assert state
        assertEq(auctioneer.getMinimumBid(), minimumBid, "minimum bid");
    }
}
