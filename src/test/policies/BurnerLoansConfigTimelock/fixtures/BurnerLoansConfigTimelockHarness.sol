// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

contract BurnerLoansConfigTimelockHarness is BurnerLoansConfigTimelock {
    constructor(
        Kernel kernel_,
        IBurnerLoansConfig config_
    ) BurnerLoansConfigTimelock(kernel_, config_) {}

    function queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) external returns (uint64 actionId) {
        return _queueAction(target_, selector_, payload_);
    }
}
