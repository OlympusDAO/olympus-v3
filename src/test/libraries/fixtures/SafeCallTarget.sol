// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SafeCallTarget {
    error SafeCallTarget_Reverted(bytes reason);

    uint256 internal constant _OVERSIZED_RETURN_BYTES = 1024;

    function returnBytes() external pure returns (bytes memory) {
        return new bytes(_OVERSIZED_RETURN_BYTES);
    }

    function revertBytes() external pure {
        revert SafeCallTarget_Reverted(new bytes(_OVERSIZED_RETURN_BYTES));
    }
}
