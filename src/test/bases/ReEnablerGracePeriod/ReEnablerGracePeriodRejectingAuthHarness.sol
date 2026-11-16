// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Contracts
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";

/// @notice The test harness whose `_authorizeSetGracePeriod` always reverts with a
///         sentinel selector. The harness is used by the `setGracePeriod` tests to
///         verify that the authorisation hook is invoked before any state mutation and
///         that its revert is propagated to the caller. The other `_authorize*` hooks
///         are stubbed to no-ops so that the underlying `EnablerV2`/`ReEnabler`
///         lifecycle remains drivable from the tests.
contract ReEnablerGracePeriodRejectingAuthHarness is ReEnablerGracePeriod {
    /// @notice The sentinel error emitted by the rejecting `_authorizeSetGracePeriod`.
    error AuthorizeSetGracePeriod_Rejected();

    constructor(uint32 period_) ReEnablerGracePeriod(period_) {}

    function _authorizeEnable(bytes calldata) internal view override {}

    function _authorizeDisable(bytes calldata) internal view override {}

    function _authorizeReEnable() internal view override {}

    function _authorizeSetGracePeriod() internal pure override {
        revert AuthorizeSetGracePeriod_Rejected();
    }
}
