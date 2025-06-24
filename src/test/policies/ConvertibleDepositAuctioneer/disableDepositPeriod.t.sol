// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerDisableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodDisabled(address depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.disableDepositPeriod(iReserveToken, PERIOD_MONTHS);
    }

    // given the deposit asset and period are not enabled
    //  [X] it reverts

    function test_givenDepositAssetAndPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(iReserveToken, PERIOD_MONTHS);
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
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        assertEq(
            auctioneer.isDepositEnabled(iReserveToken, PERIOD_MONTHS),
            false,
            "deposit asset and period disabled"
        );
        assertEq(auctioneer.getDepositAssets().length, 0, "deposit assets length");
        assertEq(auctioneer.getDepositPeriods(iReserveToken).length, 0, "deposit periods length");

        // Check the tick is removed
        _assertPreviousTick(0, 0, 0, 0);
    }

    // [X] it removes the deposit period from the deposit asset's periods array
    // [X] it does not remove the deposit asset from the deposit assets array
    // [X] it disables the deposit asset and period
    // [X] the tick is removed
    // [X] an event is emitted

    function test_givenOtherDepositPeriods()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS + 1)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS + 1, 0, 0);

        // Check the tick is removed
        _assertPreviousTick(0, 0, 0, 0);
    }
}
