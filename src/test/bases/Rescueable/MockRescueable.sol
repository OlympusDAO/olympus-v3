// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Rescueable} from "src/bases/Rescueable.sol";

/// @notice Harness exposing `Rescueable` with no auth so the parent's logic can be exercised
///         without coupling to a specific permission model.
contract MockRescueable is Rescueable {
    bool public authShouldRevert;

    /// @notice Custom error used by the optional reverting auth path.
    error MockRescueable_Unauthorized();

    function setAuthShouldRevert(bool shouldRevert_) external {
        authShouldRevert = shouldRevert_;
    }

    function _authorizeRescue() internal view override {
        if (authShouldRevert) revert MockRescueable_Unauthorized();
    }

    receive() external payable {}
}
