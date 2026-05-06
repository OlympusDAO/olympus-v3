// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

import {Rescuable} from "../../../bases/Rescuable.sol";

/// @notice Harness exposing `Rescuable` with no auth so the parent's logic can be exercised
///         without coupling to a specific permission model.
contract MockRescuable is Rescuable {
    bool public authShouldRevert;

    /// @notice Custom error used by the optional reverting auth path.
    error MockRescuable_Unauthorised();

    function setAuthShouldRevert(bool shouldRevert_) external {
        authShouldRevert = shouldRevert_;
    }

    function _authorizeRescue() internal view override {
        if (authShouldRevert) revert MockRescuable_Unauthorised();
    }

    receive() external payable {}
}

/// @notice Recipient that rejects native transfers, used to exercise the native-transfer
///         failure path in `Rescuable.rescue()`.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no native");
    }
}
