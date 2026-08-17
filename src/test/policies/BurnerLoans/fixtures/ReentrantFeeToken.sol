// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract ReentrantFeeToken is MockERC20 {
    address internal _callbackInvoker;
    address internal _callbackTarget;
    bytes internal _callbackData;

    bool public callbackEnabled;
    bool public callbackSucceeded;
    bytes4 public callbackRevertSelector;

    constructor() MockERC20("Reentrant USDS", "rUSDS", 18) {}

    function setCallback(address target_, bytes calldata data_) external {
        _callbackInvoker = target_;
        _callbackTarget = target_;
        _callbackData = data_;
        callbackEnabled = true;
    }

    function setCallbackFrom(address invoker_, address target_, bytes calldata data_) external {
        _callbackInvoker = invoker_;
        _callbackTarget = target_;
        _callbackData = data_;
        callbackEnabled = true;
    }

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        bool success = super.transfer(to_, amount_);
        _invokeCallback();
        return success;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public override returns (bool) {
        bool success = super.transferFrom(from_, to_, amount_);
        _invokeCallback();
        return success;
    }

    function _invokeCallback() internal {
        if (callbackEnabled && msg.sender == _callbackInvoker) {
            callbackEnabled = false;
            callbackRevertSelector = bytes4(0);
            bytes memory returnData;
            (callbackSucceeded, returnData) = _callbackTarget.call(_callbackData);
            if (!callbackSucceeded && returnData.length >= 4) {
                bytes4 selector;
                assembly ("memory-safe") {
                    selector := mload(add(returnData, 0x20))
                }
                callbackRevertSelector = selector;
            }
        }
    }
}
