// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Contracts
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";

/// @title ReEnablerGracePeriodImmutable
/// @notice An abstract extension of `ReEnablerGracePeriod` that locks the grace window
///         after construction.
/// @dev `setGracePeriod` always reverts with `GracePeriod_NotConfigurable`. The
///      `_authorizeSetGracePeriod` hook is left abstract so that an inheriting contract
///      that re-opens the setter must define an authorisation rule consciously.
abstract contract ReEnablerGracePeriodImmutable is ReEnablerGracePeriod {
    // ========== INITIALIZATION ========== //

    /// @notice Forwards the initial grace window length to the parent constructor.
    /// @param period_ The grace window length in seconds.
    constructor(uint32 period_) ReEnablerGracePeriod(period_) {}

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @inheritdoc ReEnablerGracePeriod
    function setGracePeriod(uint32) public pure override {
        revert GracePeriod_NotConfigurable();
    }
}
