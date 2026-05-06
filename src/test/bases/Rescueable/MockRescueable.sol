// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

import {Rescueable} from "../../../bases/Rescueable.sol";

/// @notice Harness exposing `Rescueable` with no auth so the parent's logic can be exercised
///         without coupling to a specific permission model.
contract MockRescueable is Rescueable {
    bool public authShouldRevert;

    /// @notice Custom error used by the optional reverting auth path.
    error MockRescueable_Unauthorised();

    function setAuthShouldRevert(bool shouldRevert_) external {
        authShouldRevert = shouldRevert_;
    }

    function _authorizeRescue() internal view override {
        if (authShouldRevert) revert MockRescueable_Unauthorised();
    }

    receive() external payable {}
}

/// @notice Recipient that rejects native transfers, used to exercise the native-transfer
///         failure path in `Rescueable.rescue()`.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no native");
    }
}
