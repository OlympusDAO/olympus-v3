// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRouterClient} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouterClient.sol";
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";

// Libraries
import {Owned} from "solmate/auth/Owned.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";

/// @title  CCIPCrossChainBridge
/// @notice Convenience contract for sending OHM between chains using Chainlink CCIP
///         Although not strictly necessary (as `Router.ccipSend()` can be called directly), this contract makes it easier to use.
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
contract CCIPCrossChainBridge is ICCIPCrossChainBridge, IEnabler, Owned {
    // ========= STATE VARIABLES ========= //

    bool public isEnabled;

    IERC20 public immutable OHM;

    IRouterClient public immutable CCIP_ROUTER;

    // ========= CONSTANTS ========= //

    bytes internal constant _SVM_DEFAULT_PUBKEY = "11111111111111111111111111111111";
    uint32 internal constant _SVM_DEFAULT_COMPUTE_UNITS = 0;
    uint32 internal constant _DEFAULT_GAS_LIMIT = 0;

    // ========= CONSTRUCTOR ========= //

    constructor(address ohm_, address ccipRouter_, address owner_) Owned(owner_) {
        // Validate
        if (ohm_ == address(0)) revert Bridge_InvalidAddress("ohm");
        if (ccipRouter_ == address(0)) revert Bridge_InvalidAddress("ccipRouter");

        // Set state
        OHM = IERC20(ohm_);
        CCIP_ROUTER = IRouterClient(ccipRouter_);
    }

    // ========= SENDING OHM ========= //

    function _buildCCIPMessage(
        bytes memory to_,
        uint256 amount_,
        bytes memory extraArgs_
    ) internal view returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(OHM), amount: amount_});

        // Prepare the message struct
        return
            Client.EVM2AnyMessage({
                receiver: to_, // Receiver address
                data: "", // No data
                tokenAmounts: tokenAmounts, // Token amounts
                extraArgs: extraArgs_, // Extra args
                feeToken: address(0) // Fee paid in native token
            });
    }

    function _sendOhm(
        uint64 dstChainSelector_,
        bytes memory to_,
        uint256 amount_,
        bytes memory extraArgs_
    ) internal {
        // Validate the amount
        if (amount_ == 0) revert Bridge_ZeroAmount();

        // Build the CCIP message
        Client.EVM2AnyMessage memory ccipMessage = _buildCCIPMessage(to_, amount_, extraArgs_);

        // Determine the fees
        uint256 fees = CCIP_ROUTER.getFee(dstChainSelector_, ccipMessage);

        // Validate that the sender has provided sufficient native token to cover fees
        if (msg.value < fees) revert Bridge_InsufficientNativeToken(fees, msg.value);

        // Validate that the sender has sufficient OHM
        if (OHM.balanceOf(msg.sender) < amount_)
            revert Bridge_InsufficientAmount(amount_, OHM.balanceOf(msg.sender));

        // Pull in OHM from the sender
        OHM.transferFrom(msg.sender, address(this), amount_);

        // Approve the Router to spend the token
        OHM.approve(address(CCIP_ROUTER), amount_);

        // Send the message to the router
        // The TokenPool will perform validation on the routing
        bytes32 ccipMessageId = CCIP_ROUTER.ccipSend{value: fees}(dstChainSelector_, ccipMessage);

        // Emit the event
        emit Bridged(ccipMessageId, dstChainSelector_, msg.sender, amount_, fees);
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function sendToSVM(
        uint64 dstChainSelector_,
        bytes32 to_,
        uint256 amount_
    ) external onlyEnabled {
        // Send the message to the router
        _sendOhm(
            dstChainSelector_,
            _SVM_DEFAULT_PUBKEY,
            amount_,
            Client._svmArgsToBytes(
                Client.SVMExtraArgsV1({
                    computeUnits: _SVM_DEFAULT_COMPUTE_UNITS,
                    accountIsWritableBitmap: 0,
                    allowOutOfOrderExecution: true,
                    tokenReceiver: to_,
                    accounts: new bytes32[](0)
                })
            )
        );
    }

    /// @inheritdoc ICCIPCrossChainBridge
    function sendToEVM(
        uint64 dstChainSelector_,
        address to_,
        uint256 amount_
    ) external onlyEnabled {
        // Validate the recipient EVM address
        if (to_ == address(0)) revert Bridge_InvalidRecipient(to_);

        // Send the message to the router
        _sendOhm(
            dstChainSelector_,
            abi.encode(to_),
            amount_,
            Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: _DEFAULT_GAS_LIMIT,
                    allowOutOfOrderExecution: true
                })
            )
        );
    }

    // ========= TOKEN WITHDRAWAL ========= //

    /// @inheritdoc ICCIPCrossChainBridge
    function withdraw(address recipient_) external onlyOwner {
        // Get the balance of the contract
        uint256 balance = address(this).balance;

        // Revert if the balance is zero
        if (balance == 0) revert Bridge_ZeroAmount();

        // Send the balance to the recipient
        (bool success, ) = recipient_.call{value: balance}("");
        if (!success) revert Bridge_TransferFailed(msg.sender, recipient_, balance);
    }

    // ========= ENABLER FUNCTIONS ========= //

    modifier onlyEnabled() {
        if (!isEnabled) revert Bridge_NotEnabled();
        _;
    }

    /// @inheritdoc IEnabler
    function enable(bytes calldata) external onlyOwner {
        // Validate that the contract is disabled
        if (isEnabled) revert Bridge_NotDisabled();

        // Enable the contract
        isEnabled = true;

        // Emit the enabled event
        emit BridgeEnabled();
    }

    /// @inheritdoc IEnabler
    function disable(bytes calldata) external onlyEnabled onlyOwner {
        // Disable the contract
        isEnabled = false;

        // Emit the disabled event
        emit BridgeDisabled();
    }
}
