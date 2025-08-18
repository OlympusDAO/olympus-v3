// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerDisableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodDisabled(address indexed depositAsset, uint8 depositPeriod);

    // given the contract is not enabled
    //  [X] it reverts

    function test_givenContractNotEnabled_reverts() public {
        // Expect revert
        _expectNotEnabledRevert();

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public givenEnabled {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period is not enabled
    //  [X] it reverts

    function test_givenDepositPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given there are no other deposit periods for the deposit asset
    //  [X] it removes the deposit period from the deposit asset's periods array
    //  [X] it removes the deposit asset from the deposit assets array
    //  [X] it disables the deposit asset and period
    //  [X] the tick is removed
    //  [X] an event is emitted

    function test_givenNoOtherDepositPeriods()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            false,
            "deposit period disabled"
        );
        assertEq(auctioneer.getDepositPeriods().length, 0, "deposit periods length");
        assertEq(auctioneer.getDepositPeriodsCount(), 0, "deposit periods count");

        // Check the tick is removed
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }

    // [X] it removes the deposit period from the deposit periods array
    // [X] it disables the deposit period
    // [X] the tick is removed
    // [X] an event is emitted

    function test_givenOtherDepositPeriods()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS + 1, 0);

        // Check the tick is removed
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }
}
