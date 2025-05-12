// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICCIPCrossChainBridge {
    // ========= ERRORS ========= //

    error Bridge_NotEnabled();

    error Bridge_NotDisabled();

    error Bridge_InvalidAddress(string param);

    error Bridge_ZeroAmount();

    error Bridge_InsufficientAmount(uint256 expected, uint256 actual);

    error Bridge_InsufficientNativeToken(uint256 expected, uint256 actual);

    error Bridge_InvalidRecipient(address recipient);

    error Bridge_TransferFailed(address caller, address recipient, uint256 amount);

    // ========= EVENTS ========= //

    event BridgeEnabled();

    event BridgeDisabled();

    // ========= SEND OHM ========= //

    /// @notice Sends OHM to the specified destination SVM chain
    /// @dev    This can be used to send to an address on any chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    function sendToSVM(uint64 dstChainSelector_, bytes32 to_, uint256 amount_) external;

    /// @notice Sends OHM to the specified destination EVM chain
    /// @dev    This can be used to send to an address on any EVM chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    function sendToEVM(uint64 dstChainSelector_, address to_, uint256 amount_) external;

    // ========= TOKEN WITHDRAWAL ========= //

    /// @notice Allows the owner to withdraw the native token from the contract
    /// @dev    This is needed as senders may provide more native token than needed to cover fees
    ///
    /// @param  recipient_  The recipient of the native token
    function withdraw(address recipient_) external;
}
