// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Keycode, Role} from "../Kernel.sol";

error TargetNotAContract(address target_);
error InvalidKeycode(Keycode keycode_);
error InvalidRole(Role role_);

// solhint-disable-next-line func-visibility
function toKeycode(bytes5 keycode_) pure returns (Keycode) {
    return Keycode.wrap(keycode_);
}

// solhint-disable-next-line func-visibility
function fromKeycode(Keycode keycode_) pure returns (bytes5) {
    return Keycode.unwrap(keycode_);
}

// solhint-disable-next-line func-visibility
function toRole(bytes32 role_) pure returns (Role) {
    return Role.wrap(role_);
}

// solhint-disable-next-line func-visibility
function fromRole(Role role_) pure returns (bytes32) {
    return Role.unwrap(role_);
}

// solhint-disable-next-line func-visibility
function ensureContract(address target_) view {
    uint256 size;
    assembly {
        size := extcodesize(target_)
    }
    if (size == 0) revert TargetNotAContract(target_);
}

// solhint-disable-next-line func-visibility
function ensureValidKeycode(Keycode keycode_) pure {
    bytes5 unwrapped = Keycode.unwrap(keycode_);

    for (uint256 i = 0; i < 5; ) {
        bytes1 char = unwrapped[i];

        if (char < 0x41 || char > 0x5A) revert InvalidKeycode(keycode_); // A-Z only

        unchecked {
            i++;
        }
    }
}

// solhint-disable-next-line func-visibility
function ensureValidRole(Role role_) pure {
    bytes32 unwrapped = Role.unwrap(role_);

    for (uint256 i = 0; i < 32; ) {
        bytes1 char = unwrapped[i];
        if ((char < 0x61 || char > 0x7A) && char != 0x5f && char != 0x00) {
            revert InvalidRole(role_); // a-z only
        }
        unchecked {
            i++;
        }
    }
}
