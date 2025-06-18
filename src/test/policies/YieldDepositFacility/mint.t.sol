// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract MintDepositYDFTest is YieldDepositFacilityTest {
    event CreatedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 indexed positionId,
        uint256 depositAmount
    );

    // given the contract is inactive
    //  [X] it reverts
    // when the recipient has not approved CDEPO to spend the reserve tokens
    //  [X] it reverts
    // given the deposit asset has 6 decimals
    //  [X] the amount of CD tokens minted is correct
    // [X] it mints the CD tokens to account_
    // [X] it creates a new position in the CDPOS module
    // [X] the position does not have a conversion price
    // [X] it returns the position ID
    // [X] it emits a CreatedDeposit event
    // [X] it sets the last yield conversion rate

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.mint(cdToken, RESERVE_TOKEN_AMOUNT, false);
    }

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);
    }

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 10e6)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, 10e6);

        // Call function
        uint256 positionId = _createYieldDepositPosition(recipient, 10e6);

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId).conversionPrice,
            type(uint256).max,
            "conversionPrice"
        );

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the CDEPO token was minted to the recipient
        assertEq(cdToken.balanceOf(recipient), 10e6, "cdToken.balanceOf(recipient)");

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");
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
        uint256 lastYieldConversionRate = vault.convertToAssets(1e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, RESERVE_TOKEN_AMOUNT);

        // Call function
        uint256 positionId = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

        // Assert that the position ID is 0
        assertEq(positionId, 0, "positionId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(positionId).conversionPrice,
            type(uint256).max,
            "conversionPrice"
        );

        // Assert that the position is not convertible
        assertEq(convertibleDepositPositions.isConvertible(positionId), false, "isConvertible");

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

        // Assert that the last yield conversion rate is set
        assertEq(
            yieldDepositFacility.positionLastYieldConversionRate(positionId),
            lastYieldConversionRate,
            "positionLastYieldConversionRate"
        );
    }
}
