// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Kernel
import {Kernel, Actions} from "src/Kernel.sol";

// Interfaces
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice DAO MS batches for the Kernel actions of the YRF v1.2 to v2 migration.
/// @dev The DAO MS holds the kernel executor role, so the Kernel actions are run as batch
///      scripts through the DAO MS; every other step of the migration is performed by
///      the OCG proposal (YieldRepurchaseFacilityV2Proposal) through the
///      YieldRepurchaseFacilityV2Activator.
///
///      Sequence:
///      1. `install` runs before the OCG proposal is queued: the proposal's activator
///         reverts if the policies are not active in the Kernel. The policies are
///         enabler-gated and start disabled, and the Heart calls YRF v1.2, so the
///         activation is inert until the proposal enables the stack.
///      2. `deactivateV1` runs after the OCG proposal has executed: it strips the TRSRY
///         permissions of the shut-down v1.2 policy.
contract YieldRepoV2Install is BatchScriptV2 {
    /// @notice Activates the YRF v2 stack policies in the Kernel.
    function install(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address backingOracle = _envAddressNotZero("olympus.policies.BackingOracle");
        address yrfTimelock = _envAddressNotZero("olympus.policies.YRFTimelock");
        address yieldRepo = _envAddressNotZero("olympus.policies.YieldRepurchaseFacilityV2");

        console2.log("=== Activating the YRF v2 stack ===");

        console2.log("Activating BackingOracle policy:", backingOracle);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                backingOracle
            )
        );

        console2.log("Activating YRFTimelock policy:", yrfTimelock);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                yrfTimelock
            )
        );

        console2.log("Activating YieldRepurchaseFacilityV2 policy:", yieldRepo);
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, yieldRepo)
        );

        console2.log("YRF v2 stack activated");

        proposeBatch();
    }

    /// @notice Deactivates the shut-down YRF v1.2 policy in the Kernel.
    /// @dev Reverts when v1.2 is not shut down. The guard blocks a deactivation of a
    ///      live v1.2: a deactivated policy loses its TRSRY permissions, and the v1.2
    ///      heart beat task reverts on its treasury withdrawals.
    function deactivateV1(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address yieldRepoV1 = _envAddressNotZero("olympus.policies.YieldRepurchaseFacility");

        require(
            IYieldRepo(yieldRepoV1).isShutdown(),
            "YRF v1.2 is not shut down: run this batch after the OCG proposal executes"
        );

        console2.log("=== Deactivating YRF v1.2 ===");

        console2.log("Deactivating YieldRepurchaseFacility v1.2 policy:", yieldRepoV1);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                yieldRepoV1
            )
        );

        console2.log("YRF v1.2 deactivated");

        proposeBatch();
    }
}
