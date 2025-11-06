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
            depositManager.getReceiptTokenManager().balanceOf(recipient, receiptTokenId),
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

    // when tickSizeBase = 1.0 (no reduction)
    //  [X] crossing the day target does not reduce tick size
    function test_tickSizeBaseOne_noReductionOnTarget()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 400e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 400e18)
    {
        // Set base to 1.0
        vm.prank(admin);
        auctioneer.setTickSizeBase(1e18);

        // Cross the day target exactly with a single bid:
        // Proof:
        // - Tick 1 (capacity 10e9) @ 15e18 requires 150e18 deposit
        // - Tick 2 (capacity 10e9) @ 16.5e18 requires 165e18 deposit
        // - Total to reach 20e9 = 150e18 + 165e18 = 315e18
        // Use 315e18 (>=) to ensure crossing to multiplier=1
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 315e18, 1, false, false);

        // Proof (no reduction):
        // - Base = 1.0 (1e18)
        // - Multiplier = floor(ohmOut / target) >= 1 after crossing target
        // - New tick size = floor(originalTickSize / base^multiplier) = floor(10e9 / 1^1) = 10e9
        // Therefore, expected tick size = 10e9
        assertEq(auctioneer.getCurrentTickSize(), 10e9, "tick size should not reduce");
    }

    // when tickSizeBase = 1.5
    //  [X] crossing one day target reduces tick size by ~1/1.5 (floor)
    function test_tickSizeBaseOnePointFive_reductionOnTarget()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 400e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 400e18)
    {
        // Set base to 1.5
        vm.prank(admin);
        auctioneer.setTickSizeBase(15e17); // 1.5e18

        // Cross the day target exactly with a single bid of 315e18 (see proof above)
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 315e18, 1, false, false);

        // Proof (manual):
        // - Original tick size = 10e9 (OHM units, 9 decimals)
        // - Base = 1.5 (15e17), multiplier = 1 after crossing target once
        // - New tick size = floor(10e9 / 1.5) = floor(6,666,666,666.666...) = 6,666,666,666
        // Therefore, expected tick size = 6_666_666_666
        assertEq(auctioneer.getCurrentTickSize(), 6_666_666_666, "tick size reduced by base");
    }

    // when tickSizeBase = 3.0
    //  [X] crossing one day target reduces tick size by 1/3 (floor)
    function test_tickSizeBaseThree_reductionOnTarget()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 400e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 400e18)
    {
        // Set base to 3.0
        vm.prank(admin);
        auctioneer.setTickSizeBase(3e18);

        // Cross the day target exactly with a single bid of 315e18 (see proof above)
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 315e18, 1, false, false);

        // Proof (manual):
        // - Original tick size = 10e9 (OHM units, 9 decimals)
        // - Base = 3.0 (3e18), multiplier = 1 after crossing target once
        // - New tick size = floor(10e9 / 3) = floor(3,333,333,333.333...) = 3,333,333,333
        // Therefore, expected tick size = 3_333_333_333
        assertEq(auctioneer.getCurrentTickSize(), 3_333_333_333, "tick size reduced by base");
    }

    // when base is large and multiple targets are crossed in one bid
    //  [X] tick size reduction floors to minimum when division would be zero
    function test_tickSizeMinimum_whenDivisionRoundsToZero()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(1_000, 1_000, 1) // target=1000 wei of OHM, tickSize=1000 wei of OHM, minPrice=1
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        // Set base to 10.0 to accelerate reduction
        vm.prank(admin);
        auctioneer.setTickSizeBase(10e18);

        // Single bid will vastly exceed target due to minPrice=1, crossing many thresholds
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 1e18, 1, false, false);

        // Proof (manual):
        // - Original tick size = 1000 wei of OHM
        // - Base = 10; after first threshold: floor(1000/10^1)=10
        // - After second: floor(100/10^2)=1
        // - After third: floor(10/10^3)=0 -> implementation floors to minimum (1)
        // Therefore, expected tick size = 1
        assertEq(auctioneer.getCurrentTickSize(), 1, "tick size should floor to minimum");
    }

    // when multiplier would overflow rpow
    //  [X] tick size floors to minimum instead of reverting
    function test_tickSizeMinimum_whenMultiplierOverflowsRpow()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(1, 1, MIN_PRICE)
        givenAddressHasReserveToken(recipient, 1_000_000_000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1_000_000_000e18)
    {
        // Set base to maximum (10.0) for worst-case scenario
        vm.prank(admin);
        auctioneer.setTickSizeBase(10e18);

        // Make a large bid that will result in a very large multiplier
        // multiplier = convertible / target
        // With target=1 wei, even converting 1e9 OHM gives multiplier = 1e9
        // For rpow with base=10e18, exponents > ~59 would overflow uint256
        // This test verifies that when multiplier exceeds safe maximum (around 59 for base=10),
        // the function returns minimum tick size instead of reverting from rpow overflow

        // A single large bid will cross many thresholds
        // With minPrice=1 and target=1, multiplier grows very quickly
        vm.prank(recipient);
        // This should not revert even if multiplier would overflow rpow
        // Instead, it should return minimum tick size
        auctioneer.bid(PERIOD_MONTHS, 1_000_000_000e18, 1, false, false);

        // Verify the bid succeeded and tick size is at minimum
        // When multiplier exceeds safe maximum, tick size floors to minimum (1)
        uint256 tickSize = auctioneer.getCurrentTickSize();
        assertEq(tickSize, 1, "tick size should floor to minimum when multiplier exceeds safe max");
    }

    // when tickSizeBase = 3.0 and multiple day targets are achieved in cumulative bids
    //  [X] tick size equals floor(original / 3^2) after crossing 2 targets
    function test_tickSizeBaseThree_multipleTargets_cumulative()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(20e9, TICK_SIZE, MIN_PRICE) // TARGET=20e9, tickSize=10e9
        givenAddressHasReserveToken(recipient, 10_000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 10_000e18)
    {
        // Set base to 3.0
        vm.prank(admin);
        auctioneer.setTickSizeBase(3e18);

        // Cumulatively bid small chunks until we cross 2 * TARGET (40e9)
        // This avoids over-shooting too far while keeping the test simple.
        uint256 chunk = 50e18; // small deposit increments
        while (auctioneer.getDayState().convertible < 40e9) {
            vm.prank(recipient);
            auctioneer.bid(PERIOD_MONTHS, chunk, 1, false, false);
        }

        // Proof (manual):
        // After crossing 2 day targets, multiplier = 2.
        // New tick size = floor(originalTickSize / base^multiplier)
        //                = floor(10e9 / 3^2)
        //                = floor(10e9 / 9)
        //                = floor(1,111,111,111.111...)
        //                = 1,111,111,111
        assertEq(
            auctioneer.getCurrentTickSize(),
            1_111_111_111,
            "tick size for multiplier=2, base=3"
        );
    }

    function _assertActualAmount(
        uint256 actualAmount_,
        uint256 previousReceiptBalance_
    ) internal view {
        // Assert that the actual amount matches the increase in receipt token balance
        uint256 currentReceiptBalance = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );
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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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

        _mintAndApprove(recipient, 40575e16);

        {
            // Check preview
            uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

            // Assert that the preview is as expected
            assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");
        }

        // Get receipt token balance before bid
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
            balanceBefore,
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
            TICK_SIZE / 2, // The tick size is halved as the target is met or exceeded
            uint48(block.timestamp)
        );

        // Assert the tick for the second deposit period
        {
            IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
                PERIOD_MONTHS_TWO
            );

            // Capacity: halved as the day target is met
            // Price: unaffected by the day target being met
            // Last update: updated to the current block timestamp
            assertEq(tick.capacity, TICK_SIZE / 2, "period two tick capacity");
            assertEq(tick.price, MIN_PRICE, "period two tick price");
            assertEq(tick.lastUpdate, uint48(block.timestamp), "period two tick lastUpdate");
        }
    }

    function test_convertedAmountGreaterThanTickCapacity_reachesDayTarget_multipleDepositPeriods_sameBlock()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        // Bid one: 15e18
        // - Period one
        // - Tick one: remaining capacity of 9e9, price of 15e18
        // - Bid amount of 15e18 @ 15e18 = 1e9 OHM out
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS_TWO, 15e18, 1, false, false);

        // Bid two:
        // - Period two
        // - Tick one: remaining capacity of 10e9, price of 15e18. Deposit amount of 150e18, OHM out = 10e9
        // - Tick two: remaining capacity of 10e9, price of 165e17. Deposit amount of 148.5e18, OHM out = 9e9 (due to hitting day target)
        // - Tick three: remaining capacity of 5e9, price of 1815e16. Deposit amount of 1.5e18, OHM out = 82644628
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 300e18, 1, false, false);

        // Assert the tick for period one
        _assertPreviousTick(
            5e9 - 82644628,
            1815e16,
            TICK_SIZE / 2, // The tick size is halved as the target is met or exceeded
            uint48(block.timestamp)
        );

        // Assert the tick for period two
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );

        // Capacity: halved as the day target is met
        // Price: unaffected by the day target being met
        // Last update: updated to the current block timestamp
        assertEq(tick.capacity, TICK_SIZE / 2, "period two tick capacity");
        assertEq(tick.price, MIN_PRICE, "period two tick price");
        assertEq(tick.lastUpdate, uint48(block.timestamp), "period two tick lastUpdate");
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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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

    function test_convertedAmountGreaterThanTickCapacity_smallTickStep()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 796064875e20)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 796064875e20)
    {
        uint256 reserveTokenBalance = 796064875e20;
        uint256 bidAmount = reserveTokenBalance - 1;

        vm.prank(admin);
        auctioneer.setTickStep(10001);

        vm.startSnapshotGas("bid_smallTickStep");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        vm.stopSnapshotGas();
    }

    function test_convertedAmountGreaterThanTickCapacity_smallTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(TARGET, 1e3, MIN_PRICE)
        givenAddressHasReserveToken(recipient, 100e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 100e18)
    {
        // We want the converted amount to be >= 2 * day target, 40e9
        // Max bid amount = tick size * price / 1e9
        // Tick one: tick size 1e3, price is 15e18, max bid amount is 15000000000000
        // Tick two: tick size 1e3, price is 165e17, max bid amount is 16500000000000
        // Tick three: tick size 1e3, price is 1815e16, max bid amount is 18150000000000
        // Tick four: tick size 1e3, price is 19965e15, max bid amount is 19965000000000
        // Tick five: tick size 1e3, price is 219615e14, max bid amount is 21961500000000
        // Tick six: tick size 1e3, price is 2415765e13, max bid amount is 24157650000000
        // Tick seven: tick size 1e3, price is 26573415e12, max bid amount is 26573415000000
        // Tick eight: tick size 1e3, price is 29230756500000000000, max bid amount is 29230756500000
        // Tick nine: tick size 1e3, price is 32153832150000000000, max bid amount is 32153832150000
        // Tick ten: tick size 1e3, price is 35369215365000000000, max bid amount is 35369215365000
        // Tick eleven: tick size 1e3, price is 38906136901500000000, max bid amount is 38906136901500
        // Tick twelve: tick size 1e3, price is 42796750591650000000, max bid amount is 42796750591650
        // Tick thirteen: tick size 1e3, price is 47076425650815000000, max bid amount is 47076425650815
        // Tick fourteen: tick size 1e3, price is 51784068215896500000, max bid amount is 51784068215896
        // Tick fifteen: tick size 1e3, price is 56962475037486150000, max bid amount is 56962475037486
        // Tick sixteen: tick size 1e3, price is 62658722541234765000, max bid amount is 62658722541234
        // Tick seventeen: tick size 1e3, price is 68924594795358241500, max bid amount is 68924594795358
        // Tick eighteen: tick size 1e3, price is 75817054274894065650, max bid amount is 75817054274894
        // Tick nineteen: tick size 1e3, price is 83398759702383472215, max bid amount is 83398759702383
        // Total max bid amount = 15000000000000 + 16500000000000 + 18150000000000 + 19965000000000 + 21961500000000 + 24157650000000 + 26573415000000 + 29230756500000 + 32153832150000 + 35369215365000 + 38906136901500 + 42796750591650 + 47076425650815 + 51784068215896 + 56962475037486 + 62658722541234 + 68924594795358 + 75817054274894 + 83398759702383 = 79606487500000000000
        uint256 bidAmount = 79606487500000000000;

        vm.startSnapshotGas("bid_smallTickSize");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 1, false, false);

        vm.stopSnapshotGas();
    }

    // [X] it reduces the tick size exponentially as multiple day targets are reached
    function test_exponentialTickSizeReduction()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(10e9, TICK_SIZE, MIN_PRICE)
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        // This test demonstrates exponential reduction of tick size as multiples of the day target are reached
        // Day target = 10e9
        // Initial tick size = 10e9
        //
        // Expected exponential reduction:
        // - 0x to 1x target (0 to 10e9): tick size = 10e9 (original)
        // - 1x to 2x target (10e9 to 20e9): tick size = 10e9 / 2^1 = 5e9
        // - 2x to 3x target (20e9 to 30e9): tick size = 10e9 / 2^2 = 2.5e9
        // - 3x to 4x target (30e9 to 40e9): tick size = 10e9 / 2^3 = 1.25e9
        //
        // We'll bid enough to reach just past 30e9 (3x target) to show 3 levels of exponential reduction

        // Tick 1: 10e9 OHM, price = 15e18, max bid = 150e18
        // Total converted after tick 1: 10e9 (1x target reached)
        // Tick 2: 5e9 OHM, price = 16.5e18, max bid = 82.5e18
        // Total converted after tick 2: 15e9 (1x target reached)
        // Tick 3: 5e9 OHM, price = 18.15e18, max bid = 90.75e18
        // Total converted after tick 3: 20e9 (2x target reached)
        // Tick 4: 2.5e9 OHM, price = 19.965e18, max bid = 49.9125e18
        // Total converted after tick 4: 22.5e9 (2x target reached)
        // Tick 5: 2.5e9 OHM, price = 21.9615e18, max bid = 54.90375e18
        // Total converted after tick 5: 25e9 (2x target reached)
        // Tick 6: 2.5e9 OHM, price = 24.15765e18, max bid = 60.394125e18
        // Total converted after tick 6: 27.5e9 (2x target reached)
        // Tick 7: 2.5e9 OHM, price = 26.573415e18, max bid = 66.4335375e18
        // Total converted after tick 7: 30e9 (3x target reached)
        // Tick 8: 1.25e9 OHM, price = 29.2307565e18, max bid = 36.538445625e18
        //
        // Bid 8: 1e18 @ 29.2307565e18 = 34210541 OHM out
        //
        // Total bid amount = 150e18 + 82.5e18 + 90.75e18 + 49.9125e18 + 54.90375e18 + 60.394125e18
        //                    + 66.4335375e18 + 1e18
        //                  = 555893912500000000000
        // Total OHM out = 10e9 + 5e9 + 5e9 + 2.5e9 + 2.5e9 + 2.5e9 + 2.5e9 + 34210541 = 30034210541

        uint256 bidAmount = 555893912500000000000;
        uint256 expectedConvertedAmount = 30034210541;

        // Check preview
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId, ) = auctioneer.bid(
            PERIOD_MONTHS,
            bidAmount,
            1,
            false,
            false
        );

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            30034210541,
            1000e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId,
            receiptTokenId
        );

        // Assert the day state
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state (auction parameters remain unchanged)
        _assertAuctionParameters(10e9, TICK_SIZE, MIN_PRICE);

        // The key assertion: verify that the current tick size is 1.25e9 (10e9 / 2^3)
        // This demonstrates exponential reduction: 10e9 -> 5e9 -> 2.5e9 -> 1.25e9
        // If it were linear, the tick size would be 10e9 / (3 * 2) = 1.666...e9
        uint256 expectedTickSize = 125e7; // 1.25e9

        // Assert the tick capacity and tick size
        _assertPreviousTick(
            expectedTickSize - 34210541, // remaining capacity in current tick
            29.2307565e18,
            expectedTickSize, // This should be 1.25e9, demonstrating exponential reduction
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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
        uint256 balanceBefore = depositManager.getReceiptTokenManager().balanceOf(
            recipient,
            receiptTokenId
        );

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
    //  [X] previewBid returns 0
    //  [X] bid reverts with ConvertedAmountZero error

    function test_givenTargetZero(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(0, TICK_SIZE, MIN_PRICE)
        givenAddressHasReserveToken(recipient, LARGE_MINT_AMOUNT)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), LARGE_MINT_AMOUNT)
    {
        // When target is 0, the auction is disabled regardless of bid amount
        uint256 bidAmount = bound(bidAmount_, 1, LARGE_MINT_AMOUNT);

        // Check that previewBid returns 0 for disabled auction
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);
        assertEq(previewOhmOut, 0, "previewBid should return 0 when auction is disabled");

        // Expect bid to revert with ConvertedAmountZero error
        vm.expectRevert(
            IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_ConvertedAmountZero.selector
        );

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 0, false, false);
    }

    // given the day target is 1000
    //  given the tick size is 1000
    //   when the day target is met in the middle of the bid
    //    given the other deposit period has a tick capacity larger than the new tick size
    //     [X] the tick size is halved upon the day target being met
    //     [X] the tick price increases upon the day target being met
    //     [X] the tick capacity is reduced to the standard tick size
    //     [X] the tick capacity of other deposit periods is affected
    //     [X] the tick price of other deposit periods is not affected

    function test_dayTargetAppliesImmediately_otherDepositPeriodHasNoBid()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabledWithParameters(1000e9, 1000e9, MIN_PRICE)
        givenAddressHasReserveToken(recipient, 30000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 30000e18)
    {
        // First bid: period two, day target is reached
        vm.prank(recipient);
        (, uint256 positionIdOne, , ) = auctioneer.bid(
            PERIOD_MONTHS_TWO,
            16000e18,
            1,
            false,
            false
        );

        // Assert output
        // First bid:
        // - 15000e18 * 1e9 / 15e18 = 1000e9, new price of 16.5e18 and capacity of 500e9 (halved)
        // - 1000e18 * 1e9 / 16.5e18 = 60606060606 (rounded down), price is same, capacity is 500e9 - 60606060606 = 439393939394
        // - Conversion price: 16000e18 * 1e9 / (1000e9 + 60606060606) = 15085714285715147756 (rounded up)
        IDepositPositionManager.Position memory positionOne = convertibleDepositPositions
            .getPosition(positionIdOne);
        assertEq(positionOne.remainingDeposit, 16000e18, "positionOne remaining deposit");
        assertEq(positionOne.conversionPrice, 15085714285715147756, "positionOne conversion price");

        // Check tick state for deposit period two
        // - Capacity: 439393939394 (remaining capacity)
        // - Price: 16.5e18 (moved to the next tick)
        IConvertibleDepositAuctioneer.Tick memory tickOne = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );
        assertEq(tickOne.capacity, 439393939394, "tickOne capacity");
        assertEq(tickOne.price, 16.5e18, "tickOne price");

        // Check tick state for deposit period one
        // - Capacity: 500e9 (reduced due to the day target being met)
        // - Price: 15e18 (remains the same as before)
        tickOne = auctioneer.getCurrentTick(PERIOD_MONTHS);
        assertEq(tickOne.capacity, 500e9, "tickOne capacity after bid two");
        assertEq(tickOne.price, 15e18, "tickOne price after bid two");

        // Check global tick size
        assertEq(auctioneer.getCurrentTickSize(), 500e9, "global tick size");
    }

    //    [X] the tick size is halved upon the day target being met
    //    [X] the tick price increases upon the day target being met
    //    [X] the tick capacity is reduced to the standard tick size
    //    [X] the tick capacity of other deposit periods is not affected
    //    [X] the tick price of other deposit periods is not affected

    function test_dayTargetAppliesImmediately()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabledWithParameters(1000e9, 1000e9, MIN_PRICE)
        givenAddressHasReserveToken(recipient, 30000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 30000e18)
    {
        // First bid: period one, just under the tick size
        vm.prank(recipient);
        (, uint256 positionIdOne, , ) = auctioneer.bid(PERIOD_MONTHS, 14999e18, 1, false, false);

        // Assert output
        // First bid:
        // - 14999e18 * 1e9 / 15e18 = 999933333333 (66666667 left over)
        // - Conversion price: 14999e18 * 1e9 / 999933333333 = 15000000000005000334 (rounded up)
        IDepositPositionManager.Position memory positionOne = convertibleDepositPositions
            .getPosition(positionIdOne);
        assertEq(positionOne.remainingDeposit, 14999e18, "positionOne remaining deposit");
        assertEq(positionOne.conversionPrice, 15000000000005000334, "positionOne conversion price");

        // Check tick state
        // - Capacity: 1000e9 - 999933333333 = 66666667
        // - Price: 15e18
        IConvertibleDepositAuctioneer.Tick memory tickOne = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );
        assertEq(tickOne.capacity, 66666667, "tickOne capacity");
        assertEq(tickOne.price, 15e18, "tickOne price");

        // Check global tick size
        assertEq(auctioneer.getCurrentTickSize(), 1000e9, "global tick size");

        // Second bid: period two, just under the tick size
        vm.prank(recipient);
        (, uint256 positionIdTwo, , ) = auctioneer.bid(
            PERIOD_MONTHS_TWO,
            14999e18,
            1,
            false,
            false
        );

        // Second bid:
        // - 1000000005000000000 * 1e9 / 15e18 = 66666667 (results in the day target being met, tick size halving and tick price increasing)
        // - 8250000000000000000000 * 1e9 / 16.5e18 = 500000000000 (tick depleted, tick price increases)
        // - (14999e18 - 8250000000000000000000 - 1000000005000000000) * 1e9 / 18.15e18 = 371790633608
        // - Total OHM out: 66666667 + 500000000000 + 371790633608 = 871857300275
        // - Conversion price: 14999e18 * 1e9 / 871857300275 = 17203503366054326293 (rounded up)
        IDepositPositionManager.Position memory positionTwo = convertibleDepositPositions
            .getPosition(positionIdTwo);
        assertEq(positionTwo.remainingDeposit, 14999e18, "positionTwo remaining deposit");
        assertEq(positionTwo.conversionPrice, 17203503366054326293, "positionTwo conversion price");

        // Check tick state for deposit period two
        // - Capacity: 500e9 - 371790633608 = 128209366392
        // - Price: 18.15e18
        IConvertibleDepositAuctioneer.Tick memory tickTwo = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );
        assertEq(tickTwo.capacity, 128209366392, "tickTwo capacity");
        assertEq(tickTwo.price, 1815e16, "tickTwo price");

        // Check tick state for deposit period one
        // - Capacity: 66666667 (remains the same as before, it was under the reduced tick size)
        // - Price: 15e18 (remains the same as before)
        tickOne = auctioneer.getCurrentTick(PERIOD_MONTHS);
        assertEq(tickOne.capacity, 66666667, "tickOne capacity after bid two");
        assertEq(tickOne.price, 15e18, "tickOne price after bid two");

        // Check global tick size
        assertEq(auctioneer.getCurrentTickSize(), 500e9, "global tick size");
    }

    // ========== MINIMUM BID TESTS ========== //

    function test_bidBelowMinimumBid_reverts(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        // Set a minimum bid
        uint256 minimumBid = 100e18;
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Ensure bid amount is below minimum
        uint256 bidAmount = bound(bidAmount_, 1, minimumBid - 1);

        // Test previewBid returns 0
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);
        assertEq(previewOhmOut, 0, "previewBid should return 0 for bid below minimum");

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_BidBelowMinimum.selector,
                bidAmount,
                minimumBid
            )
        );

        // Call function
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 0, false, false);
    }

    function test_bidAtMinimumBid(
        uint256 minimumBid_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        uint256 minimumBid = bound(minimumBid_, 1e18, 100e18);

        // Set minimum bid
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Test previewBid returns correct value
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, minimumBid);
        assertGt(previewOhmOut, 0, "previewBid should return non-zero value for bid at minimum");

        // Call function with exact minimum bid
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, minimumBid, 0, false, false);

        // Should succeed without reverting
    }

    function test_bidAboveMinimumBid_succeeds(
        uint256 minimumBid_,
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        uint256 minimumBid = bound(minimumBid_, 1e18, 50e18);
        uint256 bidAmount = bound(bidAmount_, minimumBid + 1, 100e18);

        // Set minimum bid
        vm.prank(admin);
        auctioneer.setMinimumBid(minimumBid);

        // Test previewBid returns correct value
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);
        assertGt(previewOhmOut, 0, "previewBid should return non-zero value for bid above minimum");

        // Call function with bid above minimum
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 0, false, false);

        // Should succeed without reverting
    }

    function test_minimumBidZero_allowsAnyBid(
        uint256 bidAmount_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenAddressHasReserveToken(recipient, 1000e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1000e18)
    {
        // convertible = deposit * 1e9 / minPrice
        // deposit = convertible * minPrice / 1e9
        uint256 minimumDepositAmount = (1 * MIN_PRICE) / 1e9;

        // Ensure bid amount is small but non-zero
        uint256 bidAmount = bound(bidAmount_, minimumDepositAmount, 1e18);

        // Set minimum bid to 0 (disabled)
        vm.prank(admin);
        auctioneer.setMinimumBid(0);

        // Test previewBid returns correct value
        uint256 previewOhmOut = auctioneer.previewBid(PERIOD_MONTHS, bidAmount);
        assertGt(previewOhmOut, 0, "previewBid should return non-zero value when minimum bid is 0");

        // Call function with small bid
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, bidAmount, 0, false, false);

        // Should succeed without reverting
    }
}
