// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  AddressStorageArray
/// @notice A library for managing a storage array of addresses, with support for insertion and removal at a specific index
library AddressStorageArray {
    error AddressStorageArray_IndexOutOfBounds(uint256 index, uint256 length);

    /// @notice Inserts an address at a specific index
    function insert(address[] storage array, address value_, uint256 index_) internal {
        // Validate that the index is within the bounds or the end of the array
        if (index_ > array.length)
            revert AddressStorageArray_IndexOutOfBounds(index_, array.length);

        // Add a new element to the end of the array
        array.push(address(0));

        // Shift all elements after the index to the right
        for (uint256 i = array.length - 1; i > index_; i--) {
            array[i] = array[i - 1];
        }

        // Insert the value at the index
        array[index_] = value_;
    }

    /// @notice Removes an address at a specific index
    function remove(address[] storage array, uint256 index_) internal returns (address) {
        // Validate that the index is within the bounds of the array
        if (index_ >= array.length)
            revert AddressStorageArray_IndexOutOfBounds(index_, array.length);

        // Get the value at the index
        address removedValue = array[index_];

        // Shift all elements after the index to the left
        for (uint256 i = index_; i < array.length - 1; i++) {
            array[i] = array[i + 1];
        }

        // Remove the last (empty) element
        array.pop();

        // Return the removed value
        return removedValue;
    }
}
