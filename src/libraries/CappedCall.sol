// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title CappedCall
/// @notice A library that performs a call and captures the returndata truncated to
///         `MAX_RETURNDATA_LENGTH` bytes.
/// @dev The truncation bounds the memory expansion of the capture, so a callee
///      returning or reverting with oversized returndata cannot inflate the gas cost of
///      the calling contract. Intended for isolated best-effort calls whose revert
///      reason is reported through an event.
library CappedCall {
    /// @notice Maximum bytes of returndata captured from a call.
    uint256 internal constant MAX_RETURNDATA_LENGTH = 256;

    /// @notice Performs a call to `target_` and captures the returndata, truncated to
    ///         `MAX_RETURNDATA_LENGTH` bytes.
    /// @dev The caller is responsible for decoding the captured data only when its
    ///      expected length fits under the cap.
    /// @param target_ The call target.
    /// @param callData_ The calldata of the call.
    /// @return success Whether the call succeeded.
    /// @return data The captured returndata, truncated to `MAX_RETURNDATA_LENGTH`
    ///         bytes.
    function tryCall(
        address target_,
        bytes memory callData_
    ) internal returns (bool success, bytes memory data) {
        uint256 maxLength = MAX_RETURNDATA_LENGTH;
        assembly ("memory-safe") {
            success := call(gas(), target_, 0, add(callData_, 0x20), mload(callData_), 0, 0)
            let size := returndatasize()
            if gt(size, maxLength) {
                size := maxLength
            }
            data := mload(0x40)
            mstore(data, size)
            returndatacopy(add(data, 0x20), 0, size)
            mstore(0x40, add(data, and(add(add(size, 0x20), 0x1f), not(0x1f))))
        }
    }
}
