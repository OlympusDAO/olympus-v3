// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

contract MockPeriodicTask is IPeriodicTask {
    uint256 public count;
    bool public _revert;

    error MockPeriodicTask_Revert();

    function execute() external override {
        if (_revert) revert MockPeriodicTask_Revert();

        count++;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IPeriodicTask).interfaceId;
    }

    function setRevert(bool revert_) external {
        _revert = revert_;
    }
}
