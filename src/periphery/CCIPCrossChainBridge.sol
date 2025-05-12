// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRouterClient} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouterClient.sol";
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";

// Libraries
import {Owned} from "solmate/auth/Owned.sol";

/// @title  CCIPCrossChainBridge
/// @notice Convenience contract for sending OHM between chains using Chainlink CCIP
///         Although not strictly necessary (as `Router.ccipSend()` can be called directly), this contract makes it easier to use.
///         It is a periphery contract, as it does not require any privileged access to the Olympus protocol.
contract CCIPCrossChainBridge is ICCIPCrossChainBridge, IEnabler, Owned {
    // ========= STATE VARIABLES ========= //

    bool public isEnabled;

    IERC20 public immutable OHM;

    IRouterClient public immutable CCIP_ROUTER;

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

    function _sendOhm(uint64 dstChainSelector_, bytes32 to_, uint256 amount_) internal {
        // Validate the amount
        if (amount_ == 0) revert Bridge_ZeroAmount();

        // Check that the required amount is available
        if (OHM.balanceOf(msg.sender) < amount_)
            revert Bridge_InsufficientAmount(amount_, OHM.balanceOf(msg.sender));

        // Validate that the destination chain is allowed

        // Set up the Router client

        // Determine the fees

        // Pull in the token from the sender

        // Approve the Router to spend the token

        // Send the message to the router
    }

    //    /// @inheritdoc ICCIPCrossChainBridge
    function sendOhm(uint64 dstChainSelector_, bytes32 to_, uint256 amount_) external onlyEnabled {
        _sendOhm(dstChainSelector_, to_, amount_);
    }

    //    /// @inheritdoc ICCIPCrossChainBridge
    function sendOhm(uint64 dstChainSelector_, address to_, uint256 amount_) external onlyEnabled {
        // Validate the recipient EVM address
        if (to_ == address(0)) revert Bridge_InvalidRecipient(to_);

        _sendOhm(dstChainSelector_, bytes32(uint256(uint160(to_))), amount_);
    }

    // ============ ENABLER FUNCTIONS ============ //

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
