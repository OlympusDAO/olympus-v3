// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract ReentrantFeeToken is MockERC20 {
    error CallbackFailed();

    address internal _callbackInvoker;
    address internal _callbackTarget;
    bytes internal _callbackData;

    bool public callbackEnabled;
    bool public callbackSucceeded;
    bool public bubbleCallbackFailure;
    bool public callbackOnTransfer = true;
    bool public callbackOnTransferFrom = true;
    address public callbackTransferRecipient;
    uint256 public transferCallCount;
    uint256 public callbackOnTransferCall;
    bytes4 public callbackRevertSelector;
    bytes public callbackRevertData;

    constructor() MockERC20("Reentrant USDS", "rUSDS", 18) {}

    function setCallback(address target_, bytes calldata data_) external {
        _callbackInvoker = target_;
        _callbackTarget = target_;
        _callbackData = data_;
        callbackEnabled = true;
        callbackOnTransfer = true;
        callbackOnTransferFrom = true;
    }

    function setCallbackFrom(address invoker_, address target_, bytes calldata data_) external {
        _callbackInvoker = invoker_;
        _callbackTarget = target_;
        _callbackData = data_;
        callbackEnabled = true;
        callbackOnTransfer = true;
        callbackOnTransferFrom = true;
    }

    function setBubbleCallbackFailure(bool enabled_) external {
        bubbleCallbackFailure = enabled_;
    }

    function setCallbackPhases(bool onTransfer_, bool onTransferFrom_) external {
        callbackOnTransfer = onTransfer_;
        callbackOnTransferFrom = onTransferFrom_;
    }

    function setCallbackTransferRecipient(address recipient_) external {
        callbackTransferRecipient = recipient_;
    }

    function setCallbackOnTransferCall(uint256 call_) external {
        transferCallCount = 0;
        callbackOnTransferCall = call_;
    }

    function transfer(address to_, uint256 amount_) public virtual override returns (bool) {
        ++transferCallCount;
        bool success = super.transfer(to_, amount_);
        if (
            callbackOnTransfer &&
            (callbackOnTransferCall == 0 || callbackOnTransferCall == transferCallCount) &&
            (callbackTransferRecipient == address(0) || callbackTransferRecipient == to_)
        ) _invokeCallback();
        return success;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public override returns (bool) {
        bool success = super.transferFrom(from_, to_, amount_);
        if (
            callbackOnTransferFrom &&
            (callbackTransferRecipient == address(0) || callbackTransferRecipient == to_)
        ) _invokeCallback();
        return success;
    }

    function _invokeCallback() internal {
        if (callbackEnabled && msg.sender == _callbackInvoker) {
            callbackEnabled = false;
            callbackRevertSelector = bytes4(0);
            delete callbackRevertData;
            bytes memory returnData;
            // The fixture invokes configurable callback data and records its result.
            // forge-lint: disable-next-line(low-level-calls)
            (callbackSucceeded, returnData) = _callbackTarget.call(_callbackData);
            if (!callbackSucceeded && returnData.length >= 4) {
                callbackRevertData = returnData;
                // The length check proves the selector exists; trailing revert data is ignored.
                // forge-lint: disable-next-line(unsafe-typecast)
                callbackRevertSelector = bytes4(returnData);
            }
            if (!callbackSucceeded && bubbleCallbackFailure) revert CallbackFailed();
        }
    }
}

// forge-lint: disable-end(missing-zero-check)
