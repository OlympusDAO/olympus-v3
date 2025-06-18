// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

library ArrayUtils {
    /// @notice Returns true if the array contains the string value
    function contains(string[] memory array, string memory value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (keccak256(abi.encodePacked(array[i])) == keccak256(abi.encodePacked(value))) {
                return true;
            }
        }

        return false;
    }

    /// @notice Returns true if the array contains the address value
    function contains(address[] memory array, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return true;
            }
        }

        return false;
    }
}
