// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library SafeCast {
    error Overflow(uint256 amount);

    function encodeUInt128(uint256 amount) internal pure returns (uint128) {
        if (amount > type(uint128).max) {
            revert Overflow(amount);
        }
        return uint128(amount);
    }
}
