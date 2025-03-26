// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract MintCallOptionCDFTest is ConvertibleDepositFacilityTest {
    event CreatedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 indexed positionId,
        uint256 depositAmount
    );

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
    // [ ] the position conversion price matches
    // [X] it returns the position ID
    // [X] it emits a CreatedDeposit event

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(auctioneer);
        facility.mintCallOption(cdToken, recipient, RESERVE_TOKEN_AMOUNT, CONVERSION_PRICE, false);
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
        facility.mintCallOption(cdToken, recipient, RESERVE_TOKEN_AMOUNT, CONVERSION_PRICE, false);
    }

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT, CONVERSION_PRICE, false);
    }

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 10e6)
    {
        uint256 conversionPrice = 2e6;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, 10e6);

        // Call function
        uint256 positionId = _createPosition(recipient, 10e6, conversionPrice, false);

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(cdToken.balanceOf(recipient), 10e6, "cdToken.balanceOf(recipient)");

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
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
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, RESERVE_TOKEN_AMOUNT);

        // Call function
        uint256 positionId = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT,
            CONVERSION_PRICE,
            false
        );

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(
            cdToken.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT,
            "cdToken.balanceOf(recipient)"
        );

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
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
        // Call function
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT / 2, CONVERSION_PRICE, false);

        // Call function again
        uint256 positionId2 = _createPosition(
            recipient,
            RESERVE_TOKEN_AMOUNT / 2,
            CONVERSION_PRICE,
            false
        );

        // Assert that the position ID is 1
        assertEq(positionId2, 1, "positionId2");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(
            cdToken.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT,
            "cdToken.balanceOf(recipient)"
        );

        // Assert that the recipient has two CDPOS positions
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 2, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");
        assertEq(positionIds[1], 1, "positionIds[1]");

        // Assert that the mint approval was NOT increased
        _assertMintApproval(0);
    }
}
