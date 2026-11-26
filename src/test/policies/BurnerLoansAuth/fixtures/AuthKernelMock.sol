// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

contract AuthKernelMock {
    bool public active = true;

    function setActive(bool active_) external {
        active = active_;
    }

    function isPolicyActive(address) external view returns (bool) {
        return active;
    }
}
