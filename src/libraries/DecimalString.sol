// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8;

import {uint2str} from "./Uint2Str.sol";

library DecimalString {
    /// @notice Converts a uint256 value to a string with a specified number of decimal places.
    ///         The value is adjusted by the scale factor and then formatted to the specified number of decimal places.
    ///         The decimal places are not zero-padded, so the result is not always the same length.
    /// @dev    This is inspired by code in [FixedStrikeOptionTeller](https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/fixed-strike/FixedStrikeOptionTeller.sol#L722).
    ///
    /// @param  value_            The uint256 value to convert to a string.
    /// @param  valueDecimals_    The scale factor of the value.
    /// @param  decimalPlaces_    The number of decimal places to format the value to.
    /// @return result            A string representation of the value with the specified number of decimal places.
    function toDecimalString(
        uint256 value_,
        uint8 valueDecimals_,
        uint8 decimalPlaces_
    ) internal pure returns (string memory) {
        // Handle zero case
        if (value_ == 0) return "0";

        // Convert the entire number to string first
        string memory str = uint2str(value_);
        bytes memory bStr = bytes(str);

        // If no decimal places requested, just handle the scaling and return
        if (decimalPlaces_ == 0) {
            if (bStr.length <= valueDecimals_) return "0";
            return uint2str(value_ / (10 ** valueDecimals_));
        }

        // If value is a whole number, return as-is
        if (valueDecimals_ == 0) return str;

        // Calculate decimal places to show (limited by request and available decimals)
        uint256 maxDecimalPlaces = valueDecimals_ > decimalPlaces_
            ? decimalPlaces_
            : valueDecimals_;

        // Handle numbers smaller than 1
        if (bStr.length <= valueDecimals_) {
            bytes memory smallResult = new bytes(2 + maxDecimalPlaces);
            smallResult[0] = "0";
            smallResult[1] = ".";

            uint256 leadingZeros = valueDecimals_ - bStr.length;
            uint256 zerosToAdd = leadingZeros > maxDecimalPlaces ? maxDecimalPlaces : leadingZeros;

            // Add leading zeros after decimal
            for (uint256 i = 0; i < zerosToAdd; i++) {
                smallResult[i + 2] = "0";
            }

            // Add available digits
            for (uint256 i = 0; i < maxDecimalPlaces - zerosToAdd && i < bStr.length; i++) {
                smallResult[i + 2 + zerosToAdd] = bStr[i];
            }

            return string(smallResult);
        }

        // Find decimal position and last significant digit
        uint256 decimalPosition = bStr.length - valueDecimals_;
        uint256 lastNonZeroPos = decimalPosition;
        for (uint256 i = 0; i < maxDecimalPlaces && i + decimalPosition < bStr.length; i++) {
            if (bStr[decimalPosition + i] != "0") {
                lastNonZeroPos = decimalPosition + i + 1;
            }
        }

        // Create and populate result
        bytes memory finalResult = new bytes(
            lastNonZeroPos - decimalPosition > 0 ? lastNonZeroPos + 1 : lastNonZeroPos
        );

        for (uint256 i = 0; i < decimalPosition; i++) {
            finalResult[i] = bStr[i];
        }

        if (lastNonZeroPos > decimalPosition) {
            finalResult[decimalPosition] = ".";
            for (uint256 i = 0; i < lastNonZeroPos - decimalPosition; i++) {
                finalResult[decimalPosition + 1 + i] = bStr[decimalPosition + i];
            }
        }

        return string(finalResult);
    }
}
