// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRouterClient} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouterClient.sol";
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {ICCIPClient} from "src/external/bridge/ICCIPClient.sol";

// Libraries
import {Owned} from "solmate/auth/Owned.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";

// Contracts
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";
import {CCIPReceiver} from "@chainlink-ccip-1.6.0/ccip/applications/CCIPReceiver.sol";

/// @title  CCIPCrossChainBridge
/// @notice Sends and receives OHM between chains using Chainlink CCIP
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
///
///         The contract is designed to be an intermediary when receiving OHM, so that failed messages can be retried.
contract CCIPCrossChainBridge is CCIPReceiver, PeripheryEnabler, Owned, ICCIPCrossChainBridge {
    // ========= STATE VARIABLES ========= //

    IERC20 public immutable OHM;

    /// @notice Mapping of EVM chain selectors to trusted bridge contracts
    /// @dev    When sending, this is used to determine the initial recipient of a bridging message.
    ///         When receiving, this is used to validate the sender of the message.
    mapping(uint64 => address) internal _trustedRemoteEVM;

    /// @notice Mapping of SVM chain selectors to trusted recipients
    /// @dev    When sending, this is used to determine the initial recipient of a bridging message.
    mapping(uint64 => bytes32) internal _trustedRemoteSVM;

    /// @notice Mapping of message IDs to failed messages
    /// @dev    When a message fails to receive, it is stored here to allow for retries.
    mapping(bytes32 => Client.Any2EVMMessage) internal _failedMessages;

    // ========= CONSTANTS ========= //

    uint32 internal constant _SVM_DEFAULT_COMPUTE_UNITS = 0;

    /// @dev This is non-zero to allow for message handling by the bridge contract on the destination chain
    uint32 internal constant _DEFAULT_GAS_LIMIT = 200_000;

    // ========= CONSTRUCTOR ========= //

    constructor(
        address ohm_,
        address ccipRouter_,
        address owner_
    ) Owned(owner_) CCIPReceiver(ccipRouter_) {
        // Validate
        if (ohm_ == address(0)) revert Bridge_InvalidAddress("ohm");
        if (owner_ == address(0)) revert Bridge_InvalidAddress("owner");

        // Set state
        OHM = IERC20(ohm_);

        // Disabled by default
    }

    // ========= SENDING OHM ========= //

    function _buildCCIPMessage(
        bytes memory to_,
        uint256 amount_,
        bytes memory data_,
        bytes memory extraArgs_
    ) internal view returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(OHM), amount: amount_});

        // Prepare the message struct
        return
            Client.EVM2AnyMessage({
                receiver: to_, // Receiver address
                data: data_, // Data
                tokenAmounts: tokenAmounts, // Token amounts
                extraArgs: extraArgs_, // Extra args
                feeToken: address(0) // Fee paid in native token
            });
    }

    function _getSVMExtraArgs(bytes32 to_) internal pure returns (bytes memory) {
        return
            Client._svmArgsToBytes(
                Client.SVMExtraArgsV1({
                    computeUnits: _SVM_DEFAULT_COMPUTE_UNITS,
                    accountIsWritableBitmap: 0,
                    allowOutOfOrderExecution: true,
                    tokenReceiver: to_,
                    accounts: new bytes32[](0)
                })
            );
    }

    function _getEVMExtraArgs() internal pure returns (bytes memory) {
        return
            Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: _DEFAULT_GAS_LIMIT,
                    allowOutOfOrderExecution: true
                })
            );
    }

    function _getEVMData(
        uint64 dstChainSelector_,
        address to_
    ) internal view returns (bytes memory recipient, bytes memory data, bytes memory extraArgs) {
        // Validate that the recipient is not the zero address
        if (to_ == address(0)) revert Bridge_InvalidAddress("recipient");

        // Validate that the destination chain has a trusted remote
        address trustedRemote = _trustedRemoteEVM[dstChainSelector_];
        if (trustedRemote == address(0)) revert Bridge_DestinationNotTrusted();

        // Initial recipient is the trusted remote (this contract on the destination chain)
        recipient = abi.encode(trustedRemote);
        // Data contains the actual recipient address
        data = abi.encode(to_);
        // Extra args
        extraArgs = _getEVMExtraArgs();

        return (recipient, data, extraArgs);
    }

    function _getSVMData(
        uint64 dstChainSelector_,
        bytes32 to_
    ) internal view returns (bytes memory recipient, bytes memory data, bytes memory extraArgs) {
        // Validate that the destination chain has a trusted remote
        bytes32 trustedRemote = _trustedRemoteSVM[dstChainSelector_];
        if (trustedRemote == bytes32(0)) revert Bridge_DestinationNotTrusted();

        // Initial recipient is the trusted remote (this contract on the destination chain)
        recipient = abi.encodePacked(trustedRemote);
        // Data is empty
        data = "";
        // Extra args
        extraArgs = _getSVMExtraArgs(to_);
        return (recipient, data, extraArgs);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function getFeeSVM(
        uint64 dstChainSelector_,
        bytes32 to_,
        uint256 amount_
    ) external view returns (uint256 fee_) {
        // Get the recipient and data
        // This also validates that the destination chain is supported
        (bytes memory recipient, bytes memory data, bytes memory extraArgs) = _getSVMData(
            dstChainSelector_,
            to_
        );

        fee_ = IRouterClient(i_ccipRouter).getFee(
            dstChainSelector_,
            _buildCCIPMessage(recipient, amount_, data, extraArgs)
        );
        return fee_;
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function getFeeEVM(
        uint64 dstChainSelector_,
        address to_,
        uint256 amount_
    ) external view returns (uint256 fee_) {
        // Get the recipient and data
        // This also validates that the destination chain is supported
        (bytes memory recipient, bytes memory data, bytes memory extraArgs) = _getEVMData(
            dstChainSelector_,
            to_
        );

        // Get the fees
        fee_ = IRouterClient(i_ccipRouter).getFee(
            dstChainSelector_,
            _buildCCIPMessage(recipient, amount_, data, extraArgs)
        );
        return fee_;
    }

    function _sendOhm(
        uint64 dstChainSelector_,
        bytes memory to_,
        uint256 amount_,
        bytes memory data_,
        bytes memory extraArgs_
    ) internal returns (bytes32) {
        // Validate the amount
        if (amount_ == 0) revert Bridge_ZeroAmount();

        // Build the CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _buildCCIPMessage(
            to_,
            amount_,
            data_,
            extraArgs_
        );

        // Determine the fees
        uint256 fees = IRouterClient(i_ccipRouter).getFee(dstChainSelector_, ccipMessage);

        // Validate that the sender has provided sufficient native token to cover fees
        if (msg.value < fees) revert Bridge_InsufficientNativeToken(fees, msg.value);

        // Sending the excess native token to the sender can create problems if the sender cannot receive it
        // Any excess can be retrieved by the owner via the `withdraw` function

        // Validate that the sender has sufficient OHM
        if (OHM.balanceOf(msg.sender) < amount_)
            revert Bridge_InsufficientAmount(amount_, OHM.balanceOf(msg.sender));

        // Pull in OHM from the sender
        OHM.transferFrom(msg.sender, address(this), amount_);

        // Approve the Router to spend the token
        OHM.approve(address(i_ccipRouter), amount_);

        // Send the message to the router
        // The TokenPool will perform validation on the routing
        bytes32 ccipMessageId = IRouterClient(i_ccipRouter).ccipSend{value: fees}(
            dstChainSelector_,
            ccipMessage
        );

        // Emit the event
        emit Bridged(ccipMessageId, dstChainSelector_, msg.sender, amount_, fees);

        // Return the message ID
        return ccipMessageId;
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function sendToSVM(
        uint64 dstChainSelector_,
        bytes32 to_,
        uint256 amount_
    ) external payable onlyEnabled returns (bytes32) {
        // Get the recipient and data
        // This also validates that the destination chain is supported
        (bytes memory recipient, bytes memory data, bytes memory extraArgs) = _getSVMData(
            dstChainSelector_,
            to_
        );

        // Send the message to the router
        return _sendOhm(dstChainSelector_, recipient, amount_, data, extraArgs);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function sendToEVM(
        uint64 dstChainSelector_,
        address to_,
        uint256 amount_
    ) external payable onlyEnabled returns (bytes32) {
        // Get the recipient and data
        // This also validates that the destination chain is supported
        (bytes memory recipient, bytes memory data, bytes memory extraArgs) = _getEVMData(
            dstChainSelector_,
            to_
        );

        // Send the message to the router
        return _sendOhm(dstChainSelector_, recipient, amount_, data, extraArgs);
    }

    // ========= TOKEN WITHDRAWAL ========= //

    /// @inheritdoc ICCIPCrossChainBridge
    function withdraw(address recipient_) external onlyOwner {
        // Validate the recipient address
        if (recipient_ == address(0)) revert Bridge_InvalidAddress("recipient");

        // Get the balance of the contract
        uint256 balance = address(this).balance;

        // Revert if the balance is zero
        if (balance == 0) revert Bridge_ZeroAmount();

        // Send the balance to the recipient
        (bool success, ) = recipient_.call{value: balance}("");
        if (!success) revert Bridge_TransferFailed(msg.sender, recipient_, balance);

        // Emit the event
        emit Withdrawn(recipient_, balance);
    }

    // ========= CCIP RECEIVER ========= //

    /// @inheritdoc CCIPReceiver
    /// @dev        This function is designed to not revert, and instead will capture any errors in order to mark the message as failed. The message can be retried using the `retryFailedMessage()` function.
    function _ccipReceive(Client.Any2EVMMessage memory message_) internal override {
        // Assumptions:
        // - The caller has already been validated by the `ccipReceive()` function to be the CCIP router
        // - Bridging from SVM will not go through this contract

        // Attempt to receive the message
        // We catch any errors in order to mark the message as failed
        try this.receiveMessage(message_) {
            // Message received successfully
        } catch {
            // Message failed to receive
            // Mark the message as failed

            Client.Any2EVMMessage storage failedMessage = _failedMessages[message_.messageId];
            failedMessage.messageId = message_.messageId;
            failedMessage.sourceChainSelector = message_.sourceChainSelector;
            failedMessage.sender = message_.sender;
            failedMessage.data = message_.data;

            // Delete the array, in case it was previously set (however unlikely)
            delete failedMessage.destTokenAmounts;
            // Iterate over the token amounts and add them. This is needed as Solidity does not support adding a memory array to a struct in storage.
            for (uint256 i = 0; i < message_.destTokenAmounts.length; i++) {
                failedMessage.destTokenAmounts.push(message_.destTokenAmounts[i]);
            }

            emit MessageFailed(message_.messageId);
        }
    }

    /// @notice Actual handler for receiving CCIP messages
    /// @dev    Does NOT support receiving messages from SVM, since they will not go through this contract
    function _receiveMessage(Client.Any2EVMMessage memory message_) internal {
        // Validate that the contract is enabled
        if (!isEnabled) revert NotEnabled();

        // Validate that the sender is a trusted remote
        // This will be the sending bridge contract, as it is set in the OnRamp.forwardFromRouter() function
        address sourceBridge = abi.decode(message_.sender, (address));
        if (sourceBridge != _trustedRemoteEVM[message_.sourceChainSelector])
            revert Bridge_SourceNotTrusted();

        // There should only be a single token and amount specified in the message
        if (message_.destTokenAmounts.length != 1) revert Bridge_InvalidPayloadTokensLength();

        // Validate that the token is OHM
        if (message_.destTokenAmounts[0].token != address(OHM)) revert Bridge_InvalidPayloadToken();

        // Decode the message data
        address recipient = abi.decode(message_.data, (address));

        // Transfer the OHM to the actual recipient
        OHM.transfer(recipient, message_.destTokenAmounts[0].amount);

        // Emit the event
        emit Received(
            message_.messageId,
            message_.sourceChainSelector,
            sourceBridge,
            message_.destTokenAmounts[0].amount
        );
    }

    /// @notice Receives a message from the CCIP router
    /// @dev    This function can only be called by the contract
    function receiveMessage(Client.Any2EVMMessage calldata message_) external {
        // Validate that the caller is this contract
        if (msg.sender != address(this)) revert Bridge_InvalidCaller();

        // Call the handler
        _receiveMessage(message_);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    /// @dev        This function will revert if:
    ///             - The message is not in the failedMessages mapping
    ///             - The message sender is not a trusted remote
    ///             - The message tokens array is not of length 1
    ///             - The message token is not OHM
    ///             - The message data is not a valid EVM address
    function retryFailedMessage(bytes32 messageId_) external {
        // Validate that the message is in the failedMessages mapping
        if (_failedMessages[messageId_].sourceChainSelector == 0)
            revert Bridge_FailedMessageNotFound(messageId_);

        // Remove the message from the failedMessages mapping
        Client.Any2EVMMessage memory message = _failedMessages[messageId_];
        delete _failedMessages[messageId_];

        // Call the handler
        _receiveMessage(message);

        // Emit the event
        emit RetryMessageSuccess(messageId_);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    /// @dev        This function re-creates the Client.Any2EVMMessage struct in order to return the correct type. This is done to avoid requiring the caller to import the `Client` library.
    function getFailedMessage(
        bytes32 messageId_
    ) external view returns (ICCIPClient.Any2EVMMessage memory) {
        Client.Any2EVMMessage memory message = _failedMessages[messageId_];

        ICCIPClient.EVMTokenAmount[] memory destTokenAmounts = new ICCIPClient.EVMTokenAmount[](
            message.destTokenAmounts.length
        );
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            destTokenAmounts[i] = ICCIPClient.EVMTokenAmount({
                token: message.destTokenAmounts[i].token,
                amount: message.destTokenAmounts[i].amount
            });
        }

        return
            ICCIPClient.Any2EVMMessage({
                messageId: message.messageId,
                sourceChainSelector: message.sourceChainSelector,
                sender: message.sender,
                data: message.data,
                destTokenAmounts: destTokenAmounts
            });
    }

    // ========= TRUSTED REMOTES ========= //

    /// @inheritdoc ICCIPCrossChainBridge
    function setTrustedRemoteEVM(uint64 dstChainSelector_, address to_) external onlyOwner {
        _trustedRemoteEVM[dstChainSelector_] = to_;
        emit TrustedRemoteEVMSet(dstChainSelector_, to_);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function getTrustedRemoteEVM(uint64 dstChainSelector_) external view returns (address) {
        return _trustedRemoteEVM[dstChainSelector_];
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function setTrustedRemoteSVM(uint64 dstChainSelector_, bytes32 to_) external onlyOwner {
        _trustedRemoteSVM[dstChainSelector_] = to_;
        emit TrustedRemoteSVMSet(dstChainSelector_, to_);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function getTrustedRemoteSVM(uint64 dstChainSelector_) external view returns (bytes32) {
        return _trustedRemoteSVM[dstChainSelector_];
    }

    // ========= CONFIGURATION ========= //

    /// @inheritdoc ICCIPCrossChainBridge
    function getCCIPRouter() external view returns (address) {
        return i_ccipRouter;
    }

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(ICCIPCrossChainBridge).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ========= ENABLER FUNCTIONS ========= //

    /// @inheritdoc PeripheryEnabler
    function _enable(bytes calldata) internal override {}

    /// @inheritdoc PeripheryEnabler
    function _disable(bytes calldata) internal override {}

    /// @inheritdoc PeripheryEnabler
    function _onlyOwner() internal view override {
        // Validate that the caller is the owner
        // String literal to keep it consistent with the solmate onlyOwner modifier
        // solhint-disable-next-line gas-custom-errors
        if (msg.sender != owner) revert("UNAUTHORIZED");
    }
}
