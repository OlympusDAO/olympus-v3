// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors, one-contract-per-file
pragma solidity ^0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice The flag the legacy LayerZero `CrossChainBridge` policy gates its send path on. A
///         minimal local interface, so this batch does not import the LayerZero contract graph.
interface ILegacyCrossChainBridge {
    function bridgeActive() external view returns (bool);
}

/// @title CCIPNonEthereumSetupBatch
/// @notice The DAO MS batches that roll the CCIP triad (burn/mint pool, config policy, config
///         timelock) out on a non-canonical EVM chain, after the deploy sequence and the pool
///         ownership transfer to the config policy have run. Every action is conditional on the
///         live state, so a second run on a converged state proposes nothing.
///
///         Entry points:
///         - `setup` (DAO MS, during the mainnet proposal's voting window): deactivate the legacy
///           LayerZero bridge in the Kernel, activate the three policies, grant the local roles,
///           enable the config policy and the timelock, accept the pool ownership, set the config
///           operator and add the routes declared in `env.json` directly under the admin role.
///           The pool stays disabled and unregistered: no message can be sent or delivered yet.
///         - `finalize` (DAO MS, immediately after the mainnet proposal executes): enable the
///           pool policy and register it in the local TokenAdminRegistry, which opens the chain
///           in both directions.
///         - `checkReadiness` (read-only, any sender, also on mainnet): the per-chain half of the
///           rollout readiness report that gates the proposal submission.
///
///         The steady state afterwards is served by the shared tooling: routes through
///         `CCIPRouteReconcileBatch`, containment and re-enable through `CCIPBridgeConfigBatch`.
///         The pool itself has no `reEnable`: after a `disable` it is restored only by the local
///         admin role through `enable`.
contract CCIPNonEthereumSetupBatch is BatchScriptV2 {
    // =========== STATE =========== //

    /// @notice The failure count of the running readiness check.
    uint256 internal _failures;

    // =========== ENTRY POINTS =========== //

    /// @notice Rolls the CCIP triad out on a non-canonical chain, without enabling the pool and
    ///         without registering it (DAO MS).
    /// @dev    Each action is added only when the live state lacks it. The batch refuses to run
    ///         until the deploy sequence, the registry administrator handover to the DAO MS and
    ///         the pool ownership transfer to the config policy have happened, and until every
    ///         outgoing lane toward a burn/mint chain carries the raised OHM fee budget.
    ///
    ///         The `admin` grant is chain wide: it applies to every policy of this Kernel, not
    ///         only to the CCIP policies.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The chain is canonical (the mainnet rollout runs through
    ///           `CCIPBridgeConfigBatch.prepareHandover` and the OCG proposal).
    ///         - The batch owner is not the Kernel executor or not the RolesAdmin admin.
    ///         - The deployed config policy, timelock and pool are not bound to each other, or
    ///           the pool reports itself as a liquidity container.
    ///         - The batch owner is not the OHM administrator in the local TokenAdminRegistry.
    ///         - The config policy is neither the owner nor the pending owner of the pool.
    ///         - A lane toward a burn/mint destination carries an OHM delivery gas budget below
    ///           175000 (the revert names the lane).
    ///         - A desired route is marked for removal, or a live route differs from `env.json`
    ///           (the bootstrap expects a clean pool; reconcile through the config timelock
    ///           afterwards).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function setup(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the CCIP contracts, the Kernel policy set and the roles
        _skipHeartbeatValidation = true;
        _requireNonCanonical();

        (
            address kernel,
            address config,
            address timelock,
            address pool,
            address registry,
            address ohm
        ) = _contracts();
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address emergencyMS = _envAddressNotZero("olympus.multisig.emergency");

        console2.log("\n=== Non-Ethereum CCIP setup on", chain, "===");
        console2.log("Kernel:", kernel);
        console2.log("CCIPBurnMintTokenPool:", pool);
        console2.log("CCIPBridgeConfig:", config);
        console2.log("CCIPBridgeConfigTimelock:", timelock);
        console2.log("TokenAdminRegistry:", registry);

        // Preconditions
        _requireBinding(kernel, config, timelock, pool);
        Kernel kernelContract = Kernel(kernel);
        require(
            kernelContract.executor() == _owner,
            string.concat(
                "CCIPNonEthereumSetupBatch: the batch owner is not the Kernel executor ",
                vm.toString(kernelContract.executor())
            )
        );
        require(
            RolesAdmin(rolesAdmin).admin() == _owner,
            string.concat(
                "CCIPNonEthereumSetupBatch: the batch owner is not the RolesAdmin admin ",
                vm.toString(RolesAdmin(rolesAdmin).admin())
            )
        );
        _requireRegistryAdmin(registry, ohm, pool);
        _requirePoolOwnedOrPending(pool, config);
        _requireFeeBudgets();

        // 1. Deactivate the legacy LayerZero bridge in the Kernel
        _planLegacyBridgeDeactivation(kernelContract);

        // 2. Activate the policies in the Kernel
        _planActivatePolicy(kernelContract, pool, "CCIPBurnMintTokenPool");
        _planActivatePolicy(kernelContract, config, "CCIPBridgeConfig");
        _planActivatePolicy(kernelContract, timelock, "CCIPBridgeConfigTimelock");

        // 3. Grant the local roles
        ROLESv1 roles = _roles(kernel);
        console2.log(
            "\nNOTE: the admin role is chain wide; it applies to every policy of this Kernel."
        );
        _planGrantRole(rolesAdmin, roles, ADMIN_ROLE, _owner, "admin");
        _planGrantRole(rolesAdmin, roles, BRIDGE_ADMIN_ROLE, _owner, "bridge_admin");
        _planGrantRole(rolesAdmin, roles, EMERGENCY_ROLE, emergencyMS, "emergency");

        // 4. Enable the config policy and the timelock, take the pool over
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(env, chain);
        if (!IEnabler(config).isEnabled()) {
            addToBatch(config, abi.encodeWithSelector(IEnabler.enable.selector, ""));
            console2.log("Added: CCIPBridgeConfig.enable");
        }
        if (ICCIPTokenPoolAdmin(pool).owner() != config) {
            addToBatch(
                config,
                abi.encodeWithSelector(ICCIPBridgeConfig.acceptPoolOwnership.selector)
            );
            console2.log("Added: CCIPBridgeConfig.acceptPoolOwnership");
        }
        if (ICCIPBridgeConfig(config).configOperator() != timelock) {
            addToBatch(
                config,
                abi.encodeWithSelector(IConfigOperator.setConfigOperator.selector, timelock)
            );
            console2.log("Added: CCIPBridgeConfig.setConfigOperator(timelock)");
        }
        if (ICCIPTokenPoolAdmin(pool).getRateLimitAdmin() != desired.rateLimitAdmin) {
            addToBatch(
                config,
                abi.encodeWithSelector(
                    ICCIPBridgeConfig.setRateLimitAdmin.selector,
                    desired.rateLimitAdmin
                )
            );
            console2.log("Added: CCIPBridgeConfig.setRateLimitAdmin");
        }
        if (!IEnabler(timelock).isEnabled()) {
            addToBatch(timelock, abi.encodeWithSelector(IEnabler.enable.selector, ""));
            console2.log("Added: CCIPBridgeConfigTimelock.enable");
        }

        // 5. Add the missing routes directly under the admin role (the bootstrap needs no
        //    timelock: the routes are voted on as part of the mainnet CCIP Bridge Config
        //    Activation proposal).
        _planRoutes(ICCIPBridgeConfig(config), ICCIPTokenPoolAdmin(pool));

        _setPostBatchValidateSelector(this._validateSetup.selector);

        proposeBatch();
    }

    /// @notice Enables the pool policy and registers it for OHM in the local TokenAdminRegistry
    ///         (DAO MS), which opens the chain for CCIP transfers in both directions.
    /// @dev    Run immediately after the mainnet proposal executes. Until then the chain stays
    ///         dormant: without `setPool` neither an outbound send nor an inbound delivery can
    ///         touch the pool. The order is enable first, register second, so that a registered
    ///         pool is never unable to mint.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The chain is canonical.
    ///         - `setup` has not converged: the pool policy is not active, the config policy does
    ///           not own the pool, the batch owner lacks the admin role, the config policy or the
    ///           timelock is disabled, or a desired route is missing or differs from `env.json`.
    ///         - The batch owner is not the OHM administrator in the local TokenAdminRegistry.
    ///         - Another pool is registered for OHM.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function finalize(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;
        _requireNonCanonical();

        (
            address kernel,
            address config,
            address timelock,
            address pool,
            address registry,
            address ohm
        ) = _contracts();

        console2.log("\n=== Non-Ethereum CCIP finalize on", chain, "===");

        _requireBinding(kernel, config, timelock, pool);
        require(
            Kernel(kernel).isPolicyActive(Policy(pool)),
            "CCIPNonEthereumSetupBatch: the pool policy is not active in the Kernel; run setup first"
        );
        require(
            ICCIPTokenPoolAdmin(pool).owner() == config,
            "CCIPNonEthereumSetupBatch: the config policy does not own the pool; run setup first"
        );
        require(
            _roles(kernel).hasRole(_owner, ADMIN_ROLE),
            "CCIPNonEthereumSetupBatch: the batch owner does not hold the admin role; run setup first"
        );
        require(
            IEnabler(config).isEnabled(),
            "CCIPNonEthereumSetupBatch: CCIPBridgeConfig is disabled; run setup first, or restore it (reEnable within the grace window, enable afterwards)"
        );
        require(
            IEnabler(timelock).isEnabled(),
            "CCIPNonEthereumSetupBatch: CCIPBridgeConfigTimelock is disabled; run setup first, or restore it (reEnable within the grace window, enable afterwards)"
        );
        _requireRoutesConverged(ICCIPTokenPoolAdmin(pool));

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry)
            .getTokenConfig(ohm);
        require(
            tokenConfig.administrator == _owner,
            string.concat(
                "CCIPNonEthereumSetupBatch: the batch owner is not the OHM administrator ",
                vm.toString(tokenConfig.administrator)
            )
        );
        require(
            tokenConfig.tokenPool == address(0) || tokenConfig.tokenPool == pool,
            string.concat(
                "CCIPNonEthereumSetupBatch: another pool is registered for OHM: ",
                vm.toString(tokenConfig.tokenPool)
            )
        );

        if (IEnabler(pool).isEnabled()) {
            console2.log("The pool policy is already enabled. Skipping.");
        } else {
            addToBatch(pool, abi.encodeWithSelector(IEnabler.enable.selector, ""));
            console2.log("Added: CCIPBurnMintTokenPool.enable");
        }

        if (tokenConfig.tokenPool == pool) {
            console2.log("The pool is already registered for OHM. Skipping.");
        } else {
            addToBatch(
                registry,
                abi.encodeWithSelector(ICCIPTokenAdminRegistry.setPool.selector, ohm, pool)
            );
            console2.log("Added: TokenAdminRegistry.setPool(OHM, pool)");
        }

        _setPostBatchValidateSelector(this._validateFinalize.selector);

        proposeBatch();
    }

    /// @notice The per-chain half of the rollout readiness report (read-only, any sender). On a
    ///         non-canonical chain it checks the deployment, the authority handovers and every
    ///         outgoing lane; on mainnet it checks the Phase B state, the pool backing and the
    ///         mainnet-side lanes. `shell/ccip/check_rollout_readiness.sh` aggregates the answers
    ///         of every chain; the proposal is not submitted until the aggregate is green.
    /// @dev    Prints one `[ OK ]`/`[FAIL]` line per check and a final
    ///         `READINESS RESULT <chain>: GREEN|RED` line. It does not revert on a red result:
    ///         a reverted script would swallow its own log, so the shell wrapper derives the
    ///         exit code from the verdict line instead. A revert can still happen when the
    ///         environment itself is unreadable (a malformed or incomplete `env.json`), which
    ///         the wrapper also treats as red. Performs no state change on the chain.
    function checkReadiness() external {
        _loadEnv(ChainUtils._getChainName(block.chainid));
        _failures = 0;

        console2.log("\n=== CCIP rollout readiness:", chain, "===");
        if (ChainUtils._isCanonicalChain(chain)) {
            _checkCanonicalReadiness();
        } else {
            _checkNonCanonicalReadiness();
        }

        console2.log(
            string.concat("\nREADINESS RESULT ", chain, ": ", _failures == 0 ? "GREEN" : "RED")
        );
    }

    /// @notice Reads the OHM delivery gas budget of one lane. External so that the readiness
    ///         check can try/catch a lane that cannot be read and keep checking the others.
    function laneBudget(
        string calldata localChain_,
        string calldata remoteChain_
    ) external view returns (uint32 overhead, bool isTokenEntry, string memory source) {
        return CCIPFeeBudgetLib.readOhmDestGasOverhead(env, localChain_, remoteChain_);
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `setup`.
    function _validateSetup() external view {
        (address kernel, address config, address timelock, address pool, , ) = _contracts();
        address emergencyMS = _envAddressNotZero("olympus.multisig.emergency");
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(env, chain);
        ROLESv1 roles = _roles(kernel);

        console2.log("\nValidating setup post-batch state");
        require(
            Kernel(kernel).isPolicyActive(Policy(pool)),
            "CCIPBurnMintTokenPool is not active in the Kernel"
        );
        require(
            Kernel(kernel).isPolicyActive(Policy(config)),
            "CCIPBridgeConfig is not active in the Kernel"
        );
        require(
            Kernel(kernel).isPolicyActive(Policy(timelock)),
            "CCIPBridgeConfigTimelock is not active in the Kernel"
        );
        address legacyBridge = _envAddress("olympus.policies.CrossChainBridge");
        require(
            legacyBridge == address(0) || !Kernel(kernel).isPolicyActive(Policy(legacyBridge)),
            "The legacy CrossChainBridge policy is still active in the Kernel"
        );
        require(IEnabler(config).isEnabled(), "CCIPBridgeConfig is not enabled");
        require(IEnabler(timelock).isEnabled(), "CCIPBridgeConfigTimelock is not enabled");
        require(
            ICCIPTokenPoolAdmin(pool).owner() == config,
            "CCIPBridgeConfig does not own the pool"
        );
        require(CCIPConfigLib.pendingOwner(pool) == address(0), "The pool has a pending owner");
        require(
            ICCIPBridgeConfig(config).configOperator() == timelock,
            "CCIPBridgeConfigTimelock is not the config operator"
        );
        require(
            ICCIPTokenPoolAdmin(pool).getRateLimitAdmin() == desired.rateLimitAdmin,
            "The native rate limit admin is not the desired value"
        );
        require(roles.hasRole(_owner, ADMIN_ROLE), "The DAO MS does not hold admin");
        require(roles.hasRole(_owner, BRIDGE_ADMIN_ROLE), "The DAO MS does not hold bridge_admin");
        require(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "The Emergency MS does not hold emergency"
        );
        require(
            IGracePeriod(config).gracePeriod() == desired.gracePeriod,
            "CCIPBridgeConfig grace period mismatch"
        );
        require(
            IGracePeriod(timelock).gracePeriod() == desired.gracePeriod,
            "CCIPBridgeConfigTimelock grace period mismatch"
        );
        require(
            ICCIPBridgeConfigTimelock(timelock).timelockDelay() == desired.timelockDelay,
            "CCIPBridgeConfigTimelock delay mismatch"
        );
        _requireRoutesConverged(ICCIPTokenPoolAdmin(pool));
        console2.log("setup post-batch validation passed");
    }

    /// @notice Validates the state after `finalize`.
    function _validateFinalize() external view {
        (
            address kernel,
            address config,
            address timelock,
            address pool,
            address registry,
            address ohm
        ) = _contracts();
        ROLESv1 roles = _roles(kernel);

        console2.log("\nValidating finalize post-batch state");
        require(IEnabler(pool).isEnabled(), "CCIPBurnMintTokenPool is not enabled");
        require(
            ICCIPTokenAdminRegistry(registry).getTokenConfig(ohm).tokenPool == pool,
            "The pool is not registered for OHM"
        );
        require(
            ICCIPTokenPoolAdmin(pool).owner() == config,
            "CCIPBridgeConfig does not own the pool"
        );
        require(IEnabler(config).isEnabled(), "CCIPBridgeConfig is not enabled");
        require(IEnabler(timelock).isEnabled(), "CCIPBridgeConfigTimelock is not enabled");
        require(roles.hasRole(_owner, ADMIN_ROLE), "The DAO MS does not hold admin");
        require(roles.hasRole(_owner, BRIDGE_ADMIN_ROLE), "The DAO MS does not hold bridge_admin");
        _requireRoutesConverged(ICCIPTokenPoolAdmin(pool));
        console2.log("finalize post-batch validation passed");
    }

    // =========== READINESS =========== //

    function _checkNonCanonicalReadiness() internal {
        address pool = _envAddress(CCIPConfigLib.poolKey(chain));
        address config = _envAddress("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddress("olympus.policies.CCIPBridgeConfigTimelock");
        address periphery = _envAddress(CCIPConfigLib.EVM_BRIDGE_KEY);
        address kernel = _envAddressNotZero("olympus.Kernel");
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        address emergencyMS = _envAddressNotZero("olympus.multisig.emergency");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");

        bool deployed = pool != address(0) &&
            config != address(0) &&
            timelock != address(0) &&
            periphery != address(0);
        _check(
            deployed,
            "the pool, the config policy, the timelock and the periphery are recorded in env.json"
        );
        if (deployed) {
            _check(
                ICCIPBridgeConfig(config).pool() == pool &&
                    ICCIPBridgeConfigTimelock(timelock).config() == config &&
                    address(Policy(config).kernel()) == kernel,
                "the config policy, the timelock and the pool are bound to each other"
            );
            _check(
                !ICCIPBridgeConfig(config).isLiquidityContainer(),
                "the pool is a burn/mint pool (not a liquidity container)"
            );
            address poolOwner = ICCIPTokenPoolAdmin(pool).owner();
            _check(
                poolOwner == config || CCIPConfigLib.pendingOwner(pool) == config,
                string.concat(
                    "the config policy owns or is the pending owner of the pool (owner ",
                    vm.toString(poolOwner),
                    "; if the deployer still owns it, run CCIPTokenPool.transferTokenPoolOwnershipToConfig)"
                )
            );
            _check(
                Owned(periphery).owner() == daoMS,
                "the DAO MS owns the CCIPCrossChainBridge periphery"
            );
        }

        _check(Kernel(kernel).executor() == daoMS, "the DAO MS is the Kernel executor");
        _check(RolesAdmin(rolesAdmin).admin() == daoMS, "the DAO MS is the RolesAdmin admin");

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry)
            .getTokenConfig(ohm);
        _check(
            tokenConfig.administrator == daoMS,
            string.concat(
                "the DAO MS is the OHM administrator in the TokenAdminRegistry (administrator ",
                vm.toString(tokenConfig.administrator),
                ", pending ",
                vm.toString(tokenConfig.pendingAdministrator),
                ")"
            )
        );
        _check(
            tokenConfig.tokenPool == address(0) || tokenConfig.tokenPool == pool,
            "no other pool is registered for OHM"
        );

        ROLESv1 roles = _roles(kernel);
        _check(roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE), "the DAO MS holds bridge_admin");
        _check(roles.hasRole(emergencyMS, EMERGENCY_ROLE), "the Emergency MS holds emergency");
        if (!roles.hasRole(daoMS, ADMIN_ROLE)) {
            console2.log("  [INFO] the DAO MS does not hold admin yet; the setup batch grants it");
        }

        address legacyBridge = _envAddress("olympus.policies.CrossChainBridge");
        if (legacyBridge != address(0)) {
            _check(
                !ILegacyCrossChainBridge(legacyBridge).bridgeActive(),
                "the legacy CrossChainBridge is operationally disabled (bridgeActive is false)"
            );
            MINTRv1 mintr = MINTRv1(
                address(Kernel(kernel).getModuleForKeycode(toKeycode("MINTR")))
            );
            _check(
                mintr.mintApproval(legacyBridge) == 0,
                "the legacy CrossChainBridge holds no MINTR mint approval"
            );
        }

        _checkLanes();
    }

    function _checkCanonicalReadiness() internal {
        address pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        address config = _envAddress("olympus.policies.CCIPBridgeConfig");
        address timelock = _envAddress("olympus.policies.CCIPBridgeConfigTimelock");
        address kernel = _envAddressNotZero("olympus.Kernel");
        address registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        address ohm = _envAddressNotZero("olympus.legacy.OHM");
        address ocgTimelock = _envAddressNotZero("olympus.governance.Timelock");

        bool deployed = config != address(0) && timelock != address(0);
        _check(deployed, "the config policy and the timelock are recorded in env.json");
        if (deployed) {
            _check(
                ICCIPBridgeConfig(config).pool() == pool &&
                    ICCIPBridgeConfigTimelock(timelock).config() == config,
                "the config policy, the timelock and the pool are bound to each other"
            );
            _check(
                Kernel(kernel).isPolicyActive(Policy(config)) &&
                    Kernel(kernel).isPolicyActive(Policy(timelock)),
                "both policies are active in the Kernel (Phase B)"
            );
            address poolOwner = ICCIPTokenPoolAdmin(pool).owner();
            _check(
                poolOwner == config || CCIPConfigLib.pendingOwner(pool) == config,
                "the config policy owns or is the pending owner of the pool (Phase B)"
            );
            (uint8 major, uint8 minor) = IVersioned(config).VERSION();
            _check(major == 1 && minor == 0, "CCIPBridgeConfig reports version 1.0");
        }

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry)
            .getTokenConfig(ohm);
        _check(
            tokenConfig.administrator == ocgTimelock ||
                tokenConfig.pendingAdministrator == ocgTimelock,
            "the OCG timelock is the OHM administrator or the pending administrator (Phase B)"
        );
        _check(tokenConfig.tokenPool == pool, "the configured pool is registered for OHM");

        uint256 minBacking = CCIPConfigLib.minimumPoolBacking(env, chain);
        uint256 poolBalance = IERC20(ohm).balanceOf(pool);
        _check(
            poolBalance >= minBacking,
            string.concat(
                "the pool backing covers the burn/mint supply: balance ",
                vm.toString(poolBalance),
                ", required ",
                vm.toString(minBacking),
                " (run CCIPTokenPool.fundPool and re-read shell/calc_bridged_supply.sh)"
            )
        );

        _checkLanes();
    }

    /// @notice Checks the OHM delivery gas budget of every outgoing lane whose destination is a
    ///         burn/mint chain.
    function _checkLanes() internal {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        for (uint256 i; i < desired.length; ++i) {
            if (!desired[i].enabled || desired[i].remove) continue;
            if (!CCIPConfigLib.isBurnMintEvmChain(desired[i].remoteChain)) continue;
            _checkLane(desired[i].remoteChain);
        }
    }

    function _checkLane(string memory remoteChain_) internal {
        string memory lane = string.concat("lane ", chain, " -> ", remoteChain_);
        try this.laneBudget(chain, remoteChain_) returns (
            uint32 overhead,
            bool isTokenEntry,
            string memory source
        ) {
            // A raised chain default is not accepted: the D0 precondition is an enabled OHM
            // token entry, since the default is shared by every token of the destination.
            _check(
                isTokenEntry && overhead >= CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
                string.concat(
                    lane,
                    ": OHM delivery gas budget ",
                    vm.toString(overhead),
                    " (",
                    source,
                    "), required an enabled OHM token entry of at least ",
                    vm.toString(uint256(CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD))
                )
            );
        } catch Error(string memory reason) {
            _check(false, string.concat(lane, ": ", reason));
        }
    }

    function _check(bool ok_, string memory description_) internal {
        console2.log(string.concat(ok_ ? "  [ OK ] " : "  [FAIL] ", description_));
        if (!ok_) _failures++;
    }

    // =========== PLANNING HELPERS =========== //

    function _planLegacyBridgeDeactivation(Kernel kernel_) internal {
        address bridge = _envAddress("olympus.policies.CrossChainBridge");
        if (bridge == address(0)) {
            console2.log("No legacy CrossChainBridge is recorded for this chain. Skipping.");
            return;
        }
        if (!kernel_.isPolicyActive(Policy(bridge))) {
            console2.log(
                "The legacy CrossChainBridge is already inactive in the Kernel. Skipping."
            );
            return;
        }

        // The Kernel checks nothing itself; stop rather than deactivate a bridge that is
        // operating or mid-mint.
        require(
            !ILegacyCrossChainBridge(bridge).bridgeActive(),
            "CCIPNonEthereumSetupBatch: the legacy CrossChainBridge reports bridgeActive; disable it before deactivating"
        );
        MINTRv1 mintr = MINTRv1(address(kernel_.getModuleForKeycode(toKeycode("MINTR"))));
        require(
            mintr.mintApproval(bridge) == 0,
            "CCIPNonEthereumSetupBatch: the legacy CrossChainBridge still holds a MINTR mint approval"
        );

        addToBatch(
            address(kernel_),
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, bridge)
        );
        console2.log("Added: Kernel.executeAction(DeactivatePolicy, CrossChainBridge)");
    }

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

    function _planGrantRole(
        address rolesAdmin_,
        ROLESv1 roles_,
        bytes32 role_,
        address holder_,
        string memory name_
    ) internal {
        if (roles_.hasRole(holder_, role_)) {
            console2.log("Role", name_, "is already held by", holder_);
            return;
        }
        addToBatch(
            rolesAdmin_,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, role_, holder_)
        );
        console2.log(string.concat("Added: RolesAdmin.grantRole(", name_, ")"), holder_);
    }

    function _planRoutes(ICCIPBridgeConfig config_, ICCIPTokenPoolAdmin pool_) internal {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        require(
            desired.length > 0,
            "CCIPNonEthereumSetupBatch: env.json declares no CCIP route for this chain"
        );

        console2.log("\n--- Routes ---");
        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(
                pool_,
                route.chainSelector
            );
            console2.log("Route", route.remoteChain, "selector", route.chainSelector);

            require(
                !route.remove,
                string.concat(
                    "CCIPNonEthereumSetupBatch: route ",
                    route.remoteChain,
                    " is marked for removal; the bootstrap expects no removal marker (use CCIPRouteReconcileBatch after the setup)"
                )
            );
            if (!route.enabled) {
                console2.log("  Declared with enabled=false: not configured.");
                continue;
            }

            if (live.exists) {
                require(
                    !CCIPConfigLib.hasChanges(CCIPConfigLib.diffRoute(route, live)),
                    string.concat(
                        "CCIPNonEthereumSetupBatch: route ",
                        route.remoteChain,
                        " differs from env.json; the bootstrap expects a clean pool (use CCIPRouteReconcileBatch after the setup)"
                    )
                );
                console2.log("  Already configured and matching env.json. Skipping.");
                continue;
            }

            ICCIPTokenPoolAdmin.ChainUpdate memory update = ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: route.chainSelector,
                remotePoolAddresses: route.remotePools,
                remoteTokenAddress: route.remoteToken,
                outboundRateLimiterConfig: route.outbound,
                inboundRateLimiterConfig: route.inbound
            });
            // Surface the config policy's own validation before batching
            config_.validateAddChain(update);
            addToBatch(
                address(config_),
                abi.encodeWithSelector(ICCIPBridgeConfig.addChain.selector, update)
            );
            console2.log("  Added: CCIPBridgeConfig.addChain");
        }

        uint64[] memory liveSelectors = pool_.getSupportedChains();
        for (uint256 i; i < liveSelectors.length; ++i) {
            bool declared;
            for (uint256 j; j < desired.length; ++j) {
                if (desired[j].chainSelector == liveSelectors[i]) {
                    declared = true;
                    break;
                }
            }
            if (!declared) {
                console2.log(
                    "\nWARNING: live route",
                    liveSelectors[i],
                    "is not declared in env.json and is left untouched."
                );
            }
        }
    }

    // =========== INTERNAL HELPERS =========== //

    function _requireNonCanonical() internal view {
        require(
            !ChainUtils._isCanonicalChain(chain),
            "CCIPNonEthereumSetupBatch: the chain is canonical; use CCIPBridgeConfigBatch.prepareHandover and the OCG proposal"
        );
    }

    function _contracts()
        internal
        view
        returns (
            address kernel,
            address config,
            address timelock,
            address pool,
            address registry,
            address ohm
        )
    {
        kernel = _envAddressNotZero("olympus.Kernel");
        config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");
        timelock = _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock");
        pool = _envAddressNotZero(CCIPConfigLib.poolKey(chain));
        registry = _envAddressNotZero("external.ccip.TokenAdminRegistry");
        ohm = _envAddressNotZero("olympus.legacy.OHM");
    }

    /// @notice Reverts unless the config policy, the timelock and the pool are bound together
    ///         and the pool is a burn/mint pool.
    function _requireBinding(
        address kernel_,
        address config_,
        address timelock_,
        address pool_
    ) internal view {
        require(
            ICCIPBridgeConfig(config_).pool() == pool_,
            "CCIPNonEthereumSetupBatch: the config policy is bound to another pool"
        );
        require(
            ICCIPBridgeConfigTimelock(timelock_).config() == config_,
            "CCIPNonEthereumSetupBatch: the timelock is bound to another config policy"
        );
        require(
            address(Policy(config_).kernel()) == kernel_,
            "CCIPNonEthereumSetupBatch: the config policy reports another Kernel"
        );
        require(
            !ICCIPBridgeConfig(config_).isLiquidityContainer(),
            "CCIPNonEthereumSetupBatch: the pool reports itself as a liquidity container; a burn/mint pool is expected on a non-canonical chain"
        );
    }

    function _requireRegistryAdmin(address registry_, address ohm_, address pool_) internal view {
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(registry_)
            .getTokenConfig(ohm_);
        if (tokenConfig.administrator != _owner) {
            revert(
                string.concat(
                    "CCIPNonEthereumSetupBatch: the batch owner is not the OHM administrator (administrator ",
                    vm.toString(tokenConfig.administrator),
                    ", pending ",
                    vm.toString(tokenConfig.pendingAdministrator),
                    "). ",
                    tokenConfig.pendingAdministrator == _owner
                        ? "Run CCIPTokenPool.acceptAdminRole from the DAO MS first."
                        : "Run CCIPTokenPool.transferTokenPoolAdminRoleToDaoMS from the deployer EOA, then CCIPTokenPool.acceptAdminRole from the DAO MS."
                )
            );
        }
        require(
            tokenConfig.tokenPool == address(0) || tokenConfig.tokenPool == pool_,
            string.concat(
                "CCIPNonEthereumSetupBatch: another pool is registered for OHM: ",
                vm.toString(tokenConfig.tokenPool)
            )
        );
    }

    function _requirePoolOwnedOrPending(address pool_, address config_) internal view {
        address poolOwner = ICCIPTokenPoolAdmin(pool_).owner();
        address pending = CCIPConfigLib.pendingOwner(pool_);
        console2.log("Pool owner:", poolOwner, "pending owner:", pending);
        require(
            poolOwner == config_ || pending == config_,
            string.concat(
                "CCIPNonEthereumSetupBatch: the config policy is neither the owner nor the pending owner of the pool (owner ",
                vm.toString(poolOwner),
                "); run CCIPTokenPool.transferTokenPoolOwnershipToConfig from the pool owner"
            )
        );
    }

    /// @notice Reverts unless every outgoing lane toward a burn/mint destination carries the
    ///         raised OHM delivery gas budget.
    function _requireFeeBudgets() internal view {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        console2.log("\n--- Outgoing lane fee budgets ---");
        for (uint256 i; i < desired.length; ++i) {
            if (!desired[i].enabled || desired[i].remove) continue;
            if (!CCIPConfigLib.isBurnMintEvmChain(desired[i].remoteChain)) {
                console2.log(
                    "Lane to",
                    desired[i].remoteChain,
                    "needs no raised budget (not a burn/mint destination)."
                );
                continue;
            }
            (uint32 overhead, , string memory source) = CCIPFeeBudgetLib.readOhmDestGasOverhead(
                env,
                chain,
                desired[i].remoteChain
            );
            console2.log(
                string.concat(
                    "Lane ",
                    chain,
                    " -> ",
                    desired[i].remoteChain,
                    ": ",
                    vm.toString(overhead),
                    " (",
                    source,
                    ")"
                )
            );
            CCIPFeeBudgetLib.requireOhmFeeBudget(env, chain, desired[i].remoteChain);
        }
    }

    /// @notice Reverts unless every desired route of `env.json` is live on the pool and matches
    ///         it field by field.
    function _requireRoutesConverged(ICCIPTokenPoolAdmin pool_) internal view {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        require(
            desired.length > 0,
            "CCIPNonEthereumSetupBatch: env.json declares no CCIP route for this chain"
        );
        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            if (!route.enabled || route.remove) continue;
            CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(
                pool_,
                route.chainSelector
            );
            require(
                live.exists,
                string.concat(
                    "CCIPNonEthereumSetupBatch: route ",
                    route.remoteChain,
                    " is not configured on the pool; run setup first"
                )
            );
            require(
                !CCIPConfigLib.hasChanges(CCIPConfigLib.diffRoute(route, live)),
                string.concat(
                    "CCIPNonEthereumSetupBatch: route ",
                    route.remoteChain,
                    " differs from env.json"
                )
            );
        }
    }

    function _roles(address kernel_) internal view returns (ROLESv1 roles) {
        return ROLESv1(address(Kernel(kernel_).getModuleForKeycode(toKeycode("ROLES"))));
    }
}
