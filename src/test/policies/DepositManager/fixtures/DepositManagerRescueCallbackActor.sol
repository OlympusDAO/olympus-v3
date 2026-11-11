// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";

/// @notice An authorized nested rescuer that varies only Kernel activity during a token callback.
contract DepositManagerRescueCallbackActor {
    Kernel internal immutable _KERNEL;
    address internal immutable _MANAGER;
    address internal immutable _TOKEN;
    bool internal immutable _NESTED_ACTIVE;

    bool public previewSucceeded;
    bytes public previewResult;
    bool public rescueSucceeded;
    bytes public rescueResult;

    constructor(Kernel kernel_, address manager_, address token_, bool nestedActive_) {
        _KERNEL = kernel_;
        _MANAGER = manager_;
        _TOKEN = token_;
        _NESTED_ACTIVE = nestedActive_;
    }

    function callback() external {
        if (!_NESTED_ACTIVE) _KERNEL.executeAction(Actions.DeactivatePolicy, _MANAGER);
        (previewSucceeded, previewResult) = _MANAGER.staticcall(
            abi.encodeWithSignature("previewRescue(address)", _TOKEN)
        );
        (rescueSucceeded, rescueResult) = _MANAGER.call(
            abi.encodeWithSignature("rescue(address)", _TOKEN)
        );
        if (!_NESTED_ACTIVE) _KERNEL.executeAction(Actions.ActivatePolicy, _MANAGER);
    }
}
