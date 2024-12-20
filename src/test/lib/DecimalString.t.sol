// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";
import {DecimalString} from "src/libraries/DecimalString.sol";

contract DecimalStringTest is Test {

    // when valueDecimals is 0
    //  [X] it returns the raw value as a string
    // when valueDecimals is 1-3
    //  [X] it returns the value with a decimal point and the correct number of digits
    // when the decimal value is large
    //  [X] it returns the value correctly to 3 decimal places
    // when the decimal value is small
    //  [X] it returns the value correctly to 3 decimal places
    // when the decimal value is smaller than 3 decimal places
    //  [X] it returns 0

    function test_whenValueDecimalsIs0() public {
        uint256 value = 123456789;
        uint8 valueDecimals = 0;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "123456789", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "123456789", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "123456789", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "123456789", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "123456789", "decimal places is 18");
    }

    function test_whenValueDecimalsIs1() public {
        uint256 value = 123456789;
        uint8 valueDecimals = 1;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "12345678", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "12345678.9", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "12345678.9", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "12345678.9", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "12345678.9", "decimal places is 18");
    }

    function test_whenValueDecimalsIs2() public {
        uint256 value = 123456789;
        uint8 valueDecimals = 2;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "1234567", "decimal places is 0"   );
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "1234567.8", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "1234567.89", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "1234567.89", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "1234567.89", "decimal places is 18");
    }

    function test_whenValueDecimalsIs3() public {
        uint256 value = 123456789;
        uint8 valueDecimals = 3;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "123456", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "123456.7", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "123456.78", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "123456.789", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "123456.789", "decimal places is 18");
    }

    function test_whenValueDecimalValueIsLessThanOne() public {
        uint256 value = 1234;
        uint8 valueDecimals = 4;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "0", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "0.1", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "0.12", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "0.123", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "0.1234", "decimal places is 18");
    }

    function test_whenValueDecimalValueIsGreaterThanOne() public {
        uint256 value = 1234567890000000000;
        uint8 valueDecimals = 18;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "1", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "1.2", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "1.23", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "1.234", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "1.23456789", "decimal places is 18");
    }

    function test_whenValueDecimalValueIsLarge() public {
        uint256 value = 1234567890000000000000;
        uint8 valueDecimals = 18;

        assertEq(DecimalString.toDecimalString(value, valueDecimals, 0), "1234", "decimal places is 0");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 1), "1234.5", "decimal places is 1");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 2), "1234.56", "decimal places is 2");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 3), "1234.567", "decimal places is 3");
        assertEq(DecimalString.toDecimalString(value, valueDecimals, 18), "1234.56789", "decimal places is 18");
    }
}
