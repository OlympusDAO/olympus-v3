// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

contract MockOlympusBackingOracle is IOlympusBackingOracle {
    uint256 public override backing;

    constructor(uint256 backing_) {
        backing = backing_;
    }

    function setBacking(uint256 backing_) external override {
        backing = backing_;
        emit BackingSet(backing_);
    }
}
