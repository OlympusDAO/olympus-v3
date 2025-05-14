// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

contract MockRMNProxy {
    mapping(bytes16 => bool) internal _isSet;
    mapping(bytes16 => bool) internal _isCursed;

    error NotSet();

    function setIsCursed(bytes16 selector, bool cursed) external {
        _isSet[selector] = true;
        _isCursed[selector] = cursed;
    }

    function isCursed(bytes16 selector) external view returns (bool) {
        if (!_isSet[selector]) revert NotSet();

        return _isCursed[selector];
    }
}
