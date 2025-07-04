// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

contract MockCustomPeriodicTask {
    uint256 public count;
    bool public _revert;

    error MockCustomPeriodicTask_Revert();

    function customExecute() external {
        if (_revert) revert MockCustomPeriodicTask_Revert();

        count++;
    }

    function setRevert(bool revert_) external {
        _revert = revert_;
    }
}
