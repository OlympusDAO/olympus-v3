// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @dev Keeps Config's original getters and setter behavior while injecting one target callback.
contract TimelockCallbackTarget {
    error UnexpectedCallbackResult(bytes result);
    address internal immutable _implementation;
    address internal immutable _timelock;
    uint64 internal immutable _actionId;
    bool internal immutable _catches;

    constructor(address implementation_, address timelock_, uint64 actionId_, bool catches_) {
        _implementation = implementation_;
        _timelock = timelock_;
        _actionId = actionId_;
        _catches = catches_;
    }

    fallback() external {
        if (msg.sig == IBurnerLoansConfig.setAssetDebtCap.selector && msg.sender == _timelock) {
            (bool ok, bytes memory result) = _timelock.call(
                abi.encodeCall(ITimelockBatchQueue.executeQueuedAction, (_actionId))
            );
            if (
                ok ||
                keccak256(result) !=
                keccak256(
                    abi.encodeWithSelector(
                        ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                        _actionId
                    )
                )
            ) revert UnexpectedCallbackResult(result);
            if (!_catches) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
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
