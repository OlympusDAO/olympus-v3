// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";

/// @notice The Mainnet Receiver receives transfer requests from Satellite Requesters,
///         validating and processing their transfer requests and sending OHM or
///         reserves given checks are passed. Processing occurs once per day, triggered
///         by the Olympus Heart. Transferable tokens, recipient addresses, and daily
///         limits are all stored within the Receiver to reduce reliance on message validity.
contract MainnetReceiver is NonblockingLzApp, Policy, RolesConsumer {
    error InvalidInput();

    // Structs
    struct TokenTransfer {
        address token;
        uint256 amount;
        uint16 sourceChain;
    }

    // Modules
    TRSRYv1 public TRSRY;

    // Addresses
    address[] public validTokens;
    IStargateRouter public bridge;
    mapping(uint16 => address) public chainRecipients;
    
    // Queues and Limits
    TokenTransfer[] public pendingTransfers;
    mapping(address => mapping(uint16 => uint256)) public chainTokenLimits;
    mapping(address => uint256) public globalTokenLimits;
    mapping(bytes32 => bool) public processedMessages;
    uint16 public epochCounter;
    uint16 public epochLimit;
    
    // Events
    event TransferQueued(address token, uint256 amount, uint16 sourceChain);
    event TransferProcessed(address token, uint256 amount, uint16 sourceChain);
    event TransferRejected(address token, uint256 amount, uint16 sourceChain, string reason);
    
    constructor(address _lzEndpoint, Kernel kernel_) NonblockingLzApp(_lzEndpoint) Policy(kernel_) {}

    // ========= HEARTBEAT ========= //

    /// @notice     process requests received for a given day
    /// @dev        called by Olympus Heart, executes once per day
    function processPendingTransfers() external hasRole("heart") {
        epochCounter++;
        if ((epochCounter % epochLimit) != 0) return;

        mapping(uint16 => uint256) memory chainUsage;
        mapping(address => uint256) memory tokenUsage;
        
        for (uint i = 0; i < pendingTransfers.length; i++) {
            // pull request info and delete from array
            TokenTransfer memory transfer = pendingTransfers[i];
            delete pendingTransfers[i];
            
            // check request is within daily limits
            uint256 chainLimit = chainTokenLimits[transfer.token][transfer.sourceChain];
            uint256 globalLimit = globalTokenLimits[transfer.token];
            
            if (chainUsage[transfer.sourceChain] + transfer.amount > chainLimit) {
                emit TransferRejected(transfer.token, transfer.amount, transfer.sourceChain, "Chain limit exceeded");
                continue;
            }
            
            if (tokenUsage[transfer.token] + transfer.amount > globalLimit) {
                emit TransferRejected(transfer.token, transfer.amount, transfer.sourceChain, "Global limit exceeded");
                continue;
            }

            // fetch and validate recipient on request chain
            address recipient = chainRecipients[transfer.sourceChain];
            require(recipient != address(0), "Recipient not set");

            // fetch tokens for transfer
            if (validTokens[0] == transfer.token) MINTR.mintOhm(address(this), amount);
            else {
                TRSRY.increaseWithdrawApproval(address(this), token, amount);
                TRSRY.withdrawReserves(address(this), token, amount);
            }

            // transfer tokens to request chain
            IERC20(transfer.token).approve(bridge, transfer.amount);
            bridge.swap{value: 0}(
                transfer.sourceChain,    // destination chain id
                0,                       // source pool id
                0,                       // destination pool id
                payable(msg.sender),     // refund address
                transfer.amount,         // amount
                0,                       // amountMin
                IStargateRouter.lzTxObj(0, 0, "0x"),
                abi.encodePacked(chainRecipients[transfer.sourceChain]),
                bytes("")               // payload
            );
            
            // update daily usage metrics
            chainUsage[transfer.sourceChain] += transfer.amount;
            tokenUsage[transfer.token] += transfer.amount;
            
            emit TransferProcessed(transfer.token, transfer.amount, transfer.sourceChain);
        }
    }

    /// @notice handle receiving requests from other chains
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        bytes32 messageId = keccak256(abi.encodePacked(_srcChainId, _srcAddress, _nonce, _payload));
        require(!processedMessages[messageId], "Already processed");
        processedMessages[messageId] = true;
        
        (uint8 tokenIndex, uint256 amount) = abi.decode(_payload, (uint8, uint256));
        require(tokenIndex < validTokens.length, "Invalid token index");
        
        pendingTransfers.push(TokenTransfer({
            token: validTokens[tokenIndex],
            amount: amount,
            sourceChain: _srcChainId
        }));
        
        emit TransferQueued(validTokens[tokenIndex], amount, _srcChainId);
    }

    // ========= ADMIN ========= //

    /// @notice             set number of epochs between processing
    /// @dev                attempts to maintain previous cadence for first post-change execution
    /// @dev                only callable by bridge admin
    /// @param limit        new number of epochs
    function setEpochLimit(uint256 limit) external hasRole("bridge_admin") {
        if (limit == 0) revert InvalidInput();
        uint256 epochsUntilNext = (epochLimit - epochCounter);
        epochCounter = (limit > epochsUntilNext) ? limit - epochsUntilNext : 0;
        epochLimit = limit;
    }
    
    /// @notice             set daily limit for token transferred to specific chain
    /// @dev                only callable by bridge admin
    /// @param token        token being transferred
    /// @param chainId      chain to transfer to
    /// @param limit        max number of tokens transferrable per day
    function setTokenLimit(address token, uint16 chainId, uint256 limit) external hasRole("bridge_admin") {
        chainTokenLimits[token][chainId] = limit;
    }
    
    /// @notice             set daily limit for token transferred to any chain
    /// @dev                only callable by bridge admin
    /// @param token        token being transferred
    /// @param limit        max number of tokens transferrable per day
    function setGlobalTokenLimit(address token, uint256 limit) external hasRole("bridge_admin") {
        globalTokenLimits[token] = limit;
    }

    /// @notice             set layerzero bridge contract address
    /// @dev                only callable by bridge admin
    /// @param _bridge      new bridge address
    function setBridge(address _bridge) external hasRole("bridge_admin") {
        bridge = _bridge;
    }

    /// @notice             set recipient address for tokens on a chain
    /// @dev                only callable by bridge admin
    /// @param chainId      id of chain with recipient
    /// @param recipient    address of recipient on chain
    function setChainRecipient(uint16 chainId, address recipient) external hasRole("bridge_admin") {
        chainRecipients[chainId] = recipient;
    }
    
    /// @notice             add requestable token
    /// @dev                only callable by bridge admin
    /// @param token        token made requestable
    function addValidToken(address token) external hasRole("bridge_admin") {
        validTokens.push(token);
    }

    // ========= GUARDIAN ========= //

    /// @notice             remove pending transfer from queue
    /// @dev                for use by guardian in case of malicious request
    /// @param pendingID    array index of invalid pending request
    function invalidatePending(uint pendingID) external hasRole("bridge_guardian") {
        delete pendingTransfers[pendingID];
    }
}