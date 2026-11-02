// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title ConfigTimelockKeyLib
/// @notice Derives destination-scoped configuration keys used by ConfigTimelockBatchQueue.
library ConfigTimelockKeyLib {
    /// @notice Returns the destination-scoped key for a local configuration key.
    /// @param destination_ The configuration destination.
    /// @param localKey_ The key within that destination.
    /// @return key The hash of the destination and local key.
    function scope(address destination_, bytes32 localKey_) internal pure returns (bytes32 key) {
        return keccak256(abi.encode(destination_, localKey_));
    }
}
