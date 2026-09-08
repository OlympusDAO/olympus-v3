// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.20;

/// @title  SafeCall
/// @notice Performs a call or a static call that caps the returndata copied into memory, so that a
///         callee returning or reverting with oversized returndata cannot inflate the gas cost of
///         the calling contract.
/// @dev    Copied from LayerZero at commit 592625b9e5967643853476445ffe0e777360b906, path
///         `packages/layerzero-v2/evm/messagelib/contracts/libs/SafeCall.sol`, which is itself a
///         copy of the nomad-xyz `ExcessivelySafeCall` library at commit
///         81cd99ce3e69117d665d7601c330ea03b97acce0, path `src/ExcessivelySafeCall.sol`.
///         Copyright (c) Illusory Systems Inc. and LayerZero Labs Ltd., licensed MIT OR
///         Apache-2.0.
///
///         LayerZero changed the nomad original as follows: added the `extcodesize` guard that
///         returns `(false, "")` when the target holds no code, renamed `excessivelySafeCall` to
///         `safeCall` and `excessivelySafeStaticCall` to `safeStaticCall`, dropped the
///         `swapSelector` helper, and raised the pragma from `>=0.7.6` to `^0.8.20`.
///
///         This copy changes the LayerZero source as follows: widened `uint` to `uint256` in the
///         `extcodesize` guard, corrected two stale comments that named a fixed byte count where
///         the code caps at `_maxCopy`, and added the lint suppressions. The executable code is
///         otherwise unchanged.
///
///         Neither function propagates the revert reason. Both return the returndata truncated to
///         `_maxCopy` bytes, which the caller must bubble up itself if it wants to revert. An
///         `Error(string)` payload needs 100 bytes to survive intact, and a callee that runs out
///         of gas returns no data at all, which a caller cannot tell apart from a bare `revert()`.
library SafeCall {
    /// @notice calls a contract with a specified gas limit and value and captures the return data
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _value The value in wei to send to the remote contract
    /// to memory.
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function safeCall(
        address _target,
        uint256 _gas,
        uint256 _value,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // check that target has code
        uint256 size;
        assembly {
            size := extcodesize(_target)
        }
        if (size == 0) {
            // False positive. The lint targets a boolean constant used as a condition or as an
            // operand of a boolean operator, but it flags any boolean literal in a tuple return,
            // `return (true, ...)` included.
            // forge-lint: disable-next-line(boolean-cst)
            return (false, new bytes(0));
        }

        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                _value, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to `_maxCopy` bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function safeStaticCall(
        address _target,
        uint256 _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal view returns (bool, bytes memory) {
        // check that target has code
        uint256 size;
        assembly {
            size := extcodesize(_target)
        }
        if (size == 0) {
            // False positive. The lint targets a boolean constant used as a condition or as an
            // operand of a boolean operator, but it flags any boolean literal in a tuple return,
            // `return (true, ...)` included.
            // forge-lint: disable-next-line(boolean-cst)
            return (false, new bytes(0));
        }

        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := staticcall(
                _gas, // gas
                _target, // recipient
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to `_maxCopy` bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }
}
