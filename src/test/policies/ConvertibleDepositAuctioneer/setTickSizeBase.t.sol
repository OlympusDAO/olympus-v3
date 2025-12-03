// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerTickSizeBaseTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the admin or manager role
    //  [X] it reverts
    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.setTickSizeBase(2e18);
    }

    // when the base is out of bounds
    //  [X] it reverts
    function test_valueIsBelowLowerBound_reverts(uint256 base_) public {
        uint256 base = bound(base_, 0, 1e18 - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size base"
            )
        );

        vm.prank(admin);
        auctioneer.setTickSizeBase(base);
    }

    function test_valueIsAboveUpperBound_reverts(uint256 base_) public {
        uint256 base = bound(base_, 10e18 + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "tick size base"
            )
        );

        vm.prank(admin);
        auctioneer.setTickSizeBase(base);
    }

    // when setting a valid base
    //  [X] it updates storage and emits event
    function test_setsBase(uint256 newBase_) public {
        newBase_ = bound(newBase_, 1e18, 10e18);

        vm.expectEmit(true, true, true, true);
        emit TickSizeBaseUpdated(address(iReserveToken), newBase_);

        vm.prank(admin);
        auctioneer.setTickSizeBase(newBase_);

        assertEq(auctioneer.getTickSizeBase(), newBase_, "tick size base");
    }

    // when active with pending capacity evolution
    //  [X] it does not retroactively change prior ticks; changes apply on next bid
    function test_doesNotRetroactivelyChangePriorTicks()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(3e18)
    {
        // Capture current tick
        IConvertibleDepositAuctioneer.Tick memory tickPre = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );
        uint256 tickSizePre = auctioneer.getCurrentTickSize();

        // Change base
        vm.prank(admin);
        auctioneer.setTickSizeBase(150e16); // 1.5x

        // Advance time to accrue capacity
        vm.warp(block.timestamp + 4 hours);

        // Ensure previous tick remains unchanged until next bid
        _assertPreviousTick(tickPre.capacity, tickPre.price, tickSizePre, tickPre.lastUpdate);
    }
}
