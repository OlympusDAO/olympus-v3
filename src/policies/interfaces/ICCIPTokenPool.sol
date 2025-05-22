// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICCIPTokenPool {
    // ========= ERRORS ========= //

    error TokenPool_InvalidToken(address expected, address actual);

    // ========= FUNCTIONS ========= //

    /// @notice Returns the amount of OHM that has been bridged from mainnet
    /// @dev    The implementing function should only return a value on mainnet
    function getBridgedSupply() external view returns (uint256);
}
