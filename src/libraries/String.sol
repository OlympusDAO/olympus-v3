// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

library String {
    /// @notice Truncates a string to 32 bytes
    function truncate32(string memory str_) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes32(abi.encodePacked(str_))));
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
