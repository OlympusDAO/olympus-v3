// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPQueueLib} from "src/scripts/ops/lib/CCIPQueueLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title CCIPTokenPoolConfigBatch
/// @notice Multisig batches around the CCIPTokenPoolConfig and CCIPTokenPoolConfigTimelock
///         policies. Every entry point is declarative: it reads the live state and adds only the
///         calls that are missing, so a second run on a converged state proposes nothing.
///
///         Entry points:
///         - `prepareHandover` (DAO MS, before the OCG proposal): activate the config policy and
///           the config timelock in the Kernel, propose the config policy as the new pool owner
///           and nominate the OCG timelock as the OHM administrator in the TokenAdminRegistry.
///           Neither transfer is accepted here: the OCG proposal accepts both.
///         - `reEnable` (DAO MS as `bridge_admin`): re-enable the config policy and the config
///           timelock after a disable, while their grace windows are open.
///         - `disableChain` and `disableAllChains` (DAO MS as `bridge_admin`) and their
///           `EmergencyMS` variants (Emergency MS): containment, which writes the disabled rate
///           limiter configuration to one or every route of the pool. Available to the
///           emergency, admin, bridge admin and bridge rate limiter roles, whether or not the
///           config policy is enabled. Containment leaves the queued actions of the config
///           timelock executable; each run lists the unresolved ones.
///         - `disablePolicies` (DAO MS as the local `admin` on a burn/mint chain) and its
///           `EmergencyMS` variant (Emergency MS): disable the config timelock and the config
///           policy, which stops queueing and execution but not transfers; containment stays
///           available. Both owners need `emergency` or `admin`, the gate of `disable()`, which
///           on mainnet the DAO MS does not hold.
///         - `haltAll` (DAO MS as the local `admin` on a burn/mint chain) and its `EmergencyMS`
///           variant (Emergency MS): the full halt, which contains every route and disables both
///           policies in one batch, so that no transfer passes and no queued action executes.
///           Same gate as `disablePolicies`.
///
///         Route configuration runs through `CCIPRouteReconcileBatch` and the config timelock.
contract CCIPTokenPoolConfigBatch is BatchScriptV2 {
    // =========== STATE =========== //

    /// @notice The pool registered for OHM before `prepareHandover`, for the post-batch check.
    address internal _expectedRegisteredPool;

    /// @notice Whether `reEnable` scheduled the config policy re-enable.
    bool internal _expectConfigEnabled;

    /// @notice Whether `reEnable` scheduled the config timelock re-enable.
    bool internal _expectTimelockEnabled;

    /// @notice The chain selectors that a containment batch expects to be contained afterwards.
    uint64[] internal _expectedDisabledSelectors;

    /// @notice The policies that `disablePolicies` expects to be disabled afterwards.
    address[] internal _expectedDisabledPolicies;

    // =========== ENTRY POINTS =========== //

    /// @notice Phase B of the mainnet rollout (DAO MS, before the OCG proposal): activate the
    ///         config policy and the config timelock in the Kernel, propose the config policy as
    ///         the pool owner and nominate the OCG timelock as the OHM administrator.
    /// @dev    Each action is added only when the live state lacks it. The batch does not accept
    ///         the pool ownership or the registry role: the config policy accepts the pool
    ///         through `acceptPoolOwnership` and the OCG timelock calls `acceptAdminRole`, both
    ///         in the OCG proposal.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The chain has no OCG timelock in `env.json` (`olympus.governance.Timelock`).
    ///         - The batch owner is not the Kernel executor.
    ///         - The deployed config policy, timelock and pool are not bound to each other.
    ///         - The pool owner or the OHM administrator is neither the batch owner nor already
    ///           in, or pending, its target state.
    ///         - The registered OHM pool is not the configured pool.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function prepareHandover(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the CCIP contracts, the Kernel policy set and the registry
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address ocgTimelock = _envAddressNotZero("olympus.governance.Timelock");

        console2.log(
            "\n=== Phase B: activate policies and hand the pool and the registry over ==="
        );
        console2.log("Kernel:", kernel);
        console2.log("CCIPTokenPoolConfig:", config);
        console2.log("CCIPTokenPoolConfigTimelock:", timelock);
        console2.log("Token pool:", pool);
        console2.log("TokenAdminRegistry:", registry);
        console2.log("OCG timelock:", ocgTimelock);

        _requireBinding(kernel, config, timelock, pool);

        Kernel kernelContract = Kernel(kernel);
        require(
            kernelContract.executor() == _owner,
            string.concat(
                "CCIPTokenPoolConfigBatch: the batch owner is not the Kernel executor ",
                vm.toString(kernelContract.executor())
            )
        );

        // 1. Activate the policies in the Kernel
        _planActivatePolicy(kernelContract, config, "CCIPTokenPoolConfig");
        _planActivatePolicy(kernelContract, timelock, "CCIPTokenPoolConfigTimelock");

        // 2. Propose the config policy as the pool owner
        _planPoolOwnershipTransfer(pool, config);

        // 3. Nominate the OCG timelock as the OHM administrator
        _planRegistryAdminTransfer(registry, ohm, pool, ocgTimelock);

        _setPostBatchValidateSelector(this._validatePrepareHandover.selector);

        proposeBatch();
    }

    /// @notice Re-enables the config policy and the config timelock after a disable, while
    ///         their grace windows are open (DAO MS as `bridge_admin`).
    /// @dev    A contract that is enabled, that has never been enabled or whose grace window has
    ///         elapsed is reported and skipped: the last two need the admin `enable` path, which
    ///         on mainnet is an OCG proposal. The config policy is re-enabled first so that
    ///         queueing and execution, which require both policies enabled, resume as soon as the
    ///         timelock is re-enabled. Re-enabling restores only the lifecycle flag: route limits
    ///         changed by containment are restored through
    ///         `CCIPRouteReconcileBatch.reconcileRoutes`.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - A re-enable is due and the batch owner does not hold `bridge_admin`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function reEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");

        console2.log(
            "\n=== Re-enable the CCIP config policy and timelock within the grace window ==="
        );

        _expectConfigEnabled = _planReEnable(kernel, config, "CCIPTokenPoolConfig", address(0));
        _expectTimelockEnabled = _planReEnable(
            kernel,
            timelock,
            "CCIPTokenPoolConfigTimelock",
            config
        );

        _setPostBatchValidateSelector(this._validateReEnable.selector);

        proposeBatch();
    }

    /// @notice Contains one route: writes the disabled rate limiter configuration to both of its
    ///         buckets (DAO MS as `bridge_admin`, or any holder of a containment role as owner).
    /// @dev    `disableChainEmergencyMS` is the same batch with the Emergency MS as owner.
    ///         Not gated on the config policy being enabled. Skipped when the route is already
    ///         contained. Restoring the approved limits afterwards is a declarative change:
    ///         `CCIPRouteReconcileBatch.reconcileRoutes` queues `setChainRateLimits` from
    ///         `env.json` for a route named in its `restoreContained` args. Messages that trip
    ///         the contained inbound bucket fail on this chain and need manual execution after
    ///         the limits are restored.
    ///
    ///         Containment does not stop a queued action of the config timelock: a matured one
    ///         executes permissionlessly while both policies are enabled, and an `addChain`
    ///         opens a route with the limits it carries. The run lists the unresolved queue and
    ///         points at `haltAll`, which disables both policies with the containment, and at
    ///         the cancellation entry points of `CCIPRouteReconcileBatch`.
    ///
    ///         Args file: `{"functions": [{"name": "disableChain", "args": {"remoteChain": "solana"}}]}`.
    ///
    ///         Reverts if:
    ///         - The route is not configured on the pool.
    ///         - The batch owner holds none of the emergency, admin, bridge admin and bridge
    ///           rate limiter roles.
    ///         - The config policy is neither the owner nor the rate limit admin of the pool
    ///           (before the handover, containment belongs to the pool owner through
    ///           `CCIPTokenPoolBatch.emergencyShutdown`).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "disableChain.remoteChain").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disableChain(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _planContainChain("disableChain");
        proposeBatch();
    }

    /// @notice Contains one route with the Emergency MS as owner.
    /// @dev    Same behaviour and args file as `disableChain`, under the function name
    ///         `disableChainEmergencyMS`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "disableChainEmergencyMS.remoteChain").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disableChainEmergencyMS(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _planContainChain("disableChainEmergencyMS");
        proposeBatch();
    }

    /// @notice Plans the containment of one route, reading `remoteChain` from the args entry of
    ///         `functionName_`.
    function _planContainChain(string memory functionName_) internal {
        _skipHeartbeatValidation = true;

        string memory remoteChain = _readBatchArgString(functionName_, "remoteChain");
        uint64 chainSelector = CCIPConfigLib.chainSelector(env, remoteChain);
        (address config, address pool) = _containmentAddresses();

        console2.log("\n=== Containment: disable route", remoteChain, "===");
        console2.log("Chain selector:", chainSelector);

        require(
            ICCIPTokenPoolAdmin(pool).isSupportedChain(chainSelector),
            "CCIPTokenPoolConfigBatch: the route is not configured on the pool"
        );

        if (ICCIPTokenPoolConfig(config).isChainDisabled(chainSelector)) {
            console2.log("Route is already contained. Skipping.");
        } else {
            addToBatch(
                config,
                abi.encodeWithSelector(ICCIPTokenPoolConfig.disableChain.selector, chainSelector)
            );
            console2.log("Added: CCIPTokenPoolConfig.disableChain");
        }
        _expectedDisabledSelectors.push(chainSelector);
        _logContainmentQueue(config);

        _setPostBatchValidateSelector(this._validateDisabled.selector);
    }

    /// @notice Contains every configured route of the pool (DAO MS as `bridge_admin`, or any
    ///         holder of a containment role as owner).
    /// @dev    `disableAllChainsEmergencyMS` is the same batch with the Emergency MS as owner.
    ///         Not gated on the config policy being enabled. Skipped when every route is already
    ///         contained, and when no route is configured, which the config policy would reject
    ///         (`CCIPTokenPoolConfig_NoRoutesConfigured`). See `disableChain` for the recovery
    ///         and for the queued actions that containment does not stop.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner holds none of the emergency, admin, bridge admin and bridge
    ///           rate limiter roles.
    ///         - The config policy is neither the owner nor the rate limit admin of the pool
    ///           (before the handover, containment belongs to the pool owner through
    ///           `CCIPTokenPoolBatch.emergencyShutdownAll`).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disableAllChains(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _planContainAllChains(false);
        proposeBatch();
    }

    /// @notice Contains every configured route with the Emergency MS as owner.
    /// @dev    Same behaviour as `disableAllChains`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disableAllChainsEmergencyMS(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFile_);
        _planContainAllChains(false);
        proposeBatch();
    }

    /// @notice Plans the containment of every configured route.
    /// @param  halting_ Whether the batch also disables both policies (`haltAll`), in which
    ///         case the queue is listed by the halt rather than here.
    function _planContainAllChains(bool halting_) internal {
        _skipHeartbeatValidation = true;

        (address config, address pool) = _containmentAddresses();
        uint64[] memory selectors = ICCIPTokenPoolAdmin(pool).getSupportedChains();

        console2.log("\n=== Containment: disable all routes ===");
        console2.log("Configured routes:", selectors.length);

        bool anyOpen = false;
        for (uint256 i = 0; i < selectors.length; ++i) {
            bool disabled = ICCIPTokenPoolConfig(config).isChainDisabled(selectors[i]);
            console2.log("  Route", selectors[i], disabled ? "contained" : "open");
            if (!disabled) anyOpen = true;
            _expectedDisabledSelectors.push(selectors[i]);
        }

        if (selectors.length == 0) {
            console2.log("No route is configured. Nothing to do.");
        } else if (!anyOpen) {
            console2.log("Every route is already contained. Skipping.");
        } else {
            addToBatch(
                config,
                abi.encodeWithSelector(ICCIPTokenPoolConfig.disableAllChains.selector)
            );
            console2.log("Added: CCIPTokenPoolConfig.disableAllChains");
        }
        if (!halting_) _logContainmentQueue(config);

        _setPostBatchValidateSelector(this._validateDisabled.selector);
    }

    /// @notice Disables the config timelock and the config policy (DAO MS as the local `admin`
    ///         on a burn/mint chain, or any `emergency` or `admin` holder as owner).
    /// @dev    `disablePoliciesEmergencyMS` is the same batch with the Emergency MS as owner.
    ///         The DAO MS owner serves the burn/mint chains, where it holds the local `admin`
    ///         role; on mainnet it holds neither `emergency` nor `admin`, so the freeze there is
    ///         the Emergency MS variant or an OCG proposal.
    ///
    ///         Freezes the control plane: queueing and execution stop, queued actions are kept
    ///         and may expire, and containment stays available. Transfers are not stopped; use
    ///         `disableChain` or `disableAllChains` for that. A policy that is already disabled
    ///         is skipped. Recovery is `reEnable` within the grace window, or the admin `enable`
    ///         path afterwards.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disablePolicies(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _planDisablePolicies("disablePoliciesEmergencyMS");
        proposeBatch();
    }

    /// @notice Disables the config timelock and the config policy with the Emergency MS as owner.
    /// @dev    Same behaviour as `disablePolicies`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function disablePoliciesEmergencyMS(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFile_);
        _planDisablePolicies("disablePoliciesEmergencyMS");
        proposeBatch();
    }

    /// @notice Plans the disable of the config timelock and the config policy.
    /// @param  emergencyEntry_ The Emergency MS entry point named by the gate message.
    function _planDisablePolicies(string memory emergencyEntry_) internal {
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        _requireDisableAuthority(kernel, emergencyEntry_);

        console2.log("\n=== Disable the CCIP config timelock and config policy ===");
        _planDisable(timelock, "CCIPTokenPoolConfigTimelock");
        _planDisable(config, "CCIPTokenPoolConfig");

        _setPostBatchValidateSelector(this._validateDisabledPolicies.selector);
    }

    /// @notice Halts the bridge in one batch (DAO MS as the local `admin` on a burn/mint chain,
    ///         or any `emergency` or `admin` holder as owner): contains every configured route
    ///         and disables the config timelock and the config policy, so that no transfer
    ///         passes and no queued action, matured or not, executes.
    /// @dev    `haltAllEmergencyMS` is the same batch with the Emergency MS as owner. On mainnet
    ///         the DAO MS holds neither `emergency` nor `admin`, so the halt there is the
    ///         Emergency MS variant or an OCG proposal. The containment is planned as in
    ///         `disableAllChains` and the disables as in `disablePolicies`, with the same skips:
    ///         a contained route, a disabled policy and an empty pool add nothing. The queued
    ///         actions of the timelock are kept and may expire while the policies are disabled;
    ///         the run lists the unresolved ones.
    ///
    ///         Recovery: cancel the queued actions that must not survive
    ///         (`CCIPRouteReconcileBatch.cancelQueuedAction` or `cancelQueuedActionEmergency`),
    ///         `reEnable` both policies within the grace window (the admin `enable` path
    ///         afterwards), then restore the limits through
    ///         `CCIPRouteReconcileBatch.reconcileRoutes` with every route named in its
    ///         `restoreContained` args.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner holds neither `emergency` nor `admin`.
    ///         - The config policy is neither the owner nor the rate limit admin of the pool
    ///           (before the handover, containment belongs to the pool owner through
    ///           `CCIPTokenPoolBatch.emergencyShutdownAll`).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function haltAll(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _planHaltAll();
        proposeBatch();
    }

    /// @notice Halts the bridge in one batch with the Emergency MS as owner.
    /// @dev    Same behaviour as `haltAll`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function haltAllEmergencyMS(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFile_);
        _planHaltAll();
        proposeBatch();
    }

    /// @notice Plans the full halt: the containment of every route, then the disable of the
    ///         config timelock and the config policy.
    function _planHaltAll() internal {
        _skipHeartbeatValidation = true;

        // The disable gate is checked before anything is planned, so that an owner without it
        // is refused with the halt's own message
        _requireDisableAuthority(_envAddressNotZero("olympus.Kernel"), "haltAllEmergencyMS");

        console2.log("\n=== Full halt: contain every route and disable both policies ===");
        _planContainAllChains(true);
        _planDisablePolicies("haltAllEmergencyMS");
        _logUnresolvedQueue(true);

        // The halt validator replaces the ones the two planning helpers set
        _setPostBatchValidateSelector(this._validateHalted.selector);
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `disablePolicies`.
    function _validateDisabledPolicies() external view {
        console2.log("\nValidating disablePolicies post-batch state");
        for (uint256 i = 0; i < _expectedDisabledPolicies.length; ++i) {
            require(
                !IEnabler(_expectedDisabledPolicies[i]).isEnabled(),
                string.concat(
                    "Policy ",
                    vm.toString(_expectedDisabledPolicies[i]),
                    " is still enabled"
                )
            );
            console2.log("  Policy", _expectedDisabledPolicies[i], "is disabled");
        }
        console2.log("disablePolicies post-batch validation passed");
    }

    /// @notice Validates the state after `prepareHandover`.
    function _validatePrepareHandover() external view {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address ocgTimelock = _envAddressNotZero("olympus.governance.Timelock");

        console2.log("\nValidating prepareHandover post-batch state");

        require(
            Kernel(kernel).isPolicyActive(Policy(config)),
            "CCIPTokenPoolConfig is not active in the Kernel"
        );
        require(
            Kernel(kernel).isPolicyActive(Policy(timelock)),
            "CCIPTokenPoolConfigTimelock is not active in the Kernel"
        );
        console2.log("  Both policies are active in the Kernel");

        address poolOwner = ICCIPTokenPoolAdmin(pool).owner();
        require(
            poolOwner == config || _pendingOwner(pool) == config,
            "CCIPTokenPoolConfig is neither the owner nor the pending owner of the pool"
        );
        console2.log("  Pool owner:", poolOwner, "pending owner:", _pendingOwner(pool));

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry)
            .getTokenConfig(ohm);
        require(
            tokenConfig.administrator == ocgTimelock ||
                tokenConfig.pendingAdministrator == ocgTimelock,
            "The OCG timelock is neither the OHM administrator nor the pending administrator"
        );
        require(
            tokenConfig.tokenPool == _expectedRegisteredPool,
            "The registered OHM pool changed"
        );
        console2.log(
            "  OHM administrator:",
            tokenConfig.administrator,
            "pending:",
            tokenConfig.pendingAdministrator
        );
        console2.log("  Registered OHM pool:", tokenConfig.tokenPool);

        console2.log("prepareHandover post-batch validation passed");
    }

    /// @notice Validates the state after `reEnable`.
    function _validateReEnable() external view {
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");

        console2.log("\nValidating reEnable post-batch state");
        if (_expectConfigEnabled) {
            require(IEnabler(config).isEnabled(), "CCIPTokenPoolConfig is not enabled");
            console2.log("  CCIPTokenPoolConfig is enabled");
        }
        if (_expectTimelockEnabled) {
            require(IEnabler(timelock).isEnabled(), "CCIPTokenPoolConfigTimelock is not enabled");
            console2.log("  CCIPTokenPoolConfigTimelock is enabled");
        }
        console2.log("reEnable post-batch validation passed");
    }

    /// @notice Validates the state after `disableChain` or `disableAllChains`.
    function _validateDisabled() external view {
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");

        console2.log("\nValidating containment post-batch state");
        for (uint256 i = 0; i < _expectedDisabledSelectors.length; ++i) {
            uint64 selector = _expectedDisabledSelectors[i];
            require(
                ICCIPTokenPoolConfig(config).isChainDisabled(selector),
                string.concat("Route ", vm.toString(selector), " is not contained")
            );
            console2.log("  Route", selector, "is contained");
        }
        console2.log("Containment post-batch validation passed");
    }

    /// @notice Validates the state after `haltAll`: every configured route of the pool is
    ///         contained and both policies are disabled.
    function _validateHalted() external view {
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));

        console2.log("\nValidating haltAll post-batch state");
        uint64[] memory selectors = ICCIPTokenPoolAdmin(pool).getSupportedChains();
        for (uint256 i = 0; i < selectors.length; ++i) {
            require(
                ICCIPTokenPoolConfig(config).isChainDisabled(selectors[i]),
                string.concat("Route ", vm.toString(selectors[i]), " is not contained")
            );
            console2.log("  Route", selectors[i], "is contained");
        }
        require(!IEnabler(timelock).isEnabled(), "CCIPTokenPoolConfigTimelock is still enabled");
        require(!IEnabler(config).isEnabled(), "CCIPTokenPoolConfig is still enabled");
        console2.log("  Both policies are disabled");
        console2.log("haltAll post-batch validation passed");
    }

    // =========== PLANNING HELPERS =========== //

    function _planActivatePolicy(Kernel kernel_, address policy_, string memory name_) internal {
        if (kernel_.isPolicyActive(Policy(policy_))) {
            console2.log(name_, "is already active in the Kernel. Skipping.");
            return;
        }

        addToBatch(
            address(kernel_),
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, policy_)
        );
        console2.log("Added: Kernel.executeAction(ActivatePolicy,", name_, ")");
    }

    function _planPoolOwnershipTransfer(address pool_, address config_) internal {
        address owner = ICCIPTokenPoolAdmin(pool_).owner();
        address pending = _pendingOwner(pool_);
        console2.log("Pool owner:", owner, "pending owner:", pending);

        if (owner == config_) {
            console2.log("CCIPTokenPoolConfig already owns the pool. Skipping.");
            return;
        }
        if (pending == config_) {
            console2.log("CCIPTokenPoolConfig is already the pending owner of the pool. Skipping.");
            return;
        }
        require(
            owner == _owner,
            string.concat(
                "CCIPTokenPoolConfigBatch: unexpected pool owner ",
                vm.toString(owner),
                "; the batch owner must own the pool to propose CCIPTokenPoolConfig"
            )
        );

        addToBatch(
            pool_,
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.transferOwnership.selector, config_)
        );
        console2.log("Added: pool.transferOwnership(CCIPTokenPoolConfig)");
    }

    function _planRegistryAdminTransfer(
        address registry_,
        address ohm_,
        address pool_,
        address ocgTimelock_
    ) internal {
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry_)
            .getTokenConfig(ohm_);
        console2.log(
            "OHM administrator:",
            tokenConfig.administrator,
            "pending:",
            tokenConfig.pendingAdministrator
        );
        console2.log("Registered OHM pool:", tokenConfig.tokenPool);
        require(
            tokenConfig.tokenPool == pool_,
            "CCIPTokenPoolConfigBatch: the registered OHM pool is not the configured pool"
        );
        _expectedRegisteredPool = tokenConfig.tokenPool;

        if (tokenConfig.administrator == ocgTimelock_) {
            console2.log("The OCG timelock is already the OHM administrator. Skipping.");
            return;
        }
        if (tokenConfig.pendingAdministrator == ocgTimelock_) {
            console2.log("The OCG timelock is already the pending OHM administrator. Skipping.");
            return;
        }
        require(
            tokenConfig.administrator == _owner,
            string.concat(
                "CCIPTokenPoolConfigBatch: unexpected OHM administrator ",
                vm.toString(tokenConfig.administrator),
                "; the batch owner must be the administrator to nominate the OCG timelock"
            )
        );

        addToBatch(
            registry_,
            abi.encodeWithSelector(
                ICCIPTokenAdminRegistry.transferAdminRole.selector,
                ohm_,
                ocgTimelock_
            )
        );
        console2.log("Added: TokenAdminRegistry.transferAdminRole(OHM, OCG timelock)");
    }

    function _planDisable(address target_, string memory name_) internal {
        if (!IEnabler(target_).isEnabled()) {
            console2.log(name_, "is already disabled. Skipping.");
            return;
        }
        addToBatch(target_, abi.encodeWithSelector(IEnabler.disable.selector, ""));
        _expectedDisabledPolicies.push(target_);
        console2.log("Added:", name_, "disable()");
    }

    /// @param  requiredActivePolicy_ A policy that must be active in the Kernel for the
    ///         re-enable to succeed (the config policy for the timelock), or the zero address.
    /// @return scheduled True if a re-enable was added to the batch.
    function _planReEnable(
        address kernel_,
        address target_,
        string memory name_,
        address requiredActivePolicy_
    ) internal returns (bool scheduled) {
        console2.log("\n", name_, target_);
        if (IEnabler(target_).isEnabled()) {
            console2.log("  Enabled. Nothing to do.");
            return false;
        }
        require(
            requiredActivePolicy_ == address(0) ||
                Kernel(kernel_).isPolicyActive(Policy(requiredActivePolicy_)),
            string.concat(
                "CCIPTokenPoolConfigBatch: ",
                name_,
                " cannot be re-enabled while the config policy is not active in the Kernel"
            )
        );

        uint48 lastTransitionAt = IEnablerV2(target_).lastTransitionAt();
        if (lastTransitionAt == 0) {
            console2.log(
                "  Never enabled: the admin role must call enable (OCG proposal on mainnet)."
            );
            return false;
        }

        uint256 deadline = uint256(lastTransitionAt) + IGracePeriod(target_).gracePeriod();
        console2.log("  Disabled at", lastTransitionAt, "grace deadline", deadline);
        // The grace deadline is read by the script at simulation time
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) {
            console2.log(
                "  Grace window elapsed: the admin role must call enable (OCG proposal on mainnet)."
            );
            return false;
        }

        require(
            _roles(kernel_).hasRole(_owner, BRIDGE_ADMIN_ROLE),
            "CCIPTokenPoolConfigBatch: the batch owner does not hold bridge_admin"
        );

        addToBatch(target_, abi.encodeWithSelector(IReEnabler.reEnable.selector));
        console2.log("  Added: reEnable()");
        return true;
    }

    // =========== INTERNAL HELPERS =========== //

    /// @notice Reverts unless the batch owner holds `emergency` or `admin`, the gate of
    ///         `disable()` on both policies.
    function _requireDisableAuthority(
        address kernel_,
        string memory emergencyEntry_
    ) internal view {
        ROLESv1 roles = _roles(kernel_);
        require(
            roles.hasRole(_owner, EMERGENCY_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            string.concat(
                "CCIPTokenPoolConfigBatch: the batch owner holds neither emergency nor admin; the DAO MS holds admin on the burn/mint chains only, so on mainnet use ",
                emergencyEntry_,
                " or an OCG proposal"
            )
        );
    }

    /// @notice Lists the unresolved queued actions after a containment plan, with the sentence
    ///         that fits the live lifecycle state of the two policies.
    function _logContainmentQueue(address config_) internal view {
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        _logUnresolvedQueue(!IEnabler(config_).isEnabled() || !IEnabler(timelock).isEnabled());
    }

    /// @notice Lists the unresolved queued actions of the config timelock. Containment does not
    ///         stop them: a matured action executes permissionlessly while both policies are
    ///         enabled, and an `addChain` opens a route with the limits it carries.
    /// @param  executionBlocked_ Whether a policy is, or is left by this batch, disabled, which
    ///         blocks the execution until both are enabled again.
    function _logUnresolvedQueue(bool executionBlocked_) internal view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );
        uint64[] memory ids = CCIPQueueLib.unresolvedActionIds(timelock);
        console2.log("\n--- Unresolved queued actions on the config timelock:", ids.length, "---");
        if (ids.length == 0) return;
        console2.log(
            executionBlocked_
                ? "Their execution is blocked while a policy is disabled. Before reEnable, cancel the ones that must not survive (CCIPRouteReconcileBatch.cancelQueuedAction or cancelQueuedActionEmergency); an action whose window closes meanwhile expires and must be cancelled and queued again."
                : "WARNING: containment does not stop them. A matured action executes permissionlessly while both policies are enabled, and an addChain opens a route with the limits it carries. Disable both policies together with the containment through haltAll or haltAllEmergencyMS, or cancel them (CCIPRouteReconcileBatch.cancelQueuedAction or cancelQueuedActionEmergency)."
        );
        // The queue timestamps are read by the script at simulation time
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i < ids.length; ++i) {
            CCIPQueueLib.logAction(ids[i], timelock.getQueuedAction(ids[i]), timestamp);
        }
    }

    function _containmentAddresses() internal view returns (address config, address pool) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        require(
            ICCIPTokenPoolConfig(config).pool() == pool,
            "CCIPTokenPoolConfigBatch: the config policy is bound to another pool"
        );
        require(
            ICCIPTokenPoolAdmin(pool).owner() == config ||
                ICCIPTokenPoolAdmin(pool).getRateLimitAdmin() == config,
            "CCIPTokenPoolConfigBatch: the config policy is neither the owner nor the rate limit admin of the pool, so it cannot write the rate limits; before the handover use CCIPTokenPoolBatch.emergencyShutdown or emergencyShutdownAll from the pool owner"
        );
        ROLESv1 roles = _roles(kernel);
        require(
            roles.hasRole(_owner, EMERGENCY_ROLE) ||
                roles.hasRole(_owner, ADMIN_ROLE) ||
                roles.hasRole(_owner, BRIDGE_ADMIN_ROLE) ||
                roles.hasRole(_owner, BRIDGE_RATE_LIMITER_ROLE),
            "CCIPTokenPoolConfigBatch: the batch owner holds none of the emergency, admin, bridge admin and bridge rate limiter roles"
        );
    }

    /// @notice Reverts unless the config policy, the timelock and the pool are bound together.
    function _requireBinding(
        address kernel_,
        address config_,
        address timelock_,
        address pool_
    ) internal view {
        require(
            ICCIPTokenPoolConfig(config_).pool() == pool_,
            "CCIPTokenPoolConfigBatch: the config policy is bound to another pool"
        );
        require(
            ICCIPTokenPoolConfigTimelock(timelock_).config() == config_,
            "CCIPTokenPoolConfigBatch: the timelock is bound to another config policy"
        );
        require(
            address(Policy(config_).kernel()) == kernel_,
            "CCIPTokenPoolConfigBatch: the config policy reports another Kernel"
        );
        if (ChainUtils._isCanonicalChain(chain)) {
            require(
                ICCIPTokenPoolConfig(config_).isLiquidityContainer(),
                "CCIPTokenPoolConfigBatch: the canonical pool is not a liquidity container"
            );
        }
    }

    function _pendingOwner(address pool_) internal view returns (address pending) {
        return CCIPConfigLib.pendingOwner(pool_);
    }

    function _roles(address kernel_) internal view returns (ROLESv1 roles) {
        return ROLESv1(address(Kernel(kernel_).getModuleForKeycode(toKeycode("ROLES"))));
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
