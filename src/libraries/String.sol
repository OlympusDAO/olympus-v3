// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

library String {
    /// @notice Truncates a string to 32 bytes
    function truncate32(string memory str_) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes32(abi.encodePacked(str_))));
    }
}
