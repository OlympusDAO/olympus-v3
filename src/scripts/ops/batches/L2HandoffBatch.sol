// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Libraries
import {console2} from "@forge-std-1.16.2/console2.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";

// Contracts
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Accepts the initial L2 administration and pool ownership from the DAO Safe.
contract L2HandoffBatch is BatchScriptV2 {
    error L2HandoffBatch_NotDao();
    error L2HandoffBatch_UnexpectedPendingAdmin();
    error L2HandoffBatch_UnexpectedPendingPoolOwner();
    error L2HandoffBatch_IncompleteAcceptance();

    /// @notice Simulates both acceptance calls and optionally signs and proposes the Safe batch.
    /// @dev Already accepted transfers are skipped. No Heart is deployed with the L2 core.
    function acceptHandoff(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        if (_owner != _envAddressNotZero("olympus.multisig.dao")) revert L2HandoffBatch_NotDao();
        _skipHeartbeatValidation = true;
        console2.log("=== Planning L2 DAO handoff acceptance ===");
        console2.log("Chain:", chain);
        console2.log("DAO Safe accepting ownership:", _owner);
        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        console2.log("RolesAdmin:", address(rolesAdmin));
        console2.log("Current administrator:", rolesAdmin.admin());
        console2.log("Pending administrator:", rolesAdmin.newAdmin());
        if (rolesAdmin.admin() != _owner) {
            if (rolesAdmin.newAdmin() != _owner) revert L2HandoffBatch_UnexpectedPendingAdmin();
            console2.log("Adding RolesAdmin.pullNewAdmin() to the batch");
            addToBatch(address(rolesAdmin), abi.encodeCall(RolesAdmin.pullNewAdmin, ()));
        } else {
            console2.log("Skipping RolesAdmin acceptance: DAO Safe is already administrator");
        }

        address pool = _envAddress("olympus.policies.CCIPBurnMintTokenPool");
        console2.log("TokenPool:", pool);
        if (pool != address(0)) {
            console2.log("Current pool owner:", ICCIPTokenPoolAdmin(pool).owner());
            console2.log("Pending pool owner:", CCIPConfigLib.pendingOwner(pool));
        }
        if (pool != address(0) && ICCIPTokenPoolAdmin(pool).owner() != _owner) {
            if (CCIPConfigLib.pendingOwner(pool) != _owner)
                revert L2HandoffBatch_UnexpectedPendingPoolOwner();
            console2.log("Adding TokenPool.acceptOwnership() to the batch");
            addToBatch(pool, abi.encodeCall(ICCIPTokenPoolAdmin.acceptOwnership, ()));
        } else if (pool == address(0)) {
            console2.log("Skipping TokenPool acceptance: no pool recorded in env.json");
        } else {
            console2.log("Skipping TokenPool acceptance: DAO Safe is already owner");
        }

        console2.log("Acceptance calls in batch:", _batchTargets.length);
        if (_batchTargets.length == 0) {
            validateAcceptance();
            console2.log("DAO handoff already accepted; no proposal needed.");
            return;
        }
        _setPostBatchValidateSelector(this.validateAcceptance.selector);
        console2.log("Simulating acceptance calls and checking the resulting ownership");
        console2.log(
            "Broadcast mode signs and proposes the batch; DAO Safe execution is still required"
        );
        proposeBatch();
        console2.log("Simulation checks the proposed state. Safe execution completes the handoff.");
    }

    /// @notice Checks the accepted ownership during batch simulation, before any proposal is sent.
    function validateAcceptance() public view {
        console2.log("=== Checking DAO handoff acceptance ===");
        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        console2.log("Resulting RolesAdmin administrator:", rolesAdmin.admin());
        console2.log("Resulting pending administrator:", rolesAdmin.newAdmin());
        if (rolesAdmin.admin() != _owner || rolesAdmin.newAdmin() != address(0))
            revert L2HandoffBatch_IncompleteAcceptance();
        console2.log("[PASS] RolesAdmin administration accepted by DAO Safe");

        address pool = _envAddress("olympus.policies.CCIPBurnMintTokenPool");
        if (pool != address(0)) {
            console2.log("Resulting pool owner:", ICCIPTokenPoolAdmin(pool).owner());
            console2.log("Resulting pending pool owner:", CCIPConfigLib.pendingOwner(pool));
            if (
                ICCIPTokenPoolAdmin(pool).owner() != _owner ||
                CCIPConfigLib.pendingOwner(pool) != address(0)
            ) revert L2HandoffBatch_IncompleteAcceptance();
            console2.log("[PASS] TokenPool ownership accepted by DAO Safe");
        }
    }
}
