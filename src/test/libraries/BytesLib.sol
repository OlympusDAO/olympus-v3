// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library BytesLib {
    function bytes32ToString(bytes32 value_) internal pure returns (string memory) {
        uint256 length;
        while (length < 32 && value_[length] != 0) {
            length++;
        }

        bytes memory buffer = new bytes(length);
        for (uint256 i; i < length; i++) {
            buffer[i] = value_[i];
        }

        return string(buffer);
    }
}
