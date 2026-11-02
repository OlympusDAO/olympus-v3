// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Fixture callback flags and recorded errors do not grant protocol authority.
// forge-lint: disable-start(missing-events-access-control)

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @dev Optional transfer failures and callbacks that can propagate the original guard bytes.
contract PayoutCallbackToken is MockERC20 {
    error TransferBlocked(address recipient);

    mapping(address => bool) internal _blocked;
    address internal _invoker;
    address internal _target;
    address internal _recipient;
    bytes internal _data;
    bool internal _incoming;
    bool internal _propagate;
    bool internal _armed;
    bytes public callbackError;
    uint256 public callbackAttempts;

    constructor() MockERC20("Payout callback", "PCB", 18) {}

    function setTransferBlocked(address recipient_, bool blocked_) external {
        _blocked[recipient_] = blocked_;
    }

    function armOutgoing(
        address payout_,
        address recipient_,
        bytes calldata data_,
        bool propagate_
    ) external {
        _arm(payout_, payout_, recipient_, data_, false, propagate_);
    }

    function armIncoming(
        address core_,
        address payout_,
        bytes calldata data_,
        bool propagate_
    ) external {
        _arm(core_, payout_, address(0), data_, true, propagate_);
    }

    function disarm() external {
        _armed = false;
    }

    function _arm(
        address invoker_,
        address target_,
        address recipient_,
        bytes memory data_,
        bool incoming_,
        bool propagate_
    ) internal {
        _invoker = invoker_;
        _target = target_;
        _recipient = recipient_;
        _data = data_;
        _incoming = incoming_;
        _propagate = propagate_;
        _armed = true;
        delete callbackError;
        callbackAttempts = 0;
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        if (_blocked[recipient_]) revert TransferBlocked(recipient_);
        bool success = super.transfer(recipient_, amount_);
        if (!_incoming) _callback(recipient_);
        return success;
    }

    function transferFrom(
        address from_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        bool success = super.transferFrom(from_, recipient_, amount_);
        if (_incoming) _callback(recipient_);
        return success;
    }

    function _callback(address recipient_) internal {
        if (
            !_armed ||
            msg.sender != _invoker ||
            (_recipient != address(0) && recipient_ != _recipient)
        ) return;
        _armed = false;
        ++callbackAttempts;
        // Invoke the configured nested action and retain its exact error.
        // forge-lint: disable-next-line(low-level-calls)
        (bool success, bytes memory reason) = _target.call(_data);
        if (success) return;
        callbackError = reason;
        if (_propagate) {
            // Propagation must preserve the original typed guard error.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
    }
}

// forge-lint: disable-end(missing-events-access-control)
