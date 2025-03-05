// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";

contract PreviewConvertCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [X] it reverts
    // when the conversion expiry has passed
    //  [X] it returns 0
    // when the amount is greater than the position's balance
    //  [X] it reverts
    // when the convertible deposit token has different decimals
    //  [X] it returns the correct value
    // when the convertible deposit token has 9 decimals
    //  [X] it returns the correct value
    // when the amount is very small
    //  [X] it returns the correct value
    // when the amount is very large
    //  [X] it returns the correct value
    // when the conversion price is very small
    //  [X] it returns the correct value
    // when the conversion price is very large
    //  [X] it returns the correct value
    // [X] it returns the correct value

    function test_invalidPositionId_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 0));

        // Call function
        CDPOS.previewConvert(0, 0);
    }

    function test_positionExpired(
        uint48 expiry_
    )
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        uint48 expiry = uint48(bound(expiry_, CONVERSION_EXPIRY, type(uint48).max));

        // Warp to expiry and beyond
        vm.warp(expiry);

        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, REMAINING_DEPOSIT);

        // Assert
        assertEq(ohmOut, 0);
    }

    function test_amountGreaterThanRemainingDeposit_reverts(
        uint256 amount_
    )
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        uint256 amount = bound(amount_, REMAINING_DEPOSIT + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "amount"));

        // Call function
        CDPOS.previewConvert(0, amount);
    }

    function test_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, REMAINING_DEPOSIT);

        // Calculate expected ohmOut
        uint256 expectedOhmOut = (REMAINING_DEPOSIT * 1e9) / CONVERSION_PRICE;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_convertibleDepositTokenDecimalsLower()
        public
        givenConvertibleDepositTokenDecimals(17)
        givenPositionCreated(
            address(this),
            10e17,
            2e17,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, 10e17);

        // Calculate expected ohmOut
        uint256 expectedOhmOut = (10e17 * 1e9) / 2e17;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_convertibleDepositTokenDecimalsHigher()
        public
        givenConvertibleDepositTokenDecimals(19)
        givenPositionCreated(
            address(this),
            10e19,
            2e19,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, 10e19);

        // Calculate expected ohmOut
        uint256 expectedOhmOut = (10e19 * 1e9) / 2e19;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_convertibleDepositTokenDecimalsSame()
        public
        givenConvertibleDepositTokenDecimals(9)
        givenPositionCreated(address(this), 10e9, 2e9, CONVERSION_EXPIRY, REDEMPTION_EXPIRY, false)
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, 10e9);

        // Calculate expected ohmOut
        uint256 expectedOhmOut = (10e9 * 1e9) / 2e9;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_conversionPriceVerySmall()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            1,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, REMAINING_DEPOSIT);

        // Calculate expected ohmOut
        // uint256 expectedOhmOut = (REMAINING_DEPOSIT * 1e9) / 1;
        uint256 expectedOhmOut = 25e27;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_conversionPriceVeryLarge()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            1e36,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, REMAINING_DEPOSIT);

        // Calculate expected ohmOut
        // uint256 expectedOhmOut = (REMAINING_DEPOSIT * 1e9) / 1e36;
        uint256 expectedOhmOut = 0;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_amountVerySmall()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, 1);

        // Calculate expected ohmOut
        // uint256 expectedOhmOut = (1 * 1e9) / CONVERSION_PRICE;
        uint256 expectedOhmOut = 0;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }

    function test_amountVeryLarge()
        public
        givenPositionCreated(
            address(this),
            1000e18,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        )
    {
        // Call function
        uint256 ohmOut = CDPOS.previewConvert(0, 1000e18);

        // Calculate expected ohmOut
        // uint256 expectedOhmOut = (1000e18 * 1e9) / CONVERSION_PRICE;
        uint256 expectedOhmOut = 5e11;

        // Assert
        assertEq(ohmOut, expectedOhmOut, "ohmOut");
    }
}
