// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

contract MockOlympusBackingOracle is IOlympusBackingOracle, IERC165 {
    uint256 public override backing;

    constructor(uint256 backing_) {
        backing = backing_;
    }

    function setBacking(uint256 backing_) external override {
        backing = backing_;
        emit BackingSet(backing_);
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IOlympusBackingOracle).interfaceId;
    }
}
