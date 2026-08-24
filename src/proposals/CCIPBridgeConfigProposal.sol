// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice OCG proposal that moves the mainnet CCIP OHM token pool under the CCIPBridgeConfig
///         policy and its CCIPBridgeConfigTimelock, and the OHM administrator position in the
///         Chainlink TokenAdminRegistry under the OCG timelock.
///
///         Every action is conditional on the live state, so the proposal is idempotent with
///         respect to steps that already happened. The actions read, in order:
///         accept the OHM administrator role, grant `bridge_admin` to the DAO MS, enable the
///         config policy, accept the pool ownership, set the config timelock as config operator,
///         set the OCG timelock as rebalancer, clear the native rate limit admin, and enable the
///         config timelock. At most eight actions, so no activator contract is needed.
///
///         Assumes:
///         - CCIPBridgeConfig and CCIPBridgeConfigTimelock have been deployed on Ethereum mainnet
///           and recorded in `src/proposals/addresses.json` and `src/scripts/env.json`.
///         - The DAO MS has run `CCIPBridgeConfigBatch.prepareHandover`: both policies are active
///           in the Kernel, CCIPBridgeConfig is the pending owner of the pool and the OCG timelock
///           is the pending OHM administrator in the TokenAdminRegistry.
///         - The OCG timelock holds the `admin` role.
///         - The live Solana route of the pool matches `olympus.config.CCIP.routes` in
///           `src/scripts/env.json`; the proposal changes no route.
contract CCIPBridgeConfigProposal is GovernorBravoProposal {
    // ========== CONSTANTS ========== //

    string internal constant _ENV_PATH = "./src/scripts/env.json";

    // ========== DATA STRUCTURES ========== //

    /// @dev The contracts and accounts the proposal acts on, resolved from the address registry.
    struct Contracts {
        ICCIPBridgeConfig config;
        ICCIPBridgeConfigTimelock configTimelock;
        ICCIPTokenPoolAdmin pool;
        ICCIPTokenAdminRegistry registry;
        ROLESv1 roles;
        address rolesAdmin;
        address ohm;
        address daoMS;
        address emergencyMS;
        address ocgTimelock;
        address bridge;
    }

    // ========== STATE ========== //

    Kernel internal _kernel;

    /// @dev The contents of `env.json`, the desired-state source that the proposal validates
    ///      the deployment and the routes against.
    string internal _env;

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 20;
    }

    function name() public pure override returns (string memory) {
        return "CCIP Bridge Config Activation";
    }

    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return string.concat(_descriptionPreamble(), _descriptionSteps());
    }

    function _descriptionPreamble() private pure returns (string memory) {
        return
            string.concat(
                "# CCIP Bridge Config Activation\n",
                "\n",
                "This proposal places the Chainlink CCIP OHM token pool on Ethereum mainnet under on-chain governance through the CCIPBridgeConfig policy and the CCIPBridgeConfigTimelock policy.\n",
                "\n",
                "## Justification\n",
                "\n",
                "The mainnet CCIP OHM pool (LockReleaseTokenPool) and the OHM administrator position in the Chainlink TokenAdminRegistry are held by the DAO MS. This proposal separates that authority into three layers:\n",
                "\n",
                "- The OCG timelock becomes the OHM administrator in the TokenAdminRegistry (the authority that selects or delists the OHM pool), the `admin` of the CCIPBridgeConfig policy (root settings, pool ownership, router, rebalancer, rate limit admin) and the rebalancer of the lock/release pool (the only authority that can withdraw its liquidity).\n",
                "- The CCIPBridgeConfig policy becomes the owner of the token pool and exposes a typed, role-separated subset of the pool owner surface: route, remote pool, allowlist and rate limit changes are callable by the config timelock (after its delay) or directly by `admin`; containment (`disableChain`, `disableAllChains`) is callable by the `emergency` role at any time and can only reduce capacity; there is no arbitrary call forwarding.\n",
                "- The DAO MS keeps `bridge_admin`: it queues typed route changes on the CCIPBridgeConfigTimelock, which executes them permissionlessly after a one-day delay and rejects them if the route moved in the meantime, and it can re-enable either policy within a three-day grace window after a disable. The DAO MS keeps ownership of the user-facing CCIPCrossChainBridge periphery, which is not part of this proposal.\n",
                "\n",
                "The `bridge_rate_limiter` role, a direct rate-limit path for a future monitoring operator, stays unassigned. The native pool rate limit admin stays unset so that every rate limit change passes through the policy.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- Operator documentation: `documentation/bridge/ccip/README.md` in the olympus-v3 repository.\n",
                "- Contracts: `src/policies/bridge/CCIPBridgeConfig.sol`, `src/policies/bridge/CCIPBridgeConfigTimelock.sol`.\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- CCIPBridgeConfig and CCIPBridgeConfigTimelock have been deployed on Ethereum mainnet with a 3-day grace period and a 1-day initial timelock delay.\n",
                "- The DAO MS has activated both policies in the Kernel, proposed CCIPBridgeConfig as the new owner of the token pool and nominated the OCG timelock as the OHM administrator in the TokenAdminRegistry.\n",
                "- The OCG timelock holds the `admin` role.\n",
                "- The live Solana route of the pool matches the desired configuration; the proposal changes no route.\n"
            );
    }

    function _descriptionSteps() private pure returns (string memory) {
        return
            string.concat(
                "\n",
                "## Proposal Steps\n",
                "\n",
                "Each step is included only if the live state requires it.\n",
                "\n",
                "1. Accept the OHM administrator role in the Chainlink TokenAdminRegistry. The registered OHM pool is not changed.\n",
                "2. Grant the `bridge_admin` role to the DAO MS.\n",
                "3. Enable the CCIPBridgeConfig policy.\n",
                "4. Accept the ownership of the token pool through CCIPBridgeConfig.\n",
                "5. Set the CCIPBridgeConfigTimelock as the config operator of CCIPBridgeConfig.\n",
                "6. Set the OCG timelock as the rebalancer of the token pool.\n",
                "7. Clear the native rate limit admin of the token pool.\n",
                "8. Enable the CCIPBridgeConfigTimelock policy.\n",
                "\n",
                "At the completion of this proposal, route configuration is proposed by the DAO MS through the CCIPBridgeConfigTimelock and executed after its delay, containment is available to the Emergency MS through CCIPBridgeConfig, and the remaining root settings of the pool require an OCG proposal.\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        _env = vm.readFile(_ENV_PATH);
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    function _build(Addresses addresses) internal override {
        Contracts memory c = _contracts(addresses);
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(_env, _chain());

        // Preconditions: the deployment, the admin role, the routes
        _requireDeployment(c);
        require(
            desired.rebalancer == c.ocgTimelock,
            "env.json olympus.config.CCIPBridgeConfig.rebalancer is not the OCG timelock"
        );
        require(
            c.roles.hasRole(c.ocgTimelock, ADMIN_ROLE),
            "The OCG timelock does not hold the admin role"
        );
        _requireRoutesMatchEnv(c.pool);

        // 1. Accept the OHM administrator role (conditional)
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = c.registry.getTokenConfig(c.ohm);
        require(
            tokenConfig.tokenPool == address(c.pool),
            "The registered OHM pool is not the configured pool"
        );
        if (tokenConfig.administrator != c.ocgTimelock) {
            require(
                tokenConfig.pendingAdministrator == c.ocgTimelock,
                "The OCG timelock is not the pending OHM administrator: run CCIPBridgeConfigBatch.prepareHandover first"
            );
            _pushAction(
                address(c.registry),
                abi.encodeWithSelector(ICCIPTokenAdminRegistry.acceptAdminRole.selector, c.ohm),
                "Accept the OHM administrator role in the TokenAdminRegistry"
            );
        }

        // 2. Grant bridge_admin to the DAO MS (conditional)
        if (!c.roles.hasRole(c.daoMS, BRIDGE_ADMIN_ROLE)) {
            require(
                RolesAdmin(c.rolesAdmin).admin() == c.ocgTimelock,
                "The OCG timelock is not the RolesAdmin admin"
            );
            _pushAction(
                c.rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, BRIDGE_ADMIN_ROLE, c.daoMS),
                "Grant bridge_admin role to the DAO MS"
            );
        }

        // 3. Enable the config policy (conditional); its admin functions require it
        if (!IEnabler(address(c.config)).isEnabled()) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(IEnabler.enable.selector, ""),
                "Enable CCIPBridgeConfig"
            );
        }

        // 4. Accept the pool ownership (conditional)
        if (c.pool.owner() != address(c.config)) {
            require(
                _pendingOwner(address(c.pool)) == address(c.config),
                "CCIPBridgeConfig is not the pending owner of the pool: run CCIPBridgeConfigBatch.prepareHandover first"
            );
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPBridgeConfig.acceptPoolOwnership.selector),
                "Accept the token pool ownership through CCIPBridgeConfig"
            );
        }

        // 5. Set the config timelock as config operator (conditional)
        if (c.config.configOperator() != address(c.configTimelock)) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    IConfigOperator.setConfigOperator.selector,
                    address(c.configTimelock)
                ),
                "Set CCIPBridgeConfigTimelock as the config operator of CCIPBridgeConfig"
            );
        }

        // 6. Set the OCG timelock as rebalancer (conditional)
        if (ICCIPLockReleaseTokenPool(address(c.pool)).getRebalancer() != desired.rebalancer) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    ICCIPBridgeConfig.setRebalancer.selector,
                    desired.rebalancer
                ),
                "Set the OCG timelock as the rebalancer of the token pool"
            );
        }

        // 7. Clear the native rate limit admin (conditional)
        if (c.pool.getRateLimitAdmin() != desired.rateLimitAdmin) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    ICCIPBridgeConfig.setRateLimitAdmin.selector,
                    desired.rateLimitAdmin
                ),
                "Set the native rate limit admin of the token pool"
            );
        }

        // 8. Enable the config timelock (conditional)
        if (!IEnabler(address(c.configTimelock)).isEnabled()) {
            _pushAction(
                address(c.configTimelock),
                abi.encodeWithSelector(IEnabler.enable.selector, ""),
                "Enable CCIPBridgeConfigTimelock"
            );
        }
    }

    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    function _validate(Addresses addresses, address) internal view override {
        Contracts memory c = _contracts(addresses);
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(_env, _chain());

        _requireDeployment(c);
        _validateLifecycle(c);
        _validatePoolAuthority(c, desired);
        _validateRegistry(c);
        _validateRoles(c, addresses.getAddress("proposer"));
        _validateParameters(c, desired);
        _requireRoutesMatchEnv(c.pool);

        // The periphery is untouched
        require(Owned(c.bridge).owner() == c.daoMS, "CCIPCrossChainBridge owner changed");
    }

    // ========== VALIDATION HELPERS ========== //

    function _validateLifecycle(Contracts memory c) internal view {
        require(
            _kernel.isPolicyActive(Policy(address(c.config))),
            "CCIPBridgeConfig is not active"
        );
        require(
            _kernel.isPolicyActive(Policy(address(c.configTimelock))),
            "CCIPBridgeConfigTimelock is not active"
        );
        require(IEnabler(address(c.config)).isEnabled(), "CCIPBridgeConfig is not enabled");
        require(
            IEnabler(address(c.configTimelock)).isEnabled(),
            "CCIPBridgeConfigTimelock is not enabled"
        );
    }

    function _validatePoolAuthority(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired
    ) internal view {
        require(c.pool.owner() == address(c.config), "CCIPBridgeConfig does not own the pool");
        require(_pendingOwner(address(c.pool)) == address(0), "The pool has a pending owner");
        require(
            c.config.configOperator() == address(c.configTimelock),
            "CCIPBridgeConfigTimelock is not the config operator"
        );
        require(
            ICCIPLockReleaseTokenPool(address(c.pool)).getRebalancer() == c.ocgTimelock,
            "The OCG timelock is not the rebalancer"
        );
        require(
            c.pool.getRateLimitAdmin() == desired.rateLimitAdmin,
            "The native rate limit admin is not the desired value"
        );
    }

    function _validateRegistry(Contracts memory c) internal view {
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = c.registry.getTokenConfig(c.ohm);
        require(
            tokenConfig.administrator == c.ocgTimelock,
            "The OCG timelock is not the OHM administrator"
        );
        require(
            tokenConfig.pendingAdministrator == address(0),
            "The OHM administrator transfer is still pending"
        );
        require(tokenConfig.tokenPool == address(c.pool), "The registered OHM pool changed");
    }

    function _validateRoles(Contracts memory c, address proposer) internal view {
        require(c.roles.hasRole(c.ocgTimelock, ADMIN_ROLE), "The OCG timelock lost the admin role");
        require(
            c.roles.hasRole(c.daoMS, BRIDGE_ADMIN_ROLE),
            "DAO MS does not have bridge_admin role"
        );
        require(
            c.roles.hasRole(c.emergencyMS, EMERGENCY_ROLE),
            "Emergency MS lost the emergency role"
        );
        address[6] memory noRateLimiter = [
            c.daoMS,
            c.emergencyMS,
            c.ocgTimelock,
            address(c.config),
            address(c.configTimelock),
            proposer
        ];
        for (uint256 i; i < noRateLimiter.length; ++i) {
            require(
                !c.roles.hasRole(noRateLimiter[i], BRIDGE_RATE_LIMITER_ROLE),
                "bridge_rate_limiter must be unassigned at launch"
            );
        }
    }

    function _validateParameters(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired
    ) internal view {
        require(
            IGracePeriod(address(c.config)).gracePeriod() == desired.gracePeriod,
            "CCIPBridgeConfig grace period mismatch"
        );
        require(
            IGracePeriod(address(c.configTimelock)).gracePeriod() == desired.gracePeriod,
            "CCIPBridgeConfigTimelock grace period mismatch"
        );
        require(
            c.configTimelock.timelockDelay() == desired.timelockDelay,
            "CCIPBridgeConfigTimelock delay mismatch"
        );
    }

    /// @notice Reverts unless the config policy, the timelock and the pool are bound together
    ///         and the pool serves OHM.
    function _requireDeployment(Contracts memory c) internal view {
        require(c.config.pool() == address(c.pool), "CCIPBridgeConfig is bound to another pool");
        require(
            c.configTimelock.config() == address(c.config),
            "CCIPBridgeConfigTimelock is bound to another config policy"
        );
        require(
            address(Policy(address(c.config)).kernel()) == address(_kernel),
            "CCIPBridgeConfig reports another Kernel"
        );
        require(
            address(Policy(address(c.configTimelock)).kernel()) == address(_kernel),
            "CCIPBridgeConfigTimelock reports another Kernel"
        );
        require(c.config.isLiquidityContainer(), "The pool is not a liquidity container");
        require(c.pool.getToken() == c.ohm, "The pool does not serve OHM");
        require(
            _kernel.isPolicyActive(Policy(address(c.config))),
            "CCIPBridgeConfig is not active in the Kernel: run CCIPBridgeConfigBatch.prepareHandover first"
        );
        require(
            _kernel.isPolicyActive(Policy(address(c.configTimelock))),
            "CCIPBridgeConfigTimelock is not active in the Kernel: run CCIPBridgeConfigBatch.prepareHandover first"
        );
        _requireVersion(address(c.config), "CCIPBridgeConfig");
        _requireVersion(address(c.configTimelock), "CCIPBridgeConfigTimelock");
    }

    /// @notice Reverts unless the policy reports version 1.0.
    function _requireVersion(address policy_, string memory name_) internal view {
        (uint8 major, uint8 minor) = IVersioned(policy_).VERSION();
        require(major == 1 && minor == 0, string.concat(name_, " does not report version 1.0"));
    }

    /// @notice Reverts unless every route declared in `env.json` matches the pool field by
    ///         field (existence, remote token, accepted remote pools and both rate limits) and
    ///         every live route of the pool is declared as enabled in `env.json` with both
    ///         limiters enabled.
    function _requireRoutesMatchEnv(ICCIPTokenPoolAdmin pool_) internal view {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(_env, _chain());
        require(desired.length > 0, "env.json declares no CCIP route for this chain");

        // Every live route must be declared and enabled, with both limiters enabled
        uint64[] memory liveSelectors = pool_.getSupportedChains();
        for (uint256 i; i < liveSelectors.length; ++i) {
            bool declared;
            for (uint256 j; j < desired.length; ++j) {
                if (
                    desired[j].chainSelector == liveSelectors[i] &&
                    desired[j].enabled &&
                    !desired[j].remove
                ) {
                    declared = true;
                    break;
                }
            }
            require(
                declared,
                string.concat(
                    "Live route is not declared as enabled in env.json: ",
                    vm.toString(liveSelectors[i])
                )
            );
            CCIPConfigLib.LiveRoute memory liveState = CCIPConfigLib.liveRoute(
                pool_,
                liveSelectors[i]
            );
            require(
                liveState.outbound.isEnabled && liveState.inbound.isEnabled,
                string.concat(
                    "Live route carries a disabled limiter: ",
                    vm.toString(liveSelectors[i])
                )
            );
        }

        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(
                pool_,
                route.chainSelector
            );
            if (route.remove) {
                require(
                    !live.exists,
                    string.concat(
                        "Route marked for removal is still configured: ",
                        route.remoteChain
                    )
                );
                continue;
            }
            if (!route.enabled) continue;
            require(
                live.exists,
                string.concat(
                    "Route is not configured on the pool: ",
                    route.remoteChain,
                    "; apply it before the proposal (direct pool owner batch before the handover, config timelock afterwards)"
                )
            );
            require(
                !CCIPConfigLib.hasChanges(CCIPConfigLib.diffRoute(route, live)),
                string.concat(
                    "Route differs from env.json: ",
                    route.remoteChain,
                    "; reconcile it before the proposal (direct pool owner batch before the handover, config timelock afterwards)"
                )
            );
        }
    }

    // ========== INTERNAL HELPERS ========== //

    function _contracts(Addresses addresses) internal view returns (Contracts memory c) {
        c.config = ICCIPBridgeConfig(addresses.getAddress("olympus-policy-ccip-bridge-config"));
        c.configTimelock = ICCIPBridgeConfigTimelock(
            addresses.getAddress("olympus-policy-ccip-bridge-config-timelock")
        );
        c.pool = ICCIPTokenPoolAdmin(
            addresses.getAddress("olympus-periphery-ccip-lock-release-token-pool")
        );
        c.registry = ICCIPTokenAdminRegistry(
            addresses.getAddress("external-ccip-token-admin-registry")
        );
        c.roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        c.rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        c.ohm = addresses.getAddress("olympus-legacy-ohm");
        c.daoMS = addresses.getAddress("olympus-multisig-dao");
        c.emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        c.ocgTimelock = addresses.getAddress("olympus-timelock");
        c.bridge = addresses.getAddress("olympus-periphery-ccip-cross-chain-bridge");
    }

    function _pendingOwner(address pool_) internal view returns (address pending) {
        return CCIPConfigLib.pendingOwner(pool_);
    }

    function _chain() internal view returns (string memory chain) {
        return ChainUtils._getChainName(block.chainid);
    }
}

contract CCIPBridgeConfigProposalScript is ProposalScript {
    constructor() ProposalScript(new CCIPBridgeConfigProposal()) {}
}
