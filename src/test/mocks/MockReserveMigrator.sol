// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IReserveMigrator} from "../../policies/interfaces/IReserveMigrator.sol";

contract MockReserveMigrator is IReserveMigrator {
    constructor() {}

    function migrate() external override {
        // do nothing
    }
}
