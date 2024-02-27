// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.15;

import {ContractUtils} from "src/external/governance/lib/ContractUtils.sol";

import {ITimelock} from "./interfaces/ITimelock.sol";

contract Timelock is ITimelock {
    // --- ERRORS ---------------------------------------------------------

    error Timelock_OnlyOnce();
    error Timelock_OnlyAdmin();
    error Timelock_OnlyPendingAdmin();
    error Timelock_OnlyInternalCall();
    error Timelock_InvalidDelay();
    error Timelock_InvalidExecutionTime();
    error Timelock_InvalidTx_Stale();
    error Timelock_InvalidTx_Locked();
    error Timelock_InvalidTx_NotQueued();
    error Timelock_InvalidTx_CodeHashChanged();
    error Timelock_InvalidTx_ExecReverted();

    // --- EVENTS ---------------------------------------------------------

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint256 indexed newDelay);
    event CancelTransaction(
        uint256 indexed proposalId,
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event ExecuteTransaction(
        uint256 indexed proposalId,
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event QueueTransaction(
        uint256 indexed proposalId,
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    // --- STATE VARIABLES ---------------------------------------------------------

    uint256 public constant GRACE_PERIOD = 1 days;
    uint256 public constant MINIMUM_DELAY = 1 days;
    uint256 public constant MAXIMUM_DELAY = 3 days;

    address public admin;
    address public pendingAdmin;
    uint256 public delay;
    bool public initialized;

    mapping(bytes32 => bool) public queuedTransactions;

    // --- CONSTRUCTOR -------------------------------------------------------------

    constructor(address admin_, uint256 delay_) {
        if (delay_ < MINIMUM_DELAY || delay_ > MAXIMUM_DELAY) revert Timelock_InvalidDelay();

        admin = admin_;
        delay = delay_;
    }

    function setFirstAdmin(address admin_) public {
        if (msg.sender != admin) revert Timelock_OnlyAdmin();
        if (initialized) revert Timelock_OnlyOnce();
        initialized = true;
        admin = admin_;

        emit NewAdmin(admin);
    }

    // --- TIMELOCK LOGIC ----------------------------------------------------------

    fallback() external payable {}

    function setDelay(uint256 delay_) public {
        if (msg.sender != address(this)) revert Timelock_OnlyInternalCall();
        if (delay_ < MINIMUM_DELAY || delay_ > MAXIMUM_DELAY) revert Timelock_InvalidDelay();
        delay = delay_;

        emit NewDelay(delay);
    }

    function acceptAdmin() public {
        if (msg.sender != pendingAdmin) revert Timelock_OnlyPendingAdmin();
        admin = msg.sender;
        pendingAdmin = address(0);

        emit NewAdmin(admin);
    }

    function setPendingAdmin(address pendingAdmin_) public {
        if (msg.sender != address(this)) revert Timelock_OnlyInternalCall();
        pendingAdmin = pendingAdmin_;

        emit NewPendingAdmin(pendingAdmin);
    }

    function queueTransaction(
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public returns (bytes32) {
        if (msg.sender != admin) revert Timelock_OnlyAdmin();
        if (eta < block.timestamp + delay) revert Timelock_InvalidExecutionTime();

        bytes32 txHash = keccak256(abi.encode(proposalId, target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(proposalId, txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public {
        if (msg.sender != admin) revert Timelock_OnlyAdmin();

        bytes32 txHash = keccak256(abi.encode(proposalId, target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(proposalId, txHash, target, value, signature, data, eta);
    }

    function executeTransaction(
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        bytes32 codehash,
        uint256 eta
    ) public payable returns (bytes memory) {
        if (msg.sender != admin) revert Timelock_OnlyAdmin();

        bytes32 txHash = keccak256(abi.encode(proposalId, target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) revert Timelock_InvalidTx_NotQueued();
        if (block.timestamp < eta) revert Timelock_InvalidTx_Locked();
        if (block.timestamp > eta + GRACE_PERIOD) revert Timelock_InvalidTx_Stale();

        if (ContractUtils.getCodeHash(target) != codehash)
            revert Timelock_InvalidTx_CodeHashChanged();

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) revert Timelock_InvalidTx_ExecReverted();

        emit ExecuteTransaction(proposalId, txHash, target, value, signature, data, eta);

        return returnData;
    }
}
