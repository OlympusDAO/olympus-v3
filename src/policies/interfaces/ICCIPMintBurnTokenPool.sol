// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICCIPMintBurnTokenPool {
    // ========= ERRORS ========= //

    error TokenPool_MintApprovalOutOfSync(uint256 expected, uint256 actual);

    error TokenPool_InvalidToken(address expected, address actual);

    error TokenPool_InvalidTokenDecimals(uint8 expected, uint8 actual);

    error TokenPool_ZeroAmount();

    error TokenPool_InvalidAddress(string param);

    error TokenPool_ZeroAddress();

    error TokenPool_InvalidRecipient(address recipient);

    error TokenPool_InsufficientBalance(uint256 expected, uint256 actual);

    error TokenPool_BridgedSupplyExceeded(uint256 bridgedSupply, uint256 amount);

    // ========= FUNCTIONS ========= //

    /// @notice Returns the amount of OHM that has been bridged from mainnet
    /// @dev    The implementing function should only return a value on mainnet
    function getBridgedSupply() external view returns (uint256);
}
