// SPDX-License-Identifier: BSD
pragma solidity ^0.8.4;

import {Clone as BaseClone} from "@clones-with-immutable-args-1.1.2/Clone.sol";

/// @title Clone
/// @notice Extends the base Clone contract with additional immutable arg readers.
contract Clone is BaseClone {
    /// @notice Reads an immutable arg with type uint48
    /// @param argOffset The offset of the arg in the packed data
    /// @return arg The arg value
    function _getArgUint48(uint256 argOffset) internal pure returns (uint48 arg) {
        uint256 offset = _getImmutableArgsOffset();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            arg := shr(0xd0, calldataload(add(offset, argOffset)))
        }
    }
}
