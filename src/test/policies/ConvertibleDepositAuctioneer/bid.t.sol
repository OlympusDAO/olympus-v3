// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

import {FullMath} from "src/libraries/FullMath.sol";

import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositAuctioneerBidTest is ConvertibleDepositAuctioneerTest {
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
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
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

    // when the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectNotEnabledRevert();

        // Call function
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, 1e18, false, false);
    }

    // given the deposit asset and period are not enabled
    //  [X] it reverts

    function test_givenDepositAssetAndPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, 1e18, false, false);
    }

    // when the caller has not approved DepositManager to spend the bid token
    //  [X] it reverts

    function test_givenSpendingNotApproved_reverts()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenAddressHasReserveToken(recipient, 1e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, 1e18, false, false);
    }

    // when the "cd_auctioneer" role is not granted to the auctioneer contract
    //  [X] it reverts

    function test_givenAuctioneerRoleNotGranted_reverts()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // Revoke the auctioneer role
        rolesAdmin.revokeRole("cd_auctioneer", address(auctioneer));

        // Expect revert
        _expectRoleRevert("cd_auctioneer");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, 1e18, false, false);
    }

    // when the bid amount converted is 0
    //  [X] it reverts

    function test_givenBidAmountConvertedIsZero_reverts(
        uint256 bidAmount_
    )
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "converted amount"
            )
        );

        // Call function
        vm.prank(recipient);
        auctioneer.bid(iReserveToken, PERIOD_MONTHS, bidAmount, false, false);
    }

    // given the deposit asset has 6 decimals
    //  [X] the conversion price is correct

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenEnabledWithParameters(TARGET, TICK_SIZE, 15e6)
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenAddressHasReserveToken(recipient, 3e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 3e6)
    {
        // Expected converted amount
        // 3e6 * 1e9 / 15e6 = 2e8
        uint256 bidAmount = 3e6;
        uint256 expectedConvertedAmount = 2e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenAddressHasReserveToken(recipient, 3e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 3e18)
    {
        // Expected converted amount
        // 3e18 * 1e9 / 15e18 = 2e8
        uint256 bidAmount = 3e18;
        uint256 expectedConvertedAmount = 2e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
            iReserveToken,
            PERIOD_MONTHS
        );

        // Expected converted amount
        // 6e18 * 1e9 / 15e18 = 4e8
        uint256 bidAmount = 6e18;
        uint256 expectedConvertedAmount = 4e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 1);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 1);

        // Start gas snapshot
        vm.startSnapshotGas("bid");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenTickStep(100e2)
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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

        uint256 tickOneConvertedAmount = (bidOneAmount * 1e9) / 15e18;
        uint256 tickTwoConvertedAmount = (bidTwoAmount * 1e9) / 165e17;
        uint256 tickThreeConvertedAmount = (tickThreeBidAmount * 1e9) / tickThreePrice;
        uint256 expectedConvertedAmount = tickOneConvertedAmount +
            tickTwoConvertedAmount +
            tickThreeConvertedAmount;

        // Recalculate the bid amount, in case tickThreeConvertedAmount is 0
        uint256 expectedDepositIn = bidOneAmount +
            bidTwoAmount +
            (tickThreeConvertedAmount == 0 ? 0 : tickThreeBidAmount);

        {
            // Check preview
            (uint256 previewOhmOut, ) = auctioneer.previewBid(
                iReserveToken,
                PERIOD_MONTHS,
                bidAmount
            );

            // Assert that the preview is as expected
            assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");
        }

        // Expect event
        _expectBidEvent(expectedDepositIn, expectedConvertedAmount, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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

    //  when the convertible amount of OHM will exceed multiples of the day target
    //   [X] the next tick size is set to half of the previous tick size

    function test_convertedAmountGreaterThanTickCapacity_multipleDayTargets(
        uint256 bidAmount_
    )
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
            // Tick six: 12078825e23 * 1e9 / 2395765e13 = 5e9
            uint256 ticksOneToSixConvertedAmount = 40e9;
            uint256 tickSevenConvertedAmount = ((bidAmount - 73617075e13) * 1e9) / 26573415e12;
            expectedConvertedAmount = ticksOneToSixConvertedAmount + tickSevenConvertedAmount;

            // Recalculate the bid amount, in case tickSevenConvertedAmount is 0
            expectedDepositIn =
                73617075e13 +
                (tickSevenConvertedAmount == 0 ? 0 : (bidAmount - 73617075e13));
        }

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(expectedDepositIn, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenTickStep(100e2)
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
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
        (uint256 previewOhmOut, ) = auctioneer.previewBid(iReserveToken, PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Expect event
        _expectBidEvent(bidAmount, previewOhmOut, 0);

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId) = auctioneer.bid(
            iReserveToken,
            PERIOD_MONTHS,
            bidAmount,
            false,
            false
        );

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
    }
}
