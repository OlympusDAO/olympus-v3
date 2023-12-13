// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import "@openzeppelin/contracts/utils/Create2.sol";

library ComputeAddress {
    function computeAddress(
        bytes memory creationCode,
        bytes memory creationParams,
        bytes32 salt,
        address deployer
    ) internal pure returns (address) {
        return
            Create2.computeAddress(
                bytes32(salt),
                keccak256(abi.encodePacked(creationCode, creationParams)),
                deployer
            );
    }

    function generateSalt(
        address comparisonAddress,
        bool higher,
        bytes memory creationCode,
        bytes memory creationParams,
        address deployer
    ) internal pure returns (bytes32) {
        // Start with an initial value for the salt
        bytes32 salt = bytes32(0);

        // Iterate until we find a salt that produces an address that is either higher or lower than the comparison address
        while (true) {
            // Increment the salt value
            salt = bytes32(uint256(salt) + 1);

            // Derive the address from the salt
            address derivedAddress = computeAddress(creationCode, creationParams, salt, deployer);

            // If the derived address is higher than the comparison address, we're done
            if (higher && derivedAddress > comparisonAddress) {
                break;
            }

            // If the derived address is lower than the comparison address, we're done
            if (!higher && derivedAddress < comparisonAddress) {
                break;
            }
        }

        return salt;
    }
}
