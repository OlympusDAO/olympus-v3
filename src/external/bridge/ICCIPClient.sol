// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Copied from `Client.sol` in `chainlink-ccip-1.6.0`
interface ICCIPClient {
    // Both structs keep the names of the Chainlink `Client` structs they are copied from
    // forge-lint: disable-next-line(pascal-case-struct)
    struct EVMTokenAmount {
        address token; // token address on the local chain.
        uint256 amount; // Amount of tokens.
    }

    // forge-lint: disable-next-line(pascal-case-struct)
    struct Any2EVMMessage {
        bytes32 messageId; // MessageId corresponding to ccipSend on source.
        uint64 sourceChainSelector; // Source chain selector.
        bytes sender; // abi.decode(sender) if coming from an EVM chain.
        bytes data; // payload sent in original message.
        EVMTokenAmount[] destTokenAmounts; // Tokens and their amounts in their destination chain representation.
    }
}
