// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

library String {
    error EndBeforeStartIndex(uint256 startIndex, uint256 endIndex);
    error EndIndexOutOfBounds(uint256 endIndex, uint256 length);

    /// @notice Truncates a string to 32 bytes
    function truncate32(string memory str_) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes32(abi.encodePacked(str_))));
    }

    /// @notice Converts a bytes32 value to a string
    /// @dev    Trims null characters from the end of the string
    ///
    /// @param  value_ The bytes32 value to convert to a string
    /// @return string The string representation of the bytes32 value
    function bytes32ToString(bytes32 value_) internal pure returns (string memory) {
        uint256 length;
        while (length < 32 && value_[length] != 0) {
            unchecked {
                ++length;
            }
        }

        bytes memory buffer = new bytes(length);
        for (uint256 i; i < length; ) {
            buffer[i] = value_[i];

            unchecked {
                ++i;
            }
        }

        return string(buffer);
    }

    /// @notice Returns a substring of a string
    ///
    /// @param  str_            The string to get the substring of
    /// @param  startIndex_     The index to start the substring at
    /// @param  endIndex_       The index to end the substring at
    /// @return resultString    The substring
    function substring(
        string memory str_,
        uint256 startIndex_,
        uint256 endIndex_
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str_);

        if (endIndex_ < startIndex_) revert EndBeforeStartIndex(startIndex_, endIndex_);
        if (endIndex_ > strBytes.length) revert EndIndexOutOfBounds(endIndex_, strBytes.length);

        bytes memory result = new bytes(endIndex_ - startIndex_);
        for (uint256 i = startIndex_; i < endIndex_; i++) {
            result[i - startIndex_] = strBytes[i];
        }
        return string(result);
    }

    /// @notice Returns a substring of a string from a given index
    ///
    /// @param  str_ The string to get the substring of
    /// @param  startIndex_ The index to start the substring at
    /// @return resultString The substring
    function substringFrom(
        string memory str_,
        uint256 startIndex_
    ) internal pure returns (string memory) {
        return substring(str_, startIndex_, bytes(str_).length);
    }
}
