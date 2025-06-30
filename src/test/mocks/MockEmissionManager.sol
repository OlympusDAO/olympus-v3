// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

contract MockEmissionManager is IEmissionManager, IPeriodicTask {
    constructor() {}

    function execute() external override {
        // do nothing
    }
}
