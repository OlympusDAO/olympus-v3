// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerEnableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodEnabled(address depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);
    }

    // given the contract is not enabled
    //  [X] it succeeds

    function test_givenContractNotEnabled_reverts() public {
        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0);

        // Check the tick is populated
        _assertPreviousTick(0, 0, 0, uint48(block.timestamp));
    }

    // given the deposit asset is already enabled
    //  given the deposit period is already enabled
    //   [X] it reverts

    function test_givenDepositAssetAndPeriodAlreadyEnabled_reverts()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_DepositPeriodAlreadyEnabled.selector,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);
    }

    //  [X] the deposit period is added to the deposit asset's periods array
    //  [X] the deposit asset is not added against to the deposit assets array
    //  [X] the deposit asset and period are enabled
    //  [X] the tick for the deposit asset and period is initialized
    //  [X] an event is emitted

    function test_givenDepositPeriodNotEnabled()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS + 1)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 1);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // given the deposit asset and period were previously enabled
    //  [X] the tick for the deposit asset and period is initialized

    function test_givenDepositAssetAndPeriodPreviouslyEnabled()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenDepositAssetAndPeriodDisabled(iReserveToken, PERIOD_MONTHS)
    {
        // Warp forward, so we know the timestamp will be different
        vm.warp(block.timestamp + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // [X] the deposit period is added to the deposit asset's periods array
    // [X] the deposit asset is added to the deposit assets array
    // [X] the deposit asset and period are enabled
    // [X] the tick for the deposit asset and period is initialized
    // [X] an event is emitted

    function test_success() public givenEnabled {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }
}
