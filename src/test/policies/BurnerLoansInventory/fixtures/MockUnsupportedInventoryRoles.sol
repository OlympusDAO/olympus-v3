// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

// Contracts

import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Scenario-specific contracts and fixtures have no cross-file consumers.

contract MockUnsupportedInventoryRoles is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
