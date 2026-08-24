// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity ^0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title CCIPBridgeConfigBatch
/// @notice Multisig batches around the CCIPBridgeConfig and CCIPBridgeConfigTimelock policies.
///         Every entry point is declarative: it reads the live state and adds only the calls
///         that are missing, so a second run on a converged state proposes nothing.
///
///         Entry points:
///         - `prepareHandover` (DAO MS, before the OCG proposal): activate the config policy and
///           the config timelock in the Kernel, propose the config policy as the new pool owner
///           and nominate the OCG timelock as the OHM administrator in the TokenAdminRegistry.
///           Neither transfer is accepted here: the OCG proposal accepts both.
///         - `reEnable` (DAO MS as `bridge_admin`): re-enable the config policy and the config
///           timelock after a disable, while their grace windows are open.
///         - `disableChain` and `disableAllChains` (Emergency MS): containment, which writes the
///           disabled rate limiter configuration to one or every route of the pool. Available
///           whether or not the config policy is enabled.
///         - `disablePolicies` (Emergency MS): disable the config timelock and the config policy,
///           which stops queueing and execution but not transfers; containment stays available.
///
///         Route configuration runs through `CCIPRouteReconcileBatch` and the config timelock.
contract CCIPBridgeConfigBatch is BatchScriptV2 {
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
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address ocgTimelock = _envAddressNotZero("olympus.governance.Timelock");

        console2.log(
            "\n=== Phase B: activate policies and hand the pool and the registry over ==="
        );
        console2.log("Kernel:", kernel);
        console2.log("CCIPBridgeConfig:", config);
        console2.log("CCIPBridgeConfigTimelock:", timelock);
        console2.log("Token pool:", pool);
        console2.log("TokenAdminRegistry:", registry);
        console2.log("OCG timelock:", ocgTimelock);

        _requireBinding(kernel, config, timelock, pool);

        Kernel kernelContract = Kernel(kernel);
        require(
            kernelContract.executor() == _owner,
            string.concat(
                "CCIPBridgeConfigBatch: the batch owner is not the Kernel executor ",
                vm.toString(kernelContract.executor())
            )
        );

        // 1. Activate the policies in the Kernel
        _planActivatePolicy(kernelContract, config, "CCIPBridgeConfig");
        _planActivatePolicy(kernelContract, timelock, "CCIPBridgeConfigTimelock");

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
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");

        console2.log(
            "\n=== Re-enable the CCIP config policy and timelock within the grace window ==="
        );

        _expectConfigEnabled = _planReEnable(kernel, config, "CCIPBridgeConfig", address(0));
        _expectTimelockEnabled = _planReEnable(
            kernel,
            timelock,
            "CCIPBridgeConfigTimelock",
            config
        );

        _setPostBatchValidateSelector(this._validateReEnable.selector);

        proposeBatch();
    }

    /// @notice Contains one route: writes the disabled rate limiter configuration to both of its
    ///         buckets (Emergency MS, or any `emergency` or `admin` holder as owner).
    /// @dev    Not gated on the config policy being enabled. Skipped when the route is already
    ///         contained. Restoring the approved limits afterwards is a declarative change:
    ///         `CCIPRouteReconcileBatch.reconcileRoutes` queues `setChainRateLimits` from
    ///         `env.json`. Messages that trip the contained inbound bucket fail on this chain and
    ///         need manual execution after the limits are restored.
    ///
    ///         Args file: `{"functions": [{"name": "disableChain", "args": {"remoteChain": "solana"}}]}`.
    ///
    ///         Reverts if:
    ///         - The route is not configured on the pool.
    ///         - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
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
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _skipHeartbeatValidation = true;

        string memory remoteChain = _readBatchArgString("disableChain", "remoteChain");
        uint64 chainSelector = CCIPConfigLib.chainSelector(env, remoteChain);
        (address config, address pool) = _containmentAddresses();

        console2.log("\n=== Containment: disable route", remoteChain, "===");
        console2.log("Chain selector:", chainSelector);

        require(
            ICCIPTokenPoolAdmin(pool).isSupportedChain(chainSelector),
            "CCIPBridgeConfigBatch: the route is not configured on the pool"
        );

        if (ICCIPBridgeConfig(config).isChainDisabled(chainSelector)) {
            console2.log("Route is already contained. Skipping.");
        } else {
            addToBatch(
                config,
                abi.encodeWithSelector(ICCIPBridgeConfig.disableChain.selector, chainSelector)
            );
            console2.log("Added: CCIPBridgeConfig.disableChain");
        }
        _expectedDisabledSelectors.push(chainSelector);

        _setPostBatchValidateSelector(this._validateDisabled.selector);

        proposeBatch();
    }

    /// @notice Contains every configured route of the pool (Emergency MS, or any `emergency` or
    ///         `admin` holder as owner).
    /// @dev    Not gated on the config policy being enabled. Skipped when every route is already
    ///         contained or when no route is configured. See `disableChain` for the recovery.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
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
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        (address config, address pool) = _containmentAddresses();
        uint64[] memory selectors = ICCIPTokenPoolAdmin(pool).getSupportedChains();

        console2.log("\n=== Containment: disable all routes ===");
        console2.log("Configured routes:", selectors.length);

        bool anyOpen;
        for (uint256 i; i < selectors.length; ++i) {
            bool disabled = ICCIPBridgeConfig(config).isChainDisabled(selectors[i]);
            console2.log("  Route", selectors[i], disabled ? "contained" : "open");
            if (!disabled) anyOpen = true;
            _expectedDisabledSelectors.push(selectors[i]);
        }

        if (selectors.length == 0) {
            console2.log("No route is configured. Nothing to do.");
        } else if (!anyOpen) {
            console2.log("Every route is already contained. Skipping.");
        } else {
            addToBatch(config, abi.encodeWithSelector(ICCIPBridgeConfig.disableAllChains.selector));
            console2.log("Added: CCIPBridgeConfig.disableAllChains");
        }

        _setPostBatchValidateSelector(this._validateDisabled.selector);

        proposeBatch();
    }

    /// @notice Disables the config timelock and the config policy (Emergency MS, or any
    ///         `emergency` or `admin` holder as owner).
    /// @dev    Freezes the control plane: queueing and execution stop, queued actions are kept
    ///         and may expire, and containment stays available. Transfers are not stopped; use
    ///         `disableChain` or `disableAllChains` for that. A policy that is already disabled
    ///         is skipped. Recovery is `reEnable` within the grace window, or the admin `enable`
    ///         path afterwards.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
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
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");
        ROLESv1 roles = _roles(kernel);
        require(
            roles.hasRole(_owner, EMERGENCY_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            "CCIPBridgeConfigBatch: the batch owner holds neither emergency nor admin"
        );

        console2.log("\n=== Disable the CCIP config timelock and config policy ===");
        _planDisable(timelock, "CCIPBridgeConfigTimelock");
        _planDisable(config, "CCIPBridgeConfig");

        _setPostBatchValidateSelector(this._validateDisabledPolicies.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `disablePolicies`.
    function _validateDisabledPolicies() external view {
        console2.log("\nValidating disablePolicies post-batch state");
        for (uint256 i; i < _expectedDisabledPolicies.length; ++i) {
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
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address ocgTimelock = _envAddressNotZero("olympus.governance.Timelock");

        console2.log("\nValidating prepareHandover post-batch state");

        require(
            Kernel(kernel).isPolicyActive(Policy(config)),
            "CCIPBridgeConfig is not active in the Kernel"
        );
        require(
            Kernel(kernel).isPolicyActive(Policy(timelock)),
            "CCIPBridgeConfigTimelock is not active in the Kernel"
        );
        console2.log("  Both policies are active in the Kernel");

        address poolOwner = ICCIPTokenPoolAdmin(pool).owner();
        require(
            poolOwner == config || _pendingOwner(pool) == config,
            "CCIPBridgeConfig is neither the owner nor the pending owner of the pool"
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
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");

        console2.log("\nValidating reEnable post-batch state");
        if (_expectConfigEnabled) {
            require(IEnabler(config).isEnabled(), "CCIPBridgeConfig is not enabled");
            console2.log("  CCIPBridgeConfig is enabled");
        }
        if (_expectTimelockEnabled) {
            require(IEnabler(timelock).isEnabled(), "CCIPBridgeConfigTimelock is not enabled");
            console2.log("  CCIPBridgeConfigTimelock is enabled");
        }
        console2.log("reEnable post-batch validation passed");
    }

    /// @notice Validates the state after `disableChain` or `disableAllChains`.
    function _validateDisabled() external view {
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");

        console2.log("\nValidating containment post-batch state");
        for (uint256 i; i < _expectedDisabledSelectors.length; ++i) {
            uint64 selector = _expectedDisabledSelectors[i];
            require(
                ICCIPBridgeConfig(config).isChainDisabled(selector),
                string.concat("Route ", vm.toString(selector), " is not contained")
            );
            console2.log("  Route", selector, "is contained");
        }
        console2.log("Containment post-batch validation passed");
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
            console2.log("CCIPBridgeConfig already owns the pool. Skipping.");
            return;
        }
        if (pending == config_) {
            console2.log("CCIPBridgeConfig is already the pending owner of the pool. Skipping.");
            return;
        }
        require(
            owner == _owner,
            string.concat(
                "CCIPBridgeConfigBatch: unexpected pool owner ",
                vm.toString(owner),
                "; the batch owner must own the pool to propose CCIPBridgeConfig"
            )
        );

        addToBatch(
            pool_,
            abi.encodeWithSelector(ICCIPTokenPoolAdmin.transferOwnership.selector, config_)
        );
        console2.log("Added: pool.transferOwnership(CCIPBridgeConfig)");
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
            "CCIPBridgeConfigBatch: the registered OHM pool is not the configured pool"
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
                "CCIPBridgeConfigBatch: unexpected OHM administrator ",
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
                "CCIPBridgeConfigBatch: ",
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
            "CCIPBridgeConfigBatch: the batch owner does not hold bridge_admin"
        );

        addToBatch(target_, abi.encodeWithSelector(IReEnabler.reEnable.selector));
        console2.log("  Added: reEnable()");
        return true;
    }

    // =========== INTERNAL HELPERS =========== //

    function _containmentAddresses() internal view returns (address config, address pool) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        require(
            ICCIPBridgeConfig(config).pool() == pool,
            "CCIPBridgeConfigBatch: the config policy is bound to another pool"
        );
        ROLESv1 roles = _roles(kernel);
        require(
            roles.hasRole(_owner, EMERGENCY_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            "CCIPBridgeConfigBatch: the batch owner holds neither emergency nor admin"
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
            ICCIPBridgeConfig(config_).pool() == pool_,
            "CCIPBridgeConfigBatch: the config policy is bound to another pool"
        );
        require(
            ICCIPBridgeConfigTimelock(timelock_).config() == config_,
            "CCIPBridgeConfigBatch: the timelock is bound to another config policy"
        );
        require(
            address(Policy(config_).kernel()) == kernel_,
            "CCIPBridgeConfigBatch: the config policy reports another Kernel"
        );
        if (ChainUtils._isCanonicalChain(chain)) {
            require(
                ICCIPBridgeConfig(config_).isLiquidityContainer(),
                "CCIPBridgeConfigBatch: the canonical pool is not a liquidity container"
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
