// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Contracts
import {EnablerV2GracePeriod} from "src/libraries/EnablerV2GracePeriod.sol";

/// @notice Test harness exposing `_requireGrace` of `EnablerV2GracePeriod` as
///         an external pass-through. The `_authorizeEnable` and
///         `_authorizeDisable` hooks are stubbed to no-ops so that tests can
///         drive the underlying `EnablerV2` lifecycle without external
///         authorization plumbing.
contract EnablerV2GracePeriodHarness is EnablerV2GracePeriod {
    constructor(uint32 p_) EnablerV2GracePeriod(p_) {}

    function _authorizeEnable(bytes calldata) internal override {}

    function _authorizeDisable(bytes calldata) internal override {}

    /// @notice External pass-through to `_requireGrace`.
    function requireGrace() external view {
        _requireGrace();
    }
}
