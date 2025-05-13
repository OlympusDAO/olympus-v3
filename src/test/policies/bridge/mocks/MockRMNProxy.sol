// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

contract MockRMNProxy {
    mapping(bytes16 => bool) public isCursed;

    function setIsCursed(bytes16 selector, bool cursed) external {
        isCursed[selector] = cursed;
    }
}
