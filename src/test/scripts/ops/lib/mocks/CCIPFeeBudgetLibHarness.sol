// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";

/// @notice Exposes the internal functions of `CCIPFeeBudgetLib` as external calls, so that
///         tests can match their reverts with `vm.expectRevert`.
contract CCIPFeeBudgetLibHarness {
    function readOhmDestGasOverhead(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) external view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        return CCIPFeeBudgetLib.readOhmDestGasOverhead(env_, localChain_, remoteChain_);
    }

    function requireOhmFeeBudget(
        string memory env_,
        string memory localChain_,
        string memory remoteChain_
    ) external view {
        CCIPFeeBudgetLib.requireOhmFeeBudget(env_, localChain_, remoteChain_);
    }

    function parseTypeAndVersion(
        string memory raw_
    ) external pure returns (CCIPFeeBudgetLib.TypeAndVersion memory version, bool ok) {
        return CCIPFeeBudgetLib.parseTypeAndVersion(raw_);
    }
}
