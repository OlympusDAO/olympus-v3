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

    function encodeUInt112(uint256 amount) internal pure returns (uint112) {
        if (amount > type(uint112).max) {
            revert Overflow(amount);
        }
        return uint112(amount);
    }

    function encodeUInt96(uint256 amount) internal pure returns (uint96) {
        if (amount > type(uint96).max) {
            revert Overflow(amount);
        }
        return uint96(amount);
    }

    function encodeUInt48(uint256 amount) internal pure returns (uint48) {
        if (amount > type(uint48).max) {
            revert Overflow(amount);
        }
        return uint48(amount);
    }

    function encodeUInt32(uint256 amount) internal pure returns (uint32) {
        if (amount > type(uint32).max) {
            revert Overflow(amount);
        }
        return uint32(amount);
    }

    function encodeUInt16(uint256 amount) internal pure returns (uint16) {
        if (amount > type(uint16).max) {
            revert Overflow(amount);
        }
        return uint16(amount);
    }
}
