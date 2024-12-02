// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEmissionManager} from "../../policies/interfaces/IEmissionManager.sol";

contract MockEmissionManager is IEmissionManager {
    constructor() {}

    function execute() external override {
        // do nothing
    }
}
