// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICCIPCrossChainBridge {
    // ========= ERRORS ========= //

    error Bridge_InvalidAddress(string param);

    error Bridge_ZeroAmount();

    error Bridge_InsufficientAmount(uint256 expected, uint256 actual);

    error Bridge_InsufficientNativeToken(uint256 expected, uint256 actual);

    error Bridge_TransferFailed(address caller, address recipient, uint256 amount);

    // ========= EVENTS ========= //

    event Bridged(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address indexed sender,
        uint256 amount,
        uint256 fees
    );

    event Withdrawn(address indexed recipient, uint256 amount);

    // ========= SEND OHM ========= //

    /// @notice Gets the fee for sending OHM to the specified destination SVM chain
    /// @dev    This can be used to send to an address on any chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    ///
    /// @return fee_                The fee for sending OHM to the specified destination chain
    function getFeeSVM(
        uint64 dstChainSelector_,
        bytes32 to_,
        uint256 amount_
    ) external view returns (uint256 fee_);

    /// @notice Gets the fee for sending OHM to the specified destination EVM chain
    /// @dev    This can be used to send to an address on any EVM chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    ///
    /// @return fee_                The fee for sending OHM to the specified destination EVM chain
    function getFeeEVM(
        uint64 dstChainSelector_,
        address to_,
        uint256 amount_
    ) external view returns (uint256 fee_);

    /// @notice Sends OHM to the specified destination SVM chain
    /// @dev    This can be used to send to an address on any chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    /// @return messageId           The message ID of the sent message
    function sendToSVM(
        uint64 dstChainSelector_,
        bytes32 to_,
        uint256 amount_
    ) external payable returns (bytes32 messageId);

    /// @notice Sends OHM to the specified destination EVM chain
    /// @dev    This can be used to send to an address on any EVM chain supported by CCIP
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    /// @param amount_              The amount of OHM to send
    /// @return messageId           The message ID of the sent message
    function sendToEVM(
        uint64 dstChainSelector_,
        address to_,
        uint256 amount_
    ) external payable returns (bytes32 messageId);

    // ========= TOKEN WITHDRAWAL ========= //

    /// @notice Allows the owner to withdraw the native token from the contract
    /// @dev    This is needed as senders may provide more native token than needed to cover fees
    ///
    /// @param  recipient_  The recipient of the native token
    function withdraw(address recipient_) external;
}
