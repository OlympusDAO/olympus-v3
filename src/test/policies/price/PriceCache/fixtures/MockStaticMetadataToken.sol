// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

/// @notice Token code etched over an address previously registered as a non-contract asset.
contract MockStaticMetadataToken {
    function symbol() external pure returns (string memory) {
        return "LATE";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}
