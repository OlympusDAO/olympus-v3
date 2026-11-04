// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";

/// @notice Exposes the desired-state readers of `CCIPConfigLib` as external calls, so that
///         tests can match their reverts with `vm.expectRevert`.
contract CCIPConfigLibHarness {
    function desiredConfig(
        string memory env_,
        string memory chain_
    ) external view returns (CCIPConfigLib.DesiredConfig memory config) {
        return CCIPConfigLib.desiredConfig(env_, chain_);
    }

    function desiredRoutes(
        string memory env_,
        string memory chain_
    ) external view returns (CCIPConfigLib.DesiredRoute[] memory routes) {
        return CCIPConfigLib.desiredRoutes(env_, chain_);
    }

    function desiredPeripheries(
        string memory env_,
        string memory chain_
    ) external view returns (CCIPConfigLib.DesiredPeriphery[] memory peripheries) {
        return CCIPConfigLib.desiredPeripheries(env_, chain_);
    }
}
