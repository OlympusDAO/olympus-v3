// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerBidTest is ConvertibleDepositAuctioneerTest {
    function _assertConvertibleDepositPosition(
        uint256 bidAmount_,
        uint256 expectedConvertedAmount_,
        uint256 expectedReserveTokenBalance_,
        uint256 previousConvertibleDepositBalance_,
        uint256 previousPositionCount_,
        uint256 returnedOhmOut_,
        uint256 returnedPositionId_
    ) internal {
        // Assert that the converted amount is as expected
        assertEq(returnedOhmOut_, expectedConvertedAmount_, "converted amount");

        // Assert that the CD tokens were transferred to the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            previousConvertibleDepositBalance_ + bidAmount_,
            "CD token balance"
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
    }

    // when the contract is deactivated
    //  [X] it reverts
    // when the contract has not been initialized
    //  [X] it reverts
    // when the caller has not approved CDEPO to spend the bid token
    //  [X] it reverts
    // when the "cd_auctioneer" role is not granted to the auctioneer contract
    //  [X] it reverts
    // when the bid amount converted is 0
    //  [X] it reverts
    // when the bid is the first bid
    //  [X] it sets the day's deposit balance
    //  [X] it sets the day's converted balance
    //  [X] it sets the lastUpdate to the current block timestamp
    //  [X] it deducts the converted amount from the tick capacity
    //  [X] it does not update the tick price
    // when the bid is the first bid of the day
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [X] it resets the day's deposit and converted balances
    //  [X] it updates the day's deposit balance
    //  [X] it updates the day's converted balance
    //  [X] it sets the lastUpdate to the current block timestamp
    // when the bid is not the first bid of the day
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [X] it does not reset the day's deposit and converted balances
    //  [X] it updates the day's deposit balance
    //  [X] it updates the day's converted balance
    //  [X] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is less than the remaining tick capacity
    //  when the calculated deposit amount is 0
    //   [ ] it completes bidding and leaves a remainder of the bid token
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [ ] it returns the amount of OHM that can be converted
    //  [ ] it issues CD terms with the current tick price and time to expiry
    //  [ ] it updates the day's deposit balance
    //  [ ] it updates the day's converted balance
    //  [ ] it deducts the converted amount from the tick capacity
    //  [ ] it does not update the tick price
    //  [ ] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is equal to the remaining tick capacity
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  when the tick step is > 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] it updates the tick price to be higher than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is < 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] it updates the tick price to be lower than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is = 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] the tick price is unchanged
    //   [ ] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is greater than the remaining tick capacity
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  when the tick step is > 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] it updates the new tick price to be higher than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is < 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] it updates the new tick price to be lower than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is = 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] the tick price is unchanged
    //   [ ] it sets the lastUpdate to the current block timestamp

    function test_givenContractNotInitialized_reverts() public {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.bid(1e18);
    }

    function test_givenContractInactive_reverts() public givenInitialized givenContractInactive {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.bid(1e18);
    }

    function test_givenSpendingNotApproved_reverts()
        public
        givenInitialized
        givenContractActive
        givenAddressHasReserveToken(recipient, 1e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(1e18);
    }

    function test_givenAuctioneerRoleNotGranted_reverts()
        public
        givenInitialized
        givenContractActive
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 1e18)
    {
        // Revoke the auctioneer role
        rolesAdmin.revokeRole("cd_auctioneer", address(auctioneer));

        // Expect revert
        _expectRoleRevert("cd_auctioneer");

        // Call function
        vm.prank(recipient);
        auctioneer.bid(1e18);
    }

    function test_givenBidAmountConvertedIsZero_reverts(
        uint256 bidAmount_
    )
        public
        givenInitialized
        givenContractActive
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 1e18)
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
        auctioneer.bid(bidAmount);
    }

    function test_givenBidAmountConvertedIsAboveZero(
        uint256 bidAmount_
    )
        public
        givenInitialized
        givenContractActive
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 1e18)
    {
        // We want a bid amount that will result in a converted amount of 0
        // Given bid amount * 1e9 / 15e18 = converted amount
        // When bid amount = 15e9, the converted amount = 1
        uint256 bidAmount = bound(bidAmount_, 15e9, 1e18);

        // Calculate the expected converted amount
        uint256 expectedConvertedAmount = (bidAmount * 1e9) / 15e18;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId) = auctioneer.bid(bidAmount);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            1e18 - bidAmount,
            0,
            0,
            ohmOut,
            positionId
        );
    }

    function test_givenFirstBid()
        public
        givenInitialized
        givenAddressHasReserveToken(recipient, 3e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 3e18)
    {
        // Expected converted amount
        // 3e18 * 1e9 / 15e18 = 2e8
        uint256 bidAmount = 3e18;
        uint256 expectedConvertedAmount = 2e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId) = auctioneer.bid(bidAmount);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            0,
            0,
            ohmOut,
            positionId
        );

        // Assert the day state
        assertEq(auctioneer.getDayState().deposits, bidAmount, "day deposits");
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertState(TARGET, TICK_SIZE, MIN_PRICE, uint48(block.timestamp));

        // Assert the tick
        _assertPreviousTick(TICK_SIZE - expectedConvertedAmount, MIN_PRICE);
    }

    function test_givenFirstBidOfDay()
        public
        givenInitialized
        givenRecipientHasBid(120e18)
        givenAddressHasReserveToken(recipient, 6e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 6e18)
    {
        // Warp to the next day
        uint48 nextDay = uint48(block.timestamp) + 1 days;
        vm.warp(nextDay);

        // Get the current tick for the new day
        IConvertibleDepositAuctioneer.Tick memory beforeTick = auctioneer.getCurrentTick();

        // Expected converted amount
        // 6e18 * 1e9 / 15e18 = 4e8
        uint256 bidAmount = 6e18;
        uint256 expectedConvertedAmount = 4e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId) = auctioneer.bid(bidAmount);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            120e18,
            1,
            ohmOut,
            positionId
        );

        // Assert the day state
        // Not affected by the previous day's bid
        assertEq(auctioneer.getDayState().deposits, bidAmount, "day deposits");
        assertEq(auctioneer.getDayState().convertible, expectedConvertedAmount, "day convertible");

        // Assert the state
        _assertState(TARGET, TICK_SIZE, MIN_PRICE, uint48(nextDay));

        // Assert the tick
        _assertPreviousTick(beforeTick.capacity - expectedConvertedAmount, beforeTick.price);
    }

    function test_secondBidUpdatesDayState()
        public
        givenInitialized
        givenRecipientHasBid(3e18)
        givenAddressHasReserveToken(recipient, 6e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 6e18)
    {
        // Previous converted amount
        // 3e18 * 1e9 / 15e18 = 2e8
        uint256 previousBidAmount = 3e18;
        uint256 previousConvertedAmount = 2e8;

        // Expected converted amount
        // 6e18 * 1e9 / 15e18 = 4e8
        uint256 bidAmount = 6e18;
        uint256 expectedConvertedAmount = 4e8;

        // Check preview
        (uint256 previewOhmOut, ) = auctioneer.previewBid(bidAmount);

        // Assert that the preview is as expected
        assertEq(previewOhmOut, expectedConvertedAmount, "preview converted amount");

        // Call function
        vm.prank(recipient);
        (uint256 ohmOut, uint256 positionId) = auctioneer.bid(bidAmount);

        // Assert returned values
        _assertConvertibleDepositPosition(
            bidAmount,
            expectedConvertedAmount,
            0,
            3e18,
            1,
            ohmOut,
            positionId
        );

        // Assert the day state
        // Not affected by the previous day's bid
        assertEq(auctioneer.getDayState().deposits, previousBidAmount + bidAmount, "day deposits");
        assertEq(
            auctioneer.getDayState().convertible,
            previousConvertedAmount + expectedConvertedAmount,
            "day convertible"
        );

        // Assert the state
        _assertState(TARGET, TICK_SIZE, MIN_PRICE, uint48(block.timestamp));

        // Assert the tick
        _assertPreviousTick(
            TICK_SIZE - previousConvertedAmount - expectedConvertedAmount,
            MIN_PRICE
        );
    }
}
