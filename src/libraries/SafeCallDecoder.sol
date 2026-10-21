// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {SafeCall} from "src/libraries/SafeCall.sol";

/// @title Safe Call Decoder
/// @notice Reads canonical single-word ABI values without bubbling call or decode failures.
library SafeCallDecoder {
    using SafeCall for address;

    uint16 internal constant _ABI_WORD_SIZE = 32;
    uint16 internal constant _MAX_ABI_WORD_RETURN_SIZE = _ABI_WORD_SIZE + 1;

    /// @notice Static-calls a no-argument getter and safely decodes an address return value.
    /// @dev Returns failure for calls that fail or return a short, oversized, or non-canonical word.
    /// @param target_ The contract to query.
    /// @param selector_ The selector of the no-argument getter to call.
    /// @return success True when the call succeeds and returns a canonical address word.
    /// @return value The decoded address, or address(0) when success is false.
    function safeReadAddress(
        address target_,
        bytes4 selector_
    ) internal view returns (bool success, address value) {
        uint256 raw;
        (success, raw) = _safeReadWord(target_, selector_);
        success = success && raw <= type(uint160).max;
        if (!success) return (success, value);

        // The preceding bound proves the conversion cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        value = address(uint160(raw));
    }

    /// @notice Static-calls a no-argument getter and safely decodes a bool return value.
    /// @dev Returns failure for calls that fail or return a short, oversized, or non-canonical word.
    /// @param target_ The contract to query.
    /// @param selector_ The selector of the no-argument getter to call.
    /// @return success True when the call succeeds and returns a canonical bool word.
    /// @return value The decoded bool, or false when success is false.
    function safeReadBool(
        address target_,
        bytes4 selector_
    ) internal view returns (bool success, bool value) {
        uint256 raw;
        (success, raw) = _safeReadWord(target_, selector_);
        success = success && raw <= 1;
        if (!success) return (success, value);
        value = raw == 1;
    }

    function _safeReadWord(
        address target_,
        bytes4 selector_
    ) private view returns (bool success, uint256 value) {
        bytes memory result;
        (success, result) = target_.safeStaticCall(
            gasleft(),
            _MAX_ABI_WORD_RETURN_SIZE,
            abi.encodeWithSelector(selector_)
        );
        success = success && result.length == _ABI_WORD_SIZE;
        if (success) value = abi.decode(result, (uint256));
    }
}
