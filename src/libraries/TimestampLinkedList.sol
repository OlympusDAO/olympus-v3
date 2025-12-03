// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

/// @title TimestampLinkedList
/// @notice A library for managing linked lists of uint48 timestamps in descending order
/// @dev    Each list maintains timestamps in descending chronological order (newest first)
library TimestampLinkedList {
    // ========== ERRORS ========== //

    error TimestampLinkedList_InvalidTimestamp(uint48 timestamp);

    // ========== STRUCTS ========== //

    /// @notice Structure representing a timestamp linked list
    /// @param head The most recent (largest) timestamp in the list
    /// @param previous Mapping from timestamp to the previous (older) timestamp
    struct List {
        uint48 head;
        mapping(uint48 => uint48) previous;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Adds a new timestamp to the list in descending order
    /// @dev    Does nothing if timestamp already exists
    /// @dev    This function will revert if:
    /// @dev    - The timestamp is 0
    ///
    /// @param  list The list to add to
    /// @param  timestamp The timestamp to add
    function add(List storage list, uint48 timestamp) internal {
        if (timestamp == 0) revert TimestampLinkedList_InvalidTimestamp(timestamp);

        if (contains(list, timestamp)) {
            return; // Already exists, do nothing
        }

        // If list is empty or timestamp is newer than head, make it the new head
        if (list.head == 0 || timestamp > list.head) {
            list.previous[timestamp] = list.head;
            list.head = timestamp;
            return;
        }

        // Find the correct position to insert (maintain descending order)
        uint48 current = list.head;
        while (list.previous[current] != 0 && list.previous[current] > timestamp) {
            current = list.previous[current];
        }

        // Insert between current and current.previous
        list.previous[timestamp] = list.previous[current];
        list.previous[current] = timestamp;
    }

    /// @notice Finds the largest timestamp that is less than or equal to the target
    /// @dev    Returns 0 if no such timestamp exists
    /// @param  list The list to search
    /// @param  target The target timestamp
    /// @return The largest timestamp ≤ target, or 0 if none found
    function findLastBefore(List storage list, uint48 target) internal view returns (uint48) {
        uint48 current = list.head;

        // Traverse the list until we find a timestamp <= target
        while (current != 0 && current > target) {
            current = list.previous[current];
        }

        return current;
    }

    /// @notice Finds the smallest timestamp that is greater than the target
    /// @dev    Returns 0 if no such timestamp exists
    /// @param  list The list to search
    /// @param  target The target timestamp
    /// @return The smallest timestamp > target, or 0 if none found
    function findFirstAfter(List storage list, uint48 target) internal view returns (uint48) {
        if (list.head == 0) return 0;

        uint48 result = 0;
        uint48 current = list.head;

        // Traverse the entire list to find the smallest timestamp > target
        while (current != 0) {
            if (current > target) {
                result = current;
            }
            current = list.previous[current];
        }

        return result;
    }

    /// @notice Checks if a timestamp exists in the list
    /// @param  list The list to check
    /// @param  timestamp The timestamp to look for
    /// @return True if timestamp exists in the list
    function contains(List storage list, uint48 timestamp) internal view returns (bool) {
        if (timestamp == 0) return false;
        if (list.head == timestamp) return true;

        uint48 current = list.head;
        while (current != 0) {
            if (list.previous[current] == timestamp) return true;
            current = list.previous[current];
        }

        return false;
    }

    /// @notice Returns the most recent (head) timestamp
    /// @param  list The list to check
    /// @return The head timestamp, or 0 if list is empty
    function getHead(List storage list) internal view returns (uint48) {
        return list.head;
    }

    /// @notice Returns the previous timestamp for a given timestamp
    /// @param  list The list to check
    /// @param  timestamp The timestamp to get the previous for
    /// @return The previous timestamp, or 0 if none
    function getPrevious(List storage list, uint48 timestamp) internal view returns (uint48) {
        return list.previous[timestamp];
    }

    /// @notice Checks if the list is empty
    /// @param  list The list to check
    /// @return True if the list is empty
    function isEmpty(List storage list) internal view returns (bool) {
        return list.head == 0;
    }

    /// @notice Returns the number of elements in the list
    /// @dev    This is an O(n) operation, use sparingly
    /// @param  list The list to count
    /// @return The number of timestamps in the list
    function length(List storage list) internal view returns (uint256) {
        if (list.head == 0) return 0;

        uint256 count = 1;
        uint48 current = list.head;

        while (list.previous[current] != 0) {
            current = list.previous[current];
            count++;
        }

        return count;
    }

    /// @notice Returns all timestamps in the list in descending order
    /// @dev    This is an O(n) operation with O(n) memory allocation, use sparingly
    /// @param  list The list to convert to array
    /// @return timestamps Array of timestamps in descending order
    function toArray(List storage list) internal view returns (uint48[] memory timestamps) {
        uint256 len = length(list);
        if (len == 0) return new uint48[](0);

        timestamps = new uint48[](len);
        uint48 current = list.head;

        for (uint256 i = 0; i < len; i++) {
            timestamps[i] = current;
            current = list.previous[current];
        }

        return timestamps;
    }
}
