// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";

/// @notice Exposes the readers of `BackingOracleConfigLib` as external calls, so that tests can
///         match their reverts with `vm.expectRevert`.
contract BackingOracleConfigLibHarness {
    function desiredBacking(
        string memory env_,
        string memory chain_
    ) external view returns (uint256 backing) {
        return BackingOracleConfigLib.desiredBacking(env_, chain_);
    }

    function backingPath(string memory chain_) external pure returns (string memory path) {
        return BackingOracleConfigLib.backingPath(chain_);
    }
}
