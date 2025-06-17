// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract ConvertibleDepositFacilityCreatePositionTest is ConvertibleDepositFacilityTest {
    event CreatedDeposit(
        address indexed asset,
        address indexed depositor,
        uint256 indexed positionId,
        uint8 periodMonths,
        uint256 depositAmount
    );

    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(auctioneer);
        facility.createPosition(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            false,
            true
        );
    }

    // when the caller does not have the cd_auctioneer role
    //  [X] it reverts

    function test_callerNotAuctioneer_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("cd_auctioneer"))
        );

        // Call function
        facility.createPosition(
            iReserveToken,
            PERIOD_MONTHS,
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            false,
            true
        );
    }

    // when the recipient has not approved deposit manager to spend the reserve tokens
    //  [X] it reverts

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT, CONVERSION_PRICE, false, false);
    }

    // given the deposit asset has 6 decimals
    //  [X] the amount of CD tokens minted is correct
    //  [X] mint approval is not changed

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 10e6)
    {
        uint256 conversionPrice = 2e6;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, PERIOD_MONTHS, 10e6);

        // Call function
        uint256 positionId = _createPosition(recipient, 10e6, conversionPrice, false, true);

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId).conversionPrice,
            conversionPrice,
            "conversionPrice"
        );

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, 10e6, true);

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
    }

    // [X] it mints the CD tokens to account_
    // [X] it creates a new position in the CDPOS module
    // [X] mint approval is not changed
    // [X] the position conversion price matches
    // [X] it returns the position ID
    // [X] it emits a CreatedDeposit event

    function test_success()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(
            address(reserveToken),
            recipient,
            0,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        uint256 positionId = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            false,
            true
        );

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId).conversionPrice,
            CONVERSION_PRICE,
            "conversionPrice"
        );

        // Assert that the position is convertible
        assertEq(convertibleDepositPositions.isConvertible(positionId), true, "isConvertible");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, RESERVE_TOKEN_AMOUNT, true);

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
    }

    // when multiple positions are created
    //  [X] it succeeds

    function test_success_multiple()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Call function
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT / 2, CONVERSION_PRICE, false);

        // Call function again
        uint256 positionId2 = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT / 2,
            CONVERSION_PRICE,
            false,
            true
        );

        // Assert that the position ID is 1
        assertEq(positionId2, 1, "positionId2");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId2).conversionPrice,
            CONVERSION_PRICE,
            "conversionPrice"
        );

        // Assert that the position is convertible
        assertEq(convertibleDepositPositions.isConvertible(positionId2), true, "isConvertible");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, RESERVE_TOKEN_AMOUNT, true);

        // Assert that the recipient has two CDPOS positions
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 2, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");
        assertEq(positionIds[1], 1, "positionIds[1]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
    }

    // when wrapReceipt is false
    //  [X] the ERC6909 receipt token is minted

    function test_whenWrapReceiptIsFalse()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(
            address(reserveToken),
            recipient,
            0,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        uint256 positionId = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            false,
            false
        );

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId).conversionPrice,
            CONVERSION_PRICE,
            "conversionPrice"
        );

        // Assert that the position is convertible
        assertEq(convertibleDepositPositions.isConvertible(positionId), true, "isConvertible");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, RESERVE_TOKEN_AMOUNT, false);

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
    }
}
