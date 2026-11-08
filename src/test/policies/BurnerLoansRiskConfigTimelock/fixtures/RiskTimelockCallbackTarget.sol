// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

/// @dev Preserves Risk storage/getters while asserting one caught target callback is rejected.
contract RiskTimelockCallbackTarget {
    error UnexpectedCallbackResult(bytes result);
    address internal immutable _implementation;
    address internal immutable _queue;
    bytes32 internal immutable _expected;
    bytes4 internal immutable _callbackSelector;
    bytes32 internal immutable _callbackArgument;

    constructor(
        address implementation_,
        address queue_,
        bytes memory callback_,
        bytes32 expected_
    ) {
        if (callback_.length != 36) revert UnexpectedCallbackResult(callback_);
        _implementation = implementation_;
        _queue = queue_;
        _expected = expected_;
        _callbackSelector = bytes4(callback_);
        bytes32 argument;
        assembly ("memory-safe") {
            argument := mload(add(callback_, 36))
        }
        _callbackArgument = argument;
    }

    fallback() external {
        if (msg.sig == IBurnerLoansRisk.setReferralFeeBps.selector && msg.sender == _queue) {
            (bool ok, bytes memory result) = _queue.call(
                abi.encodePacked(_callbackSelector, _callbackArgument)
            );
            if (ok || keccak256(result) != _expected) revert UnexpectedCallbackResult(result);
        }
        (bool success, bytes memory data) = _implementation.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(success) {
                revert(add(data, 32), mload(data))
            }
            return(add(data, 32), mload(data))
        }
    }
}
