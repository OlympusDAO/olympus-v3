// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICCIPClient} from "src/external/bridge/ICCIPClient.sol";

interface ICCIPCrossChainBridge {
    // ========= ERRORS ========= //

    error Bridge_InvalidAddress(string param);

    error Bridge_ZeroAmount();

    error Bridge_InsufficientAmount(uint256 expected, uint256 actual);

    error Bridge_InsufficientNativeToken(uint256 expected, uint256 actual);

    error Bridge_TransferFailed(address caller, address recipient, uint256 amount);

    error Bridge_DestinationNotTrusted();

    error Bridge_SourceNotTrusted();

    error Bridge_InvalidCaller();

    error Bridge_FailedMessageNotFound(bytes32 messageId);

    error Bridge_InvalidPayloadTokensLength();

    error Bridge_InvalidPayloadToken();

    error Bridge_TrustedRemoteNotSet();

    // ========= EVENTS ========= //

    event Bridged(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address indexed sender,
        uint256 amount,
        uint256 fees
    );

    event Received(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address indexed sender,
        uint256 amount
    );

    event Withdrawn(address indexed recipient, uint256 amount);

    event TrustedRemoteEVMSet(uint64 indexed dstChainSelector, address indexed to);

    event TrustedRemoteEVMUnset(uint64 indexed dstChainSelector);

    event TrustedRemoteSVMSet(uint64 indexed dstChainSelector, bytes32 indexed to);

    event TrustedRemoteSVMUnset(uint64 indexed dstChainSelector);

    event MessageFailed(bytes32 messageId);

    event RetryMessageSuccess(bytes32 messageId);

    // ========= DATA STRUCTURES ========= //

    struct TrustedRemoteEVM {
        address remoteAddress;
        bool isSet;
    }

    struct TrustedRemoteSVM {
        bytes32 remoteAddress;
        bool isSet;
    }

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

    // ========= RECEIVE OHM ========= //

    /// @notice Gets the failed message for the specified message ID
    ///
    /// @param messageId_ The message ID
    /// @return message_ The failed message
    function getFailedMessage(
        bytes32 messageId_
    ) external view returns (ICCIPClient.Any2EVMMessage memory);

    /// @notice Retries a failed message
    ///
    /// @param messageId_ The message ID
    function retryFailedMessage(bytes32 messageId_) external;

    // ========= TOKEN WITHDRAWAL ========= //

    /// @notice Allows the owner to withdraw the native token from the contract
    /// @dev    This is needed as senders may provide more native token than needed to cover fees
    ///
    /// @param  recipient_  The recipient of the native token
    function withdraw(address recipient_) external;

    // ========= TRUSTED REMOTES ========= //

    /// @notice Sets the trusted remote for the specified destination EVM chain
    /// @dev    This is needed to send/receive messages to/from the specified destination EVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    function setTrustedRemoteEVM(uint64 dstChainSelector_, address to_) external;

    /// @notice Unsets the trusted remote for the specified destination EVM chain
    /// @dev    This is needed to stop sending/receiving messages to/from the specified destination EVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    function unsetTrustedRemoteEVM(uint64 dstChainSelector_) external;

    /// @notice Gets the trusted remote for the specified destination EVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @return to_                The destination address
    function getTrustedRemoteEVM(
        uint64 dstChainSelector_
    ) external view returns (TrustedRemoteEVM memory);

    /// @notice Sets the trusted remote for the specified destination SVM chain
    /// @dev    This is needed to send/receive messages to/from the specified destination SVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    /// @param to_                  The destination address
    function setTrustedRemoteSVM(uint64 dstChainSelector_, bytes32 to_) external;

    /// @notice Unsets the trusted remote for the specified destination SVM chain
    /// @dev    This is needed to stop sending/receiving messages to/from the specified destination SVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    function unsetTrustedRemoteSVM(uint64 dstChainSelector_) external;

    /// @notice Gets the trusted remote for the specified destination SVM chain
    ///
    /// @param dstChainSelector_    The destination chain selector
    ///
    /// @return to_                The destination address
    function getTrustedRemoteSVM(
        uint64 dstChainSelector_
    ) external view returns (TrustedRemoteSVM memory);

    // ========= CONFIGURATION ========= //

    /// @notice Gets the CCIP router address
    ///
    /// @return ccipRouter_ The CCIP router address
    function getCCIPRouter() external view returns (address);
}
