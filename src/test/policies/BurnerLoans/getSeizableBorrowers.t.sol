// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansGetSeizableBorrowersTest is BurnerLoansSeizureTestBase {
    // getSeizableBorrowers
    // given no active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns empty
    function test_givenNoActiveBorrowers_getSeizableBorrowersReturnsEmpty() public view {
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 10, 10);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given return limit above maximum
    //  when getSeizableBorrowers is called
    //   then it reverts
    function testFuzz_givenReturnLimitAboveMaximum_getSeizableBorrowers_reverts(
        uint256 returnLimit_
    ) public {
        uint256 returnLimit = bound(returnLimit_, 51, 100);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 100, returnLimit);
    }

    // getSeizableBorrowers
    // given policy disabled
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenPolicyDisabled_getSeizableBorrowers_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 10, 10);
    }

    // getSeizableBorrowers
    // given stale prices
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenStalePrices_getSeizableBorrowers_reverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 1, 1);
    }

    // getSeizableBorrowers
    // given mixed active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns only eligible positions
    function test_givenMixedActiveBorrowers_getSeizableBorrowersReturnsOnlyEligiblePositions()
        public
    {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 2, 2);

        assertEq(borrowers.length, 1, "seizable count");
        assertEq(borrowers[0], alice, "seizable borrower");
        assertEq(nextIndex, 0, "wrapped cursor");
        assertGt(reward, 0, "keeper reward");
    }

    // getSeizableBorrowers
    // given protocol seizer
    //  when getSeizableBorrowers is called
    //   then it returns zero reward
    function test_givenProtocolSeizer_getSeizableBorrowersReturnsZeroReward() public {
        _makeUnhealthy(alice);

        vm.prank(protocolSeizer);
        (address[] memory borrowers, , uint256 reward) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrower count");
        assertEq(reward, 0, "protocol reward");
    }

    // getSeizableBorrowers
    // given return limit
    //  when getSeizableBorrowers is called
    //   then it stops at limit
    function test_givenReturnLimit_getSeizableBorrowersStopsAtLimit() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 2_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            2,
            1
        );

        assertEq(borrowers.length, 1, "return limit");
        assertEq(nextIndex, 1, "next cursor");
    }

    // getSeizableBorrowers
    // given zero check limit
    //  when getSeizableBorrowers is called
    //   then it returns empty without advancing
    function test_givenZeroCheckLimit_getSeizableBorrowersReturnsEmptyWithoutAdvancing() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 0, 1);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given start at end
    //  when getSeizableBorrowers is called
    //   then it wraps to zero
    function test_givenStartAtEnd_getSeizableBorrowersWrapsToZero() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            1,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrowers");
        assertEq(nextIndex, 0, "wrapped cursor");
    }
}
