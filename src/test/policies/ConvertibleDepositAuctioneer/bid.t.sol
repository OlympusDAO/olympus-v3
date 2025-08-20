// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

import {FullMath} from "src/libraries/FullMath.sol";

import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositAuctioneerBidTest is ConvertibleDepositAuctioneerTest {
    uint256 public constant LARGE_MINT_AMOUNT = 200e18;

    event Bid(
        address indexed bidder,
        address indexed depositAsset,
        uint8 indexed depositPeriod,
        uint256 depositAmount,
        uint256 convertedAmount,
        uint256 positionId
    );

    function _assertConvertibleDepositPosition(
        uint256 bidAmount_,
        uint256 expectedConvertedAmount_,
        uint256 expectedReserveTokenBalance_,
        uint256 previousConvertibleDepositBalance_,
        uint256 previousPositionCount_,
        uint256 returnedOhmOut_,
        uint256 returnedPositionId_,
        uint256 returnedReceiptTokenId_
    ) internal view {
        // Assert that the converted amount is as expected
        assertEq(returnedOhmOut_, expectedConvertedAmount_, "converted amount");

        // Assert that the receipt tokens were transferred to the recipient
        assertEq(
            depositManager.balanceOf(recipient, receiptTokenId),
            previousConvertibleDepositBalance_ + bidAmount_,
            "receipt token balance"
        );

        // Assert that the reserve tokens were transferred from the recipient
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedReserveTokenBalance_,
            "reserve token balance"
        );

        // Assert that the CD position terms were created
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, previousPositionCount_ + 1, "position count");
        assertEq(positionIds[positionIds.length - 1], returnedPositionId_, "position id");

        uint256 conversionPrice = FullMath.mulDivUp(bidAmount_, 1e9, expectedConvertedAmount_);

        // Assert that the position terms are correct
        IDepositPositionManager.Position memory position = convertibleDepositPositions.getPosition(
            returnedPositionId_
        );
        assertEq(position.owner, recipient, "position owner");
        assertEq(position.remainingDeposit, bidAmount_, "position remaining deposit");
        assertEq(position.conversionPrice, conversionPrice, "position conversion price");
        assertEq(
            position.expiry,
            uint48(block.timestamp) + (30 days) * PERIOD_MONTHS,
            "position expiry"
        );
        assertEq(position.wrapped, false, "position wrapped");
        assertEq(position.asset, address(reserveToken), "position deposit token");
        assertEq(position.periodMonths, PERIOD_MONTHS, "position period months");

        // Assert that the receipt token id is accurate
        uint256 receiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );
        assertEq(returnedReceiptTokenId_, receiptTokenId, "receipt token id");
    }

    function _expectBidEvent(
        uint256 bidAmount_,
        uint256 convertedAmount_,
        uint256 positionId_
    ) internal {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Bid(
            recipient,
            address(iReserveToken),
            PERIOD_MONTHS,
            bidAmount_,
            convertedAmount_,
            positionId_
        );
    }

    function _assertActualAmount(
        uint256 actualAmount_,
        uint256 previousReceiptBalance_
    ) internal view {
        // Assert that the actual amount matches the increase in receipt token balance
        uint256 currentReceiptBalance = depositManager.balanceOf(recipient, receiptTokenId);
        uint256 receiptTokensReceived = currentReceiptBalance - previousReceiptBalance_;
        assertEq(
            actualAmount_,
            receiptTokensReceived,
            "actual amount should match receipt tokens received"
        );
    }

    // when the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectNotEnabledRevert();

        // Call function
        auctioneer.bid(PERIOD_MONTHS, 1e18, 1, false, false);
    }

    // given the deposit period is not enabled
    //  [X] it reverts

    function test_givenDepositPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        auctioneer.bid(PERIOD_MONTHS, 1e18, 1, false, false);
    }

    // when the caller has not approved DepositManager to spend the bid token
    //  [X] it reverts

    function test_givenSpendingNotApproved_reverts()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 1e18, 1, false, false);
    }

    // when the "cd_auctioneer" role is not granted to the auctioneer contract
    //  [X] it reverts

    function test_givenAuctioneerRoleNotGranted_reverts()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // Revoke the auctioneer role
        rolesAdmin.revokeRole("cd_auctioneer", address(auctioneer));

        // Expect revert
        _expectRoleRevert("cd_auctioneer");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 1e18, 1, false, false);
    }

    // when the OHM out is less than the minimum OHM out
    //  [X] it reverts

    function test_whenLessThanMinimumOhmOut_reverts(
        uint256 bidAmount_,
        uint256 minOhmOut_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // We want the converted amount to be less than the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 = 10e9 - 1
        // Bid amount = (10e9 - 1) * 15e18 / 1e9
        // Bid amount = 150e18 - 1 (it will round down)
        bidAmount_ = bound(bidAmount_, 1e18, 150e18 - 1);
        uint256 expectedConvertedAmount = (bidAmount_ * 1e9) / 15e18;
        minOhmOut_ = bound(minOhmOut_, expectedConvertedAmount + 1, type(uint256).max); // Ensure minOhmOut is greater than the expected converted amount

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_ConvertedAmountSlippage
                    .selector,
                expectedConvertedAmount,
                minOhmOut_
            )
        );

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount_, minOhmOut_, false, false);
    }

    // when the bid amount converted is 0
    //  [X] it reverts

    function test_givenBidAmountConvertedIsZero_reverts(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // We want a bid amount that will result in a converted amount of 0
        // Given bid amount * 1e9 / 15e18 = converted amount
        // When bid amount = 15e9, the converted amount = 1
        uint256 bidAmount = bound(bidAmount_, 0, 15e9 - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_ConvertedAmountZero
                    .selector
            )
        );

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);
    }

    // given the deposit asset has 6 decimals
    //  [X] the conversion price is correct

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(TARGET, TICK_SIZE, 15e6)
        givenAddressHasReserveToken(recipient, 3e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 3e6)
    {
        // Expected converted amount
        // 3e6 * 1e9 / 15e6 = 2e8
        uint256 bidAmount = 3e6;
        uint256 expectedConvertedAmount = 2e8;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, 15e6);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - expectedConvertedAmount,
            15e6,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    // when the bid is the first bid
    //  [X] it sets the day's deposit balance
    //  [X] it sets the day's converted balance
    //  [X] it sets the current tick size to the standard tick size
    //  [X] it sets the lastUpdate to the current block timestamp
    //  [X] it deducts the converted amount from the tick capacity
    //  [X] it sets the current tick size to the standard tick size
    //  [X] it does not update the tick price
    //  [X] the position is not wrapped as an ERC721

    function test_givenFirstBid()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 3e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 3e18)
    {
        // Expected converted amount
        // 3e18 * 1e9 / 15e18 = 2e8
        uint256 bidAmount = 3e18;
        uint256 expectedConvertedAmount = 2e8;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - expectedConvertedAmount,
            MIN_PRICE,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    // when the bid is the first bid of the day
    //  [X] the day state is not reset
    //  [X] it updates the day's deposit balance
    //  [X] it updates the day's converted balance
    //  [X] it sets the current tick size to the standard tick size
    //  [X] it sets the lastUpdate to the current block timestamp

    function test_givenFirstBidOfDay()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(120e18)
        givenAddressHasReserveToken(recipient, 6e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 6e18)
    {
        // Warp to the next day
        uint48 nextDay = uint48(block.timestamp) + 1 days;
        vm.warp(nextDay);

        // Mimic auction parameters being set
        _setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Get the current tick for the new day
        IConvertibleDepositAuctioneer.Tick memory beforeTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Expected converted amount
        // 6e18 * 1e9 / 15e18 = 4e8
        uint256 bidAmount = 6e18;
        uint256 expectedConvertedAmount = 4e8;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 1);

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            120e18,
            1,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        // Not affected by the previous day's bid
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            beforeTick.capacity - expectedConvertedAmount,
            beforeTick.price,
            TICK_SIZE,
            uint48(nextDay)
        );
    }

    // when the bid is not the first bid of the day
    //  [X] it does not reset the day's deposit and converted balances
    //  [X] it updates the day's deposit balance
    //  [X] it updates the day's converted balance
    //  [X] it sets the current tick size to the standard tick size
    //  [X] it sets the lastUpdate to the current block timestamp

    /// forge-config: default.isolate = true
    function test_secondBidUpdatesDayState()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(3e18)
        givenAddressHasReserveToken(recipient, 6e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 6e18)
    {
        // Previous converted amount
        // 3e18 * 1e9 / 15e18 = 2e8
        // uint256 previousBidAmount = 3e18;
        uint256 previousConvertedAmount = 2e8;

        // Expected converted amount
        // 6e18 * 1e9 / 15e18 = 4e8
        uint256 bidAmount = 6e18;
        uint256 expectedConvertedAmount = 4e8;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 1);

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Start gas snapshot
        vm.startSnapshotGas("bid");

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            3e18,
            1,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        // Not affected by the previous day's bid
        assertEq(
            auctioneer.getDayState().convertible,
            previousConvertedAmount + expectedConvertedAmount,
            "day convertible"
        );

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - previousConvertedAmount - expectedConvertedAmount,
            MIN_PRICE,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    // when the bid amount converted is less than the remaining tick capacity
    //  when the calculated converted amount is 0
    //   [X] it reverts
    //  [X] it returns the amount of OHM that can be converted
    //  [X] it issues CD terms with the current tick price and time to expiry
    //  [X] it updates the day's deposit balance
    //  [X] it updates the day's converted balance
    //  [X] it deducts the converted amount from the tick capacity
    //  [X] it does not update the tick price
    //  [X] it sets the current tick size to the standard tick size
    //  [X] it sets the lastUpdate to the current block timestamp

    function test_convertedAmountLessThanTickCapacity(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 150e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 150e18)
    {
        // We want the converted amount to be less than the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 = 10e9 - 1
        // Bid amount = (10e9 - 1) * 15e18 / 1e9
        // Bid amount = 150e18 - 1 (it will round down)

        uint256 bidAmount = bound(bidAmount_, 1e18, 150e18 - 1);
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            150e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - expectedConvertedAmount,
            MIN_PRICE,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    //  when the OHM out is greater or equal to the minimum OHM out
    //   [X] it succeeds

    function test_convertedAmountLessThanTickCapacity_greaterThanMinOhmOut(
        uint256 bidAmount_,
        uint256 minOhmOut_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        _mintAndApprove(recipient, 150e18);

        // We want the converted amount to be less than the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 = 10e9 - 1
        // Bid amount = (10e9 - 1) * 15e18 / 1e9
        // Bid amount = 150e18 - 1 (it will round down)
        bidAmount_ = bound(bidAmount_, 1e18, 150e18 - 1);
        uint256 expectedConvertedAmount = (bidAmount_ * 1e9) / 15e18;
        minOhmOut_ = bound(minOhmOut_, 0, expectedConvertedAmount);

        {
            // Check preview
            uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount_);

            // Assert that the preview is as expected
            assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");
        }

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount_, expectedConvertedAmount, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount_, minOhmOut_, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount_,
            expectedConvertedAmount,
            150e18 - bidAmount_,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - expectedConvertedAmount,
            MIN_PRICE,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    // when the bid amount converted is equal to the remaining tick capacity
    //  when the tick step is > 100e2
    //   [X] it returns the amount of OHM that can be converted using the current tick price
    //   [X] it issues CD terms with the current tick price and time to expiry
    //   [X] it updates the day's deposit balance
    //   [X] it updates the day's converted balance
    //   [X] it updates the tick capacity to the tick size
    //   [X] it updates the tick price to be higher than the current tick price
    //   [X] it sets the current tick size to the standard tick size
    //   [X] it sets the lastUpdate to the current block timestamp

    function test_convertedAmountEqualToTickCapacity(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 151e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 151e18)
    {
        // We want the converted amount to be equal to the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 = 10e9
        // Bid amount = 10e9 * 15e18 / 1e9
        // Bid amount = 150e18 (it will round down)

        // We expect the range of bid amounts when converted to round down to 10e9
        uint256 bidAmount = bound(bidAmount_, 150e18, 150e18 + 15e9 - 1);
        uint256 expectedDepositIn = 150e18;
        uint256 expectedConvertedAmount = 10e9;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            151e18 - expectedDepositIn,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        // As the capacity was depleted exactly, it shifts to the next tick
        uint256 nextTickPrice = FullMath.mulDivUp(MIN_PRICE, TICK_STEP, 100e2);
        _assertPreviousTick(TICK_SIZE, nextTickPrice, TICK_SIZE, uint48(block.timestamp));
    }

    //  when the tick step is = 100e2
    //   [X] it returns the amount of OHM that can be converted using the current tick price
    //   [X] it issues CD terms with the current tick price and time to expiry
    //   [X] it updates the day's deposit balance
    //   [X] it updates the day's converted balance
    //   [X] it updates the tick capacity to the tick size
    //   [X] the tick price is unchanged
    //   [X] it sets the current tick size to the standard tick size
    //   [X] it sets the lastUpdate to the current block timestamp

    function test_convertedAmountEqualToTickCapacity_givenTickStepIsEqual(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenTickStep(100e2)
        givenAddressHasReserveToken(recipient, 151e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 151e18)
    {
        // We want the converted amount to be equal to the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 = 10e9
        // Bid amount = 10e9 * 15e18 / 1e9
        // Bid amount = 150e18 (it will round down)

        // We expect the range of bid amounts when converted to round down to 10e9
        uint256 bidAmount = bound(bidAmount_, 150e18, 150e18 + 15e9 - 1);
        uint256 expectedDepositIn = 150e18;
        uint256 expectedConvertedAmount = 10e9;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            151e18 - expectedDepositIn,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        // As the capacity was depleted exactly, it shifts to the next tick
        // As the tick step is 100e2, the price is unchanged
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // when the bid amount converted is greater than the remaining tick capacity
    //  when the remaining deposit results in a converted amount of 0
    //   [X] it returns the amount of the reserve token that can be converted

    function test_convertedAmountGreaterThanTickCapacity_convertedAmountIsZero(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 300e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 300e18)
    {
        // We want the converted amount to be greater than the tick capacity (10e9)
        // But also for the remaining deposit to result in a converted amount of 0
        // Bid amount > 150e18
        // Bid amount < 150e18 + 165e8
        uint256 bidAmount = bound(bidAmount_, 150e18 + 1, 150e18 + 165e8 - 1);
        uint256 expectedDepositIn = 150e18;

        // Only uses the first tick
        uint256 expectedConvertedAmount = (150e18 * 1e9) / 15e18;
        uint256 tickTwoPrice = FullMath.mulDivUp(MIN_PRICE, TICK_STEP, 100e2);

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            300e18 - expectedDepositIn, // Does not transfer excess deposit
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(TICK_SIZE, tickTwoPrice, TICK_SIZE, uint48(block.timestamp));
    }

    //  when the convertible amount of OHM will exceed the day target
    //   [X] the next tick size is set to half of the standard tick size

    function test_convertedAmountGreaterThanTickCapacity_reachesDayTarget(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 40575e16)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 40575e16)
    {
        // We want the converted amount to be greater than the day target, 20e9, but within tick three
        // Tick one: 10e9, price is 15e18, max bid amount is 150e18
        // Tick two: 10e9, price is 165e17, max bid amount is 165e18
        // Tick three: 5e9, price is 1815e16, max bid amount is 9075e16
        // Total bid amount = 150e18 + 165e18 + 9075e16 = 40575e16
        uint256 bidOneAmount = 150e18;
        uint256 bidTwoAmount = 165e18;
        uint256 bidThreeMaxAmount = 9075e16;
        uint256 reserveTokenBalance = bidOneAmount + bidTwoAmount + bidThreeMaxAmount;
        uint256 bidAmount = bound(bidAmount_, bidOneAmount + bidTwoAmount, reserveTokenBalance - 1);
        uint256 tickThreePrice = 1815e16;
        uint256 tickThreeBidAmount = bidAmount - bidOneAmount - bidTwoAmount;

        uint256 expectedConvertedAmount;
        uint256 expectedDepositIn;
        {
            uint256 tickOneConvertedAmount = (bidOneAmount * 1e9) / 15e18;
            uint256 tickTwoConvertedAmount = (bidTwoAmount * 1e9) / 165e17;
            uint256 tickThreeConvertedAmount = (tickThreeBidAmount * 1e9) / tickThreePrice;

            expectedConvertedAmount =
                tickOneConvertedAmount +
                tickTwoConvertedAmount +
                tickThreeConvertedAmount;

            // Recalculate the bid amount, in case tickThreeConvertedAmount is 0
            expectedDepositIn =
                bidOneAmount +
                bidTwoAmount +
                (tickThreeConvertedAmount == 0 ? 0 : tickThreeBidAmount);
        }

        {
            // Check preview
            uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

            // Assert that the preview is as expected
            assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");
        }

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, expectedConvertedAmount, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            reserveTokenBalance - expectedDepositIn,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            10e9 + 10e9 + 5e9 - expectedConvertedAmount,
            tickThreePrice,
            5e9, // The tick size is halved as the target is met or exceeded
            uint48(block.timestamp)
        );
    }

    //  given there is another deposit period enabled
    //   [X] it captures the current tick for the other deposit period

    function test_convertedAmountGreaterThanTickCapacity_reachesDayTarget_multipleDepositPeriods(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
    {
        // We want the converted amount to be greater than the day target, 20e9, but within tick three
        // Tick one: 10e9, price is 15e18, max bid amount is 150e18
        // Tick two: 10e9, price is 165e17, max bid amount is 165e18
        // Tick three: 5e9, price is 1815e16, max bid amount is 9075e16
        // Total bid amount = 150e18 + 165e18 + 9075e16 = 40575e16
        uint256 bidOneAmount = 150e18;
        uint256 bidTwoAmount = 165e18;
        uint256 bidThreeMaxAmount = 9075e16;
        uint256 reserveTokenBalance = bidOneAmount + bidTwoAmount + bidThreeMaxAmount;
        uint256 bidAmount = bound(bidAmount_, bidOneAmount + bidTwoAmount, reserveTokenBalance - 1);
        uint256 tickThreePrice = 1815e16;

        uint256 expectedConvertedAmount;
        uint256 expectedDepositIn;
        {
            uint256 tickThreeBidAmount = bidAmount - bidOneAmount - bidTwoAmount;
            uint256 tickOneConvertedAmount = (bidOneAmount * 1e9) / 15e18;
            uint256 tickTwoConvertedAmount = (bidTwoAmount * 1e9) / 165e17;
            uint256 tickThreeConvertedAmount = (tickThreeBidAmount * 1e9) / tickThreePrice;

            expectedConvertedAmount =
                tickOneConvertedAmount +
                tickTwoConvertedAmount +
                tickThreeConvertedAmount;

            // Recalculate the bid amount, in case tickThreeConvertedAmount is 0
            expectedDepositIn =
                bidOneAmount +
                bidTwoAmount +
                (tickThreeConvertedAmount == 0 ? 0 : tickThreeBidAmount);
        }

        // Place a bid for the second deposit period
        _mintAndApprove(recipient, 1e18);
        vm.prank(recipient);
        (uint256 bidOneConvertedAmount, , , ) = auctioneer.bid(
            PERIOD_MONTHS_TWO,
            1e18,
            1,
            false,
            false
        );

        // Warp forward to that the ticks change
        vm.warp(block.timestamp + 1 hours);

        IConvertibleDepositAuctioneer.Tick memory periodTwoTickBefore = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );

        _mintAndApprove(recipient, 40575e16);

        {
            // Check preview
            uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

            // Assert that the preview is as expected
            assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");
        }

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, expectedConvertedAmount, 1);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            reserveTokenBalance - expectedDepositIn,
            balanceBefore,
            1,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(
            auctioneer.getDayState().convertible,
            expectedConvertedAmount + bidOneConvertedAmount,
            "day convertible"
        );

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            10e9 + 10e9 + 5e9 - expectedConvertedAmount,
            tickThreePrice,
            5e9, // The tick size is halved as the target is met or exceeded
            uint48(block.timestamp)
        );

        // Assert the tick for the second deposit period
        {
            IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(
                PERIOD_MONTHS_TWO
            );

            assertEq(
                tick.capacity,
                periodTwoTickBefore.capacity,
                "period two previous tick capacity"
            );
            assertEq(tick.price, periodTwoTickBefore.price, "period two previous tick price");
            assertEq(
                tick.lastUpdate,
                uint48(block.timestamp),
                "period two previous tick lastUpdate"
            );
        }
    }

    //  when the convertible amount of OHM will exceed multiples of the day target
    //   [X] the next tick size is set to half of the previous tick size

    function test_convertedAmountGreaterThanTickCapacity_multipleDayTargets(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 796064875e12)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 796064875e12)
    {
        // We want the converted amount to be >= 2 * day target, 40e9
        // Tick one: 10e9, price is 15e18, max bid amount is 150e18
        // Tick two: 10e9, price is 165e17, max bid amount is 165e18
        // Tick three: 5e9, price is 1815e16, max bid amount is 9075e16
        // Tick four: 5e9, price is 19965e15, max bid amount is 99825e15
        // Tick five: 5e9, price is 219615e14, max bid amount is 1098075e14
        // Tick six: 5e9, price is 2415765e13, max bid amount is 12078825e13
        // Tick seven: 2.5e9, price is 26573415e12, max bid amount is 59894125e12
        // Max bid amount = 150e18 + 165e18 + 9075e16 + 99825e15 + 1098075e14 + 12078825e13 + 59894125e12 = 796064875e12
        // Ticks one to six bid amount = 150e18 + 165e18 + 9075e16 + 99825e15 + 1098075e14 + 12078825e13 = 73617075e13
        uint256 reserveTokenBalance = 796064875e12;
        uint256 bidAmount = bound(bidAmount_, 73617075e13, reserveTokenBalance - 1);

        uint256 expectedConvertedAmount;
        uint256 expectedDepositIn;
        {
            // Tick one: 150e18 * 1e9 / 15e18 = 10e9
            // Tick two: 165e18 * 1e9 / 165e17 = 10e9
            // Tick three: 9075e16 * 1e9 / 1815e16 = 5e9
            // Tick four: 99825e15 * 1e9 / 19965e15 = 5e9
            // Tick five: 1098075e14 * 1e9 / 219615e14 = 5e9
            // Tick six: 12078825e13 * 1e9 / 2415765e13 = 5e9
            uint256 ticksOneToSixConvertedAmount = 40e9;
            uint256 tickSevenConvertedAmount = ((bidAmount - 73617075e13) * 1e9) / 26573415e12;
            expectedConvertedAmount = ticksOneToSixConvertedAmount + tickSevenConvertedAmount;

            // Recalculate the bid amount, in case tickSevenConvertedAmount is 0
            expectedDepositIn =
                73617075e13 +
                (tickSevenConvertedAmount == 0 ? 0 : (bidAmount - 73617075e13));
        }

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            expectedDepositIn,
            expectedConvertedAmount,
            reserveTokenBalance - expectedDepositIn,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            10e9 + 10e9 + 5e9 + 5e9 + 5e9 + 5e9 + 25e8 - expectedConvertedAmount,
            26573415e12,
            25e8, // The tick size is halved twice as the target is met or exceeded twice
            uint48(block.timestamp)
        );
    }

    //  when the tick step is > 100e2
    //   [X] it returns the amount of OHM that can be converted at multiple prices
    //   [X] it issues CD terms with the average price, time to expiry and redemption period
    //   [X] it updates the day's deposit balance
    //   [X] it updates the day's converted balance
    //   [X] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [X] it updates the new tick price to be higher than the current tick price
    //   [X] it sets the current tick size to the standard tick size
    //   [X] it sets the lastUpdate to the current block timestamp

    function test_convertedAmountGreaterThanTickCapacity(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 300e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 300e18)
    {
        // We want the converted amount to be greater than the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 >= 11e9
        // Bid amount = 11e9 * 15e18 / 1e9
        // Bid amount = 165e18 (it will round down)
        // At most it should be 300e18 - 1 to stay within the tick capacity

        uint256 bidAmount = bound(bidAmount_, 165e18, 300e18 - 1);
        uint256 tickTwoPrice = FullMath.mulDivUp(MIN_PRICE, TICK_STEP, 100e2);

        uint256 tickOneConvertedAmount = (150e18 * 1e9) / 15e18;
        uint256 tickTwoConvertedAmount = ((bidAmount - 150e18) * 1e9) / tickTwoPrice;
        uint256 expectedConvertedAmount = tickOneConvertedAmount + tickTwoConvertedAmount;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            300e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE * 2 - expectedConvertedAmount,
            tickTwoPrice,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    //  when the tick step is = 100e2
    //   [X] it returns the amount of OHM that can be converted at multiple prices
    //   [X] it issues CD terms with the average price, time to expiry and redemption period
    //   [X] it updates the day's deposit balance
    //   [X] it updates the day's converted balance
    //   [X] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [X] the tick price is unchanged
    //   [X] it sets the current tick size to the standard tick size
    //   [X] it sets the lastUpdate to the current block timestamp

    function test_convertedAmountGreaterThanTickCapacity_givenTickStepIsEqual(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenTickStep(100e2)
        givenAddressHasReserveToken(recipient, 300e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 300e18)
    {
        // We want the converted amount to be greater than the tick capacity (10e9)
        // Bid amount * 1e9 / 15e18 >= 11e9
        // Bid amount = 11e9 * 15e18 / 1e9
        // Bid amount = 165e18 (it will round down)
        // At most it should be 300e18 - 1 to stay within the tick capacity

        uint256 bidAmount = bound(bidAmount_, 165e18, 300e18 - 1);
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            300e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE * 2 - expectedConvertedAmount,
            MIN_PRICE,
            TICK_SIZE,
            uint48(block.timestamp)
        );
    }

    function test_givenBidAmountConvertedIsAboveZero(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // We want a bid amount that will result in a converted amount of 0
        // Given bid amount * 1e9 / 15e18 = converted amount
        // When bid amount = 15e9, the converted amount = 1
        uint256 bidAmount = bound(bidAmount_, 15e9, 1e18);

        // Calculate the expected converted amount
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            1e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);
    }

    // given the day target is 0
    //  when the bid amount converts to an amount less than the tick capacity
    //   [X] the price does not change
    //   [X] the capacity is reduced
    //  when the bid amount converts to an amount equal to the tick capacity
    //   [X] the price is increased
    //   [X] the capacity is the standard tick size
    //  [X] the price is increased

    function test_givenTargetZero_whenConvertedAmountLessThanTickCapacity(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(0, TICK_SIZE, MIN_PRICE)
        givenAddressHasReserveToken(recipient, LARGE_MINT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), LARGE_MINT_AMOUNT)
    {
        // We want a bid amount that will result in a converted amount less than the tick size
        // Given bid amount * 1e9 / 15e18 = converted amount
        // When bid amount = 15e9, the converted amount = 1
        // When bid amount = 150e18, the converted amount = 10e9
        // When bid amount = 15e18-1, the converted amount = 9999999999
        uint256 bidAmount = bound(bidAmount_, 15e9, 150e18 - 1);

        // Calculate the expected converted amount
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            LARGE_MINT_AMOUNT - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert tick
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(PERIOD_MONTHS);
        assertEq(tick.capacity, TICK_SIZE - expectedConvertedAmount, "tick capacity");
        assertEq(tick.price, MIN_PRICE, "tick price");
    }

    function test_givenTargetZero_whenConvertedAmountEqualToTickCapacity()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(0, TICK_SIZE, MIN_PRICE)
        givenAddressHasReserveToken(recipient, LARGE_MINT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), LARGE_MINT_AMOUNT)
    {
        // We want a bid amount that will result in a converted amount equal than the tick size
        // Given bid amount * 1e9 / 15e18 = converted amount
        // When bid amount = 150e18, the converted amount = 10e9
        uint256 bidAmount = 150e18;

        // Calculate the expected converted amount
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Calculate the expected tick price
        uint256 expectedTickPrice = FullMath.mulDivUp(MIN_PRICE, TICK_STEP, 100e2);

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            LARGE_MINT_AMOUNT - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert tick
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(PERIOD_MONTHS);
        assertEq(tick.capacity, TICK_SIZE, "tick capacity");
        assertEq(tick.price, expectedTickPrice, "tick price");
    }

    function test_givenTargetZero_whenConvertedAmountGreaterThanTickCapacity(
        uint256 bidAmount
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(0, TICK_SIZE, MIN_PRICE)
    {
        _mintAndApprove(recipient, LARGE_MINT_AMOUNT);

        // We want a bid amount that will result in a converted amount greater than the tick size
        // Given bid amount * 1e9 / 15e18 = converted amount
        // The initial tick price is MIN_PRICE, 15e18
        // The second tick price is MIN_PRICE * 1.1, 165e17
        // When bid amount = 151e18:
        // - 150e18 is converted into 10e9 at a price of 15e18
        // - 1e18 is converted into 60606060 at a price of 165e17
        bidAmount = bound(bidAmount, 151e18, 200e18);

        // Calculate the expected converted amount
        uint256 expectedConvertedAmountTickTwo = ((bidAmount - 150e18) * 1e9) / 165e17;

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.balanceOf(recipient, receiptTokenId);

        {
            // Check preview
            uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

            // Assert that the preview is as expected
            assertEq(
                previewOhmOut,
                TICK_SIZE + expectedConvertedAmountTickTwo,
                "preview converted amount"
            );

            // Expect event
            _expectBidEvent(bidAmount, previewOhmOut, 0);
        }

        // Call function
        vm.prank(recipient);
        (
            uint256 ohmOut,
            uint256 positionId,
            uint256 receiptTokenId,
            uint256 actualAmount
        ) = auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            TICK_SIZE + expectedConvertedAmountTickTwo,
            LARGE_MINT_AMOUNT - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert actual amount matches receipt tokens received
        _assertActualAmount(actualAmount, balanceBefore);

        // Assert tick
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getPreviousTick(PERIOD_MONTHS);
        assertEq(tick.capacity, TICK_SIZE - expectedConvertedAmountTickTwo, "tick capacity");
        assertEq(tick.price, FullMath.mulDivUp(MIN_PRICE, TICK_STEP, 100e2), "tick price");
    }
}
