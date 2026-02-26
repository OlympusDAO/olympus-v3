// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

/// @notice Mock teller whose deploy() always returns address(0).
///         Used to test the zero-address guard in RewardDistributorConvertible._deployConvertibleToken.
contract MockConvertibleOHMTellerZeroDeploy {
    function deploy(address, uint48, uint48, uint256) external pure returns (address) {
        return address(0);
    }
}
