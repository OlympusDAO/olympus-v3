// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Contracts
import {ReEnablerGracePeriodImmutable} from "src/bases/ReEnablerGracePeriodImmutable.sol";

/// @notice The test harness for `ReEnablerGracePeriodImmutable`. Every `_authorize*`
///         hook is stubbed to a no-op so that the tests can drive the lifecycle freely.
contract ReEnablerGracePeriodImmutableHarness is ReEnablerGracePeriodImmutable {
    constructor(uint32 period_) ReEnablerGracePeriodImmutable(period_) {}

    function _authorizeEnable(bytes calldata) internal view override {}

    function _authorizeDisable(bytes calldata) internal view override {}

    function _authorizeReEnable() internal view override {}

    function _authorizeSetGracePeriod() internal view override {}
}
