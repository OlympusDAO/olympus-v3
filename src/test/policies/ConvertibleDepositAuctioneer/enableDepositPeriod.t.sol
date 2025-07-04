// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

contract ConvertibleDepositAuctioneerEnableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodEnabled(address indexed depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the contract is not enabled
    //  [X] it succeeds

    function test_givenContractNotEnabled() public {
        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(0, 0, 0, uint48(block.timestamp));
    }

    // when the deposit period is zero
    //  [X] it reverts

    function test_whenDepositPeriodIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "deposit period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(0);
    }

    // given the deposit period is already enabled
    //  [X] it reverts

    function test_givenDepositPeriodAlreadyEnabled_reverts()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_DepositPeriodAlreadyEnabled.selector,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period was previously enabled
    //  [X] the tick for the deposit period is initialized

    function test_givenDepositPeriodPreviouslyEnabled()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodDisabled(PERIOD_MONTHS)
    {
        // Warp forward, so we know the timestamp will be different
        vm.warp(block.timestamp + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // given there is another deposit period enabled
    //  [X] the deposit period is added to the deposit periods array
    //  [X] the deposit period is enabled
    //  [X] the tick for the deposit period is initialized
    //  [X] an event is emitted

    function test_givenOtherDepositPeriodEnabled()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS + 1);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS + 1);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS + 1, 1);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // [X] the deposit period is added to the deposit periods array
    // [X] the deposit period is enabled
    // [X] the tick for the deposit period is initialized
    // [X] an event is emitted

    function test_success() public givenEnabled {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }
}
