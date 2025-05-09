// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICCIPCrossChainBridge {
    // =========  ERRORS ========= //

    error Bridge_MintApprovalOutOfSync(uint256 expected, uint256 actual);

    error Bridge_InvalidToken(address expected, address actual);

    error Bridge_InvalidTokenDecimals(uint8 expected, uint8 actual);

    error Bridge_ZeroAmount();

    error Bridge_InvalidRecipient(address recipient);

    error Bridge_InsufficientAmount(uint256 expected, uint256 actual);

    // ========= EVENTS ========= //

    // ========= SEND OHM ========= //

    /// @notice Sends OHM to the specified destination chain
    /// @dev    This can be used to send to an address on any chain supported by CCIP (including non-EVM)
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    function sendOhm(uint64 dstChainSelector_, bytes32 to_, uint256 amount_) external;

    /// @notice Sends OHM to the specified destination chain
    /// @dev    This can be used to send to an address on any EVM chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    function sendOhm(uint64 dstChainSelector_, address to_, uint256 amount_) external;

    // ========= VIEW FUNCTIONS ========= //

    /// @notice Returns the quantity of OHM that has been bridged
    /// @dev    This will only be set on mainnet
    function getBridgedSupply() external view returns (uint256);
}
