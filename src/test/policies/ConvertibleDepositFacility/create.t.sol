// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract CreateCDFTest is ConvertibleDepositFacilityTest {
    event CreatedDeposit(address indexed user, uint256 indexed termId, uint256 amount);

    // given the contract is inactive
    //  [X] it reverts
    // when the caller does not have the cd_auctioneer role
    //  [X] it reverts
    // when the recipient has not approved CDEPO to spend the reserve tokens
    //  [X] it reverts
    // given the deposit asset has 6 decimals
    //  [X] the amount of CD tokens minted is correct
    //  [X] the mint approval is increased by the correct amount of OHM
    // when multiple positions are created
    //  [X] it succeeds
    // [X] it mints the CD tokens to account_
    // [X] it creates a new position in the CDPOS module
    // [X] it pre-emptively increases the mint approval equivalent to the converted amount of OHM
    // [X] it returns the position ID
    // [X] it emits a CreatedDeposit event

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotActive.selector));

        // Call function
        vm.prank(auctioneer);
        facility.create(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

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
        facility.create(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 10e6)
    {
        uint256 conversionPrice = 2e6;

        // Calculate the expected OHM amount
        uint256 expectedOhmAmount = (10e6 * 1e6) / conversionPrice;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(recipient, 0, 10e6);

        // Call function
        uint256 positionId = _createPosition(
            recipient,
            10e6,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            10e6,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was increased
        assertEq(
            minter.mintApproval(address(facility)),
            expectedOhmAmount,
            "minter.mintApproval(address(facility))"
        );
    }

    function test_success()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Calculate the expected OHM amount
        uint256 expectedOhmAmount = (RESERVE_TOKEN_AMOUNT * 1e18) / CONVERSION_PRICE;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(recipient, 0, RESERVE_TOKEN_AMOUNT);

        // Call function
        uint256 positionId = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was increased
        assertEq(
            minter.mintApproval(address(facility)),
            expectedOhmAmount,
            "minter.mintApproval(address(facility))"
        );
    }

    function test_success_multiple()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Calculate the expected OHM amount
        uint256 expectedOhmAmount = (RESERVE_TOKEN_AMOUNT * 1e18) / CONVERSION_PRICE;

        // Call function
        _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT / 2,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Call function again
        uint256 positionId2 = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT / 2,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Assert that the position ID is 1
        assertEq(positionId2, 1, "positionId2");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert that the recipient has two CDPOS positions
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 2, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");
        assertEq(positionIds[1], 1, "positionIds[1]");

        // Assert that the mint approval was increased
        assertEq(
            minter.mintApproval(address(facility)),
            expectedOhmAmount,
            "minter.mintApproval(address(facility))"
        );
    }
}
