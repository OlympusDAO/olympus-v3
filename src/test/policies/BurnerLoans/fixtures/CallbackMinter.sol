// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {MINTRv1, OHM} from "src/modules/MINTR/MINTR.v1.sol";

contract CallbackMinter is MINTRv1 {
    address internal _callbackTarget;
    bytes internal _callbackData;

    bool public callbackSucceeded;
    bytes4 public callbackRevertSelector;

    constructor(Kernel kernel_, address ohm_) Module(kernel_) {
        ohm = OHM(ohm_);
        active = true;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    function setCallback(address target_, bytes calldata data_) external {
        _callbackTarget = target_;
        _callbackData = data_;
    }

    function mintOhm(address to_, uint256 amount_) external override permissioned onlyWhileActive {
        uint256 approval = mintApproval[msg.sender];
        if (approval < amount_) revert MINTR_NotApproved();
        mintApproval[msg.sender] = approval - amount_;
        callbackRevertSelector = bytes4(0);
        bytes memory returnData;
        // The fixture invokes configurable callback data and records its result.
        // forge-lint: disable-next-line(low-level-calls)
        (callbackSucceeded, returnData) = _callbackTarget.call(_callbackData);
        if (!callbackSucceeded && returnData.length >= 4) {
            // The length check proves the selector exists; trailing revert data is ignored.
            // forge-lint: disable-next-line(unsafe-typecast)
            callbackRevertSelector = bytes4(returnData);
        }
        ohm.mint(to_, amount_);
    }

    function burnOhm(address, uint256) external pure override {
        revert MINTR_NotActive();
    }

    function increaseMintApproval(address policy_, uint256 amount_) external override permissioned {
        mintApproval[policy_] += amount_;
    }

    function decreaseMintApproval(address policy_, uint256 amount_) external override permissioned {
        uint256 approval = mintApproval[policy_];
        mintApproval[policy_] = amount_ < approval ? approval - amount_ : 0;
    }

    function deactivate() external override {
        active = false;
    }

    function activate() external override {
        active = true;
    }
}

// forge-lint: disable-end(missing-zero-check)
