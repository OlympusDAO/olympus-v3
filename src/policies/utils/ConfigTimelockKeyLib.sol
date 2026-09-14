// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  ConfigTimelockKeyLib
/// @notice Derives the destination-scoped configuration keys of `ConfigTimelockBatchQueue`: the
///         keys its reservations are stored under and that `pendingActionId` takes.
/// @dev    Shared by the base, the product timelocks and the tooling that reads the reservations,
///         so that every party computes a key with one formula.
library ConfigTimelockKeyLib {
    /// @notice Returns the destination-scoped key of a local key.
    /// @param  destination_ The destination the key is scoped to.
    /// @param  localKey_ The destination-local key.
    /// @return key The key `keccak256(abi.encode(destination_, localKey_))`.
    function scope(address destination_, bytes32 localKey_) internal pure returns (bytes32 key) {
        return keccak256(abi.encode(destination_, localKey_));
    }
}
