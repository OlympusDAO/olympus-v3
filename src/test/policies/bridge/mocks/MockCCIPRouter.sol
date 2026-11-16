// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// A test double of the CCIP router. It shares `getOnRamp` with the script-local
// `ICCIPFeeRouter` by coincidence, and it keeps the fees it is paid: the tests read its balance.
// forge-lint: disable-next-line(missing-inheritance,locked-ether)
contract MockCCIPRouter {
    address public onRamp;
    address public offRamp;
    uint256 public fee;
    uint64 public destinationChainSelector;
    bytes public messageReceiver;
    bytes public messageData;
    address[] public messageTokens;
    uint256[] public messageTokenAmounts;
    bytes public messageExtraArgs;
    address public messageFeeToken;

    bytes32 public constant DEFAULT_MESSAGE_ID = bytes32(uint256(1));

    function getOnRamp(uint64) external view returns (address) {
        return onRamp;
    }

    // A test double: it stores whatever ramp address the test supplies
    // forge-lint: disable-next-line(missing-zero-check)
    function setOnRamp(address onRamp_) external {
        onRamp = onRamp_;
    }

    function isOffRamp(uint64, address offRamp_) external view returns (bool) {
        return offRamp == offRamp_;
    }

    // A test double: it stores whatever ramp address the test supplies
    // forge-lint: disable-next-line(missing-zero-check)
    function setOffRamp(address offRamp_) external {
        offRamp = offRamp_;
    }

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fee;
    }

    function ccipSend(
        uint64 destinationChainSelector_,
        Client.EVM2AnyMessage memory message_
    ) external payable returns (bytes32) {
        // Pull the fees from the sender
        if (msg.value < fee) revert("Insufficient fee");

        // Pull token from the sender
        Client.EVMTokenAmount[] memory tokenAmounts = message_.tokenAmounts;
        // The mock tokens of the tests revert on a failed transfer
        // forge-lint: disable-next-item(erc20-unchecked-transfer)
        IERC20(tokenAmounts[0].token).transferFrom(
            msg.sender,
            address(this),
            tokenAmounts[0].amount
        );

        // Store the message
        destinationChainSelector = destinationChainSelector_;
        messageReceiver = message_.receiver;
        messageData = message_.data;
        messageTokens = new address[](tokenAmounts.length);
        messageTokenAmounts = new uint256[](tokenAmounts.length);
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            messageTokens[i] = tokenAmounts[i].token;
            messageTokenAmounts[i] = tokenAmounts[i].amount;
        }
        messageExtraArgs = message_.extraArgs;
        messageFeeToken = message_.feeToken;

        return DEFAULT_MESSAGE_ID;
    }

    function getMessageTokens() external view returns (address[] memory) {
        return messageTokens;
    }

    function getMessageTokenAmounts() external view returns (uint256[] memory) {
        return messageTokenAmounts;
    }
}
