// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.24;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice OCG proposal that re-activates OHM bridging through Chainlink CCIP: it opens the
///         mainnet routes to Arbitrum, Optimism, Base and Berachain on the OHM token pool, and
///         moves the pool under the CCIPTokenPoolConfig policy and its CCIPTokenPoolConfigTimelock
///         and the OHM administrator position in the Chainlink TokenAdminRegistry under the OCG
///         timelock.
///
///         Every handover action is conditional on the live state, so the proposal is idempotent
///         with respect to steps that already happened. The actions read, in order:
///         accept the OHM administrator role, grant `bridge_admin` to the DAO MS, enable the
///         config policy, accept the pool ownership, set the config timelock as config operator,
///         set the OCG timelock as rebalancer, clear the native rate limit admin, enable the
///         config timelock, and add the four routes through `CCIPTokenPoolConfig.addChain`. At most
///         twelve actions, so no activator contract is needed.
///
///         The route actions come after the handover actions because `addChain` requires the
///         config policy to be enabled and to own the pool, both of which happen earlier in the
///         same execution. The gap between submission and execution is safe: until execution the
///         only party able to change the pool, the registry entry or the routes is the DAO MS
///         (the pool owner and the OHM administrator until the proposal accepts both), and any
///         interference makes the execution revert (`ChainAlreadyExists`, `MustBeProposedOwner`,
///         `OnlyPendingAdministrator`) rather than land in an unexpected state. If a route is
///         added directly before submission, the build-time check of the missing set fails
///         closed: investigate, rebuild and resubmit.
///
///         Assumes:
///         - CCIPTokenPoolConfig and CCIPTokenPoolConfigTimelock have been deployed on Ethereum
///           mainnet and recorded in `src/proposals/addresses.json` and `src/scripts/env.json`.
///         - The DAO MS has run `CCIPTokenPoolConfigBatch.prepareHandover`: both policies are
///           active in the Kernel, CCIPTokenPoolConfig is the pending owner of the pool and the OCG
///           timelock is the pending OHM administrator in the TokenAdminRegistry.
///         - The OCG timelock holds the `admin` role.
///         - The live Solana route of the pool matches `olympus.config.CCIP.routes` in
///           `src/scripts/env.json`; the exact four routes to Arbitrum, Optimism, Base and
///           Berachain are declared there and missing from the pool.
///         - The burn/mint pools of those four chains are deployed and recorded in
///           `src/scripts/env.json` (`olympus.policies.CCIPBurnMintTokenPool`), since each route
///           resolves its accepted remote pool from there unless it declares an explicit
///           `remotePools` override.
///         - The pool holds at least `olympus.config.CCIP.minimumPoolBacking` OHM (the supply
///           outstanding on the burn/mint chains; `CCIPTokenPoolBatch.fundPool`).
///         - Every mainnet lane toward the four chains carries an enabled OHM fee entry with a
///           delivery gas budget of at least 175000, obtained from Chainlink.
contract CCIPTokenPoolConfigProposal is GovernorBravoProposal {
    // ========== ERRORS ========== //

    /// @notice Thrown when an address read from the chain or from `env.json` differs from the
    ///         expected one.
    /// @param field The name of the compared field.
    /// @param actual The value read.
    /// @param expected The expected value.
    error CCIPTokenPoolConfigProposal_AddressMismatch(
        string field,
        address actual,
        address expected
    );

    /// @notice Thrown when a two-step transfer is not in the expected state: at build time the
    ///         expected value is the party that must accept (run
    ///         `CCIPTokenPoolConfigBatch.prepareHandover` first), after execution it is the zero
    ///         address.
    /// @param field The name of the transferred authority.
    /// @param pending The pending value read.
    /// @param expected The expected pending value.
    error CCIPTokenPoolConfigProposal_PendingMismatch(
        string field,
        address pending,
        address expected
    );

    /// @notice Thrown when an account does not hold a required role.
    /// @param role The role.
    /// @param account The account.
    error CCIPTokenPoolConfigProposal_MissingRole(bytes32 role, address account);

    /// @notice Thrown when an account holds a role that must be unassigned at launch.
    /// @param role The role.
    /// @param account The account.
    error CCIPTokenPoolConfigProposal_RoleNotUnassigned(bytes32 role, address account);

    /// @notice Thrown when a policy is not active in the Kernel (run
    ///         `CCIPTokenPoolConfigBatch.prepareHandover` first).
    /// @param policy The policy.
    error CCIPTokenPoolConfigProposal_PolicyNotActive(address policy);

    /// @notice Thrown when a policy is not enabled.
    /// @param policy The policy.
    error CCIPTokenPoolConfigProposal_PolicyNotEnabled(address policy);

    /// @notice Thrown when the pool does not advertise the liquidity container interface.
    /// @param pool The pool.
    error CCIPTokenPoolConfigProposal_NotLiquidityContainer(address pool);

    /// @notice Thrown when a policy does not report version 1.0.
    /// @param policy The policy.
    /// @param major The reported major version.
    /// @param minor The reported minor version.
    error CCIPTokenPoolConfigProposal_VersionMismatch(address policy, uint8 major, uint8 minor);

    /// @notice Thrown when a numeric parameter differs from the value declared in `env.json`.
    /// @param name The parameter name.
    /// @param actual The value read.
    /// @param expected The declared value.
    error CCIPTokenPoolConfigProposal_ParameterMismatch(
        string name,
        uint256 actual,
        uint256 expected
    );

    /// @notice Thrown when `env.json` declares no CCIP route for the chain.
    error CCIPTokenPoolConfigProposal_NoRoutesDeclared();

    /// @notice Thrown when a live route of the pool is not declared as enabled in `env.json`.
    /// @param chainSelector The chain selector of the route.
    error CCIPTokenPoolConfigProposal_RouteUndeclared(uint64 chainSelector);

    /// @notice Thrown when a live route carries a disabled rate limiter.
    /// @param chainSelector The chain selector of the route.
    error CCIPTokenPoolConfigProposal_RouteLimiterDisabled(uint64 chainSelector);

    /// @notice Thrown when a route declared with `enabled: false` is still configured on the
    ///         pool (remove it through `CCIPRouteReconcileBatch` before the proposal).
    /// @param remoteChain The remote chain name.
    error CCIPTokenPoolConfigProposal_RouteNotRemoved(string remoteChain);

    /// @notice Thrown when an enabled desired route is not configured on the pool after
    ///         execution.
    /// @param remoteChain The remote chain name.
    error CCIPTokenPoolConfigProposal_RouteMissing(string remoteChain);

    /// @notice Thrown when a live route differs from its `env.json` declaration (reconcile it
    ///         before the proposal: direct pool owner batch before the handover, config timelock
    ///         afterwards).
    /// @param remoteChain The remote chain name.
    error CCIPTokenPoolConfigProposal_RouteDrift(string remoteChain);

    /// @notice Thrown when a desired route missing from the pool is not one of the four chains
    ///         this proposal opens.
    /// @param remoteChain The remote chain name.
    error CCIPTokenPoolConfigProposal_UnexpectedMissingRoute(string remoteChain);

    /// @notice Thrown when the set of desired routes missing from the pool is not exactly the
    ///         four chains this proposal opens (investigate, rebuild and resubmit).
    /// @param missingCount The number of missing routes among the expected chains.
    /// @param expectedCount The number of expected chains.
    error CCIPTokenPoolConfigProposal_MissingRouteSetMismatch(
        uint256 missingCount,
        uint256 expectedCount
    );

    /// @notice Thrown when the pool holds less OHM than `olympus.config.CCIP.minimumPoolBacking`
    ///         (re-read `shell/calc_bridged_supply.sh` and run `CCIPTokenPoolBatch.fundPool`
    ///         first).
    /// @param balance The OHM balance of the pool.
    /// @param minimum The required minimum.
    error CCIPTokenPoolConfigProposal_BackingTooLow(uint256 balance, uint256 minimum);

    // ========== CONSTANTS ========== //

    string internal constant _ENV_PATH = "./src/scripts/env.json";

    /// @dev The chain selectors of the four routes this proposal opens. The build fails closed
    ///      unless the set of desired routes missing from the pool equals exactly this set.
    uint64 internal constant _ARBITRUM_SELECTOR = 4949039107694359620;
    uint64 internal constant _OPTIMISM_SELECTOR = 3734403246176062136;
    uint64 internal constant _BASE_SELECTOR = 15971525489660198786;
    uint64 internal constant _BERACHAIN_SELECTOR = 1294465214383781161;

    // ========== DATA STRUCTURES ========== //

    /// @dev The contracts and accounts the proposal acts on, resolved from the address registry.
    struct Contracts {
        ICCIPTokenPoolConfig config;
        ICCIPTokenPoolConfigTimelock configTimelock;
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

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 19;
    }

    function name() public pure override returns (string memory) {
        return "CCIP Bridge Activation";
    }

    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return string.concat(_descriptionPreamble(), _descriptionSteps());
    }

    function _descriptionPreamble() private pure returns (string memory) {
        return
            string.concat(
                "# CCIP Bridge Activation\n",
                "\n",
                "This proposal re-activates OHM bridging through Chainlink CCIP. It opens the mainnet routes to Arbitrum, Optimism, Base and Berachain on the OHM token pool, which so far serves only Solana, so that OHM can move between Ethereum and the four EVM chains through the CCIP lanes, next to the existing Ethereum-Solana route.\n",
                "\n",
                "## Justification\n",
                "\n",
                "OHM on Arbitrum, Optimism, Base and Berachain was issued by the LayerZero v1 bridge, which is closed to traffic. CCIP already carries OHM between Ethereum and Solana through the mainnet lock/release pool; opening the four routes on that pool restores bridging to every supported chain through one infrastructure, with the pool funded with the OHM outstanding on the burn/mint chains so that it can release against tokens burned there.\n",
                "\n",
                "To make the pool and its routes governable, the proposal also moves the pool and the OHM entry in the Chainlink TokenAdminRegistry, both held by the DAO MS today, under on-chain governance: the OCG timelock becomes the OHM administrator, the CCIPTokenPoolConfig policy becomes the owner of the pool, and the DAO MS keeps the `bridge_admin` role to queue route changes on the CCIPTokenPoolConfigTimelock. The complete allocation is listed under Authority Model below the proposal steps.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- Operator documentation: `documentation/bridge/ccip/RUNBOOK.md` in the olympus-v3 repository.\n",
                "- Contracts: `src/policies/bridge/CCIPTokenPoolConfig.sol`, `src/policies/bridge/CCIPTokenPoolConfigTimelock.sol`.\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- CCIPTokenPoolConfig and CCIPTokenPoolConfigTimelock have been deployed on Ethereum mainnet with a 3-day grace period and a 1-day initial timelock delay.\n",
                "- The DAO MS has activated both policies in the Kernel, proposed CCIPTokenPoolConfig as the new owner of the token pool and nominated the OCG timelock as the OHM administrator in the TokenAdminRegistry.\n",
                "- The OCG timelock holds the `admin` role.\n",
                "- The live Solana route of the pool matches the desired configuration and the four new routes are not configured yet.\n",
                "- The CCIP contracts of Arbitrum, Optimism, Base and Berachain (the burn/mint pool, its config policy, its config timelock and the periphery) have been deployed, the OHM administrator role in each local TokenAdminRegistry has been handed to the local DAO MS, and each local pool has been proposed to its config policy as the new owner.\n",
                "- The pool has been funded with at least the OHM supply outstanding on Arbitrum, Optimism, Base and Berachain, so it can release against tokens burned there.\n",
                "- Chainlink has raised the OHM delivery gas budget to at least 175,000 on every mainnet lane toward the four chains; without it every inbound transfer on those chains would fail on arrival.\n"
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
                "3. Enable the CCIPTokenPoolConfig policy.\n",
                "4. Accept the ownership of the token pool through CCIPTokenPoolConfig.\n",
                "5. Set the CCIPTokenPoolConfigTimelock as the config operator of CCIPTokenPoolConfig.\n",
                "6. Set the OCG timelock as the rebalancer of the token pool.\n",
                "7. Clear the native rate limit admin of the token pool.\n",
                "8. Enable the CCIPTokenPoolConfigTimelock policy.\n",
                "9. Add the Arbitrum route to the token pool.\n",
                "10. Add the Base route to the token pool.\n",
                "11. Add the Berachain route to the token pool.\n",
                "12. Add the Optimism route to the token pool.\n",
                "\n",
                "## Authority Model\n",
                "\n",
                "The pool and the OHM registry entry are held by the DAO MS today. After this proposal:\n",
                "\n",
                "- The OCG timelock is the OHM administrator in the TokenAdminRegistry (the authority that selects or delists the OHM pool), the `admin` of the CCIPTokenPoolConfig policy (root settings, pool ownership, router, rebalancer, rate limit admin) and the rebalancer of the lock/release pool (the only authority that can withdraw its liquidity).\n",
                "- The CCIPTokenPoolConfig policy is the owner of the token pool and exposes a typed, role-separated subset of the pool owner surface: route, remote pool, allowlist and rate limit changes are callable by the config timelock (after its delay) or directly by `admin`; containment (`disableChain`, `disableAllChains`) is callable at any time by the `emergency`, `admin`, `bridge_admin` and `bridge_rate_limiter` roles and can only reduce capacity; there is no arbitrary call forwarding.\n",
                "- The DAO MS holds `bridge_admin`: it queues typed route changes on the CCIPTokenPoolConfigTimelock, which executes them permissionlessly after a one-day delay and rejects them if the route moved in the meantime, it can contain a route or every route at any time (`disableChain`, `disableAllChains`), and it can re-enable either policy within a three-day grace window after a disable. The DAO MS keeps ownership of the user-facing CCIPCrossChainBridge periphery, which is not part of this proposal.\n",
                "\n",
                "The `bridge_rate_limiter` role, a direct rate-limit and containment path for a future monitoring operator, stays unassigned. The native pool rate limit admin stays unset so that every rate limit change passes through the policy.\n",
                "\n",
                "## Route Limits\n",
                "\n",
                "Each of the four routes (Arbitrum, Optimism, Base, Berachain) opens with independent rate limit buckets in OHM base units (9 decimals), sized from the LayerZero v2 figures with a one-day window:\n",
                "\n",
                "- Outbound (mainnet to the chain): capacity 100,000 OHM (100000000000000), refill rate 1157407407 per second.\n",
                "- Inbound (the chain to mainnet): capacity 55,000 OHM (55000000000000), refill rate 636574074 per second.\n",
                "\n",
                "The remote token of each route is the chain's OHM token and the accepted remote pool is the chain's CCIPBurnMintTokenPool policy, both read from the desired-state configuration at build time.\n",
                "\n",
                "This proposal leaves the mainnet pool fully configured. Later route changes are queued by the DAO MS on the CCIPTokenPoolConfigTimelock and executed permissionlessly after its one-day delay, or applied directly by OCG; containment stays available to the Emergency MS and to the DAO MS as `bridge_admin` through CCIPTokenPoolConfig; and the remaining root settings of the pool require an OCG proposal.\n",
                "\n",
                "## Next Steps\n",
                "\n",
                "The following are performed by the DAO MS of each chain and are not part of this proposal:\n",
                "\n",
                "- On Arbitrum, Optimism, Base and Berachain: the local CCIP contracts, including the local pool's routes to mainnet and to the other burn/mint chains (less the Optimism-Berachain pair, for which Chainlink serves no lane), are configured during the voting period, with the local pool left disabled and unregistered so that the chain stays dormant. The same batch deactivates the legacy LayerZero CrossChainBridge policy in the local Kernel, which is already closed to traffic and holds no mint approval, both asserted before the deactivation. Immediately after this proposal executes, the local DAO MS enables the local pool and registers it in the local TokenAdminRegistry, which is what opens the chain.\n",
                "- On mainnet and on those four chains: set the trusted remotes and gas limits of the CCIPCrossChainBridge periphery, and enable the four new peripheries.\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    function _build(Addresses addresses) internal override {
        Contracts memory c = _contracts(addresses);
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(
            _readEnv(),
            _chain()
        );

        // Preconditions: the deployment, the admin role, the routes, the backing, the budgets
        _requireDeployment(c);
        if (desired.rebalancer != c.ocgTimelock) {
            revert CCIPTokenPoolConfigProposal_AddressMismatch(
                "olympus.config.CCIPTokenPoolConfig.rebalancer",
                desired.rebalancer,
                c.ocgTimelock
            );
        }
        _requireRole(c.roles, ADMIN_ROLE, c.ocgTimelock);
        // The routes this proposal opens are allowed to be missing; _buildRouteActions requires
        // the missing set to be exactly the four expected chains.
        _requireRoutesMatchEnv(c.pool, false);
        _requireBackingAndFeeBudgets(c);

        // 1-2. Registry and role actions
        _buildAuthorityActions(c);
        // 3-8. Config policy and timelock actions
        _buildConfigActions(c, desired);
        // 9-12. Add the four routes, after the handover actions: addChain requires the config
        // policy to be enabled and to own the pool, both established earlier in this execution.
        _buildRouteActions(c);
    }

    /// @notice Adds the registry and role actions: accept the OHM administrator role and grant
    ///         `bridge_admin` to the DAO MS, each only if the live state requires it.
    function _buildAuthorityActions(Contracts memory c) internal {
        // 1. Accept the OHM administrator role (conditional)
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = c.registry.getTokenConfig(c.ohm);
        _requireAddress("TokenAdminRegistry pool", tokenConfig.tokenPool, address(c.pool));
        if (tokenConfig.administrator != c.ocgTimelock) {
            if (tokenConfig.pendingAdministrator != c.ocgTimelock) {
                revert CCIPTokenPoolConfigProposal_PendingMismatch(
                    "OHM administrator",
                    tokenConfig.pendingAdministrator,
                    c.ocgTimelock
                );
            }
            _pushAction(
                address(c.registry),
                abi.encodeWithSelector(ICCIPTokenAdminRegistry.acceptAdminRole.selector, c.ohm),
                "Accept the OHM administrator role in the TokenAdminRegistry"
            );
        }

        // 2. Grant bridge_admin to the DAO MS (conditional)
        if (!c.roles.hasRole(c.daoMS, BRIDGE_ADMIN_ROLE)) {
            _requireAddress("RolesAdmin admin", RolesAdmin(c.rolesAdmin).admin(), c.ocgTimelock);
            _pushAction(
                c.rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, BRIDGE_ADMIN_ROLE, c.daoMS),
                "Grant bridge_admin role to the DAO MS"
            );
        }
    }

    /// @notice Adds the config policy and timelock actions: enable the config policy, accept the
    ///         pool ownership, set the config operator, the rebalancer and the rate limit admin,
    ///         and enable the timelock, each only if the live state requires it.
    function _buildConfigActions(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired
    ) internal {
        // 3. Enable the config policy (conditional); its admin functions require it
        if (!IEnabler(address(c.config)).isEnabled()) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(IEnabler.enable.selector, ""),
                "Enable CCIPTokenPoolConfig"
            );
        }

        // 4. Accept the pool ownership (conditional)
        if (c.pool.owner() != address(c.config)) {
            address pendingOwner = _pendingOwner(address(c.pool));
            if (pendingOwner != address(c.config)) {
                revert CCIPTokenPoolConfigProposal_PendingMismatch(
                    "pool owner",
                    pendingOwner,
                    address(c.config)
                );
            }
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPTokenPoolConfig.acceptPoolOwnership.selector),
                "Accept the token pool ownership through CCIPTokenPoolConfig"
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
                "Set CCIPTokenPoolConfigTimelock as the config operator of CCIPTokenPoolConfig"
            );
        }

        // 6. Set the OCG timelock as rebalancer (conditional)
        if (ICCIPLockReleaseTokenPool(address(c.pool)).getRebalancer() != desired.rebalancer) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    ICCIPTokenPoolConfig.setRebalancer.selector,
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
                    ICCIPTokenPoolConfig.setRateLimitAdmin.selector,
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
                "Enable CCIPTokenPoolConfigTimelock"
            );
        }
    }

    /// @notice Adds one `addChain` action per desired route missing from the pool, in remote
    ///         chain name order, and requires the missing set to be exactly the four expected
    ///         chains (Arbitrum, Optimism, Base, Berachain).
    /// @dev Fails closed on any drift: a missing route outside the expected set (an undeclared
    ///      selector cannot appear here since the routes come from `env.json`, so this means the
    ///      declaration changed), or an expected route that is already configured (someone added
    ///      it directly while the DAO MS still owned the pool). Both need investigation and a
    ///      rebuild rather than a silently smaller proposal.
    function _buildRouteActions(Contracts memory c) internal {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(
            _readEnv(),
            _chain()
        );
        uint64[4] memory expected = [
            _ARBITRUM_SELECTOR,
            _OPTIMISM_SELECTOR,
            _BASE_SELECTOR,
            _BERACHAIN_SELECTOR
        ];
        bool[4] memory added;
        uint256 missingCount;

        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            if (!route.enabled) continue;
            if (CCIPConfigLib.liveRoute(c.pool, route.chainSelector).exists) continue;

            uint256 expectedIndex = type(uint256).max;
            for (uint256 j; j < expected.length; ++j) {
                if (expected[j] == route.chainSelector) {
                    expectedIndex = j;
                    break;
                }
            }
            if (expectedIndex == type(uint256).max) {
                revert CCIPTokenPoolConfigProposal_UnexpectedMissingRoute(route.remoteChain);
            }
            added[expectedIndex] = true;
            missingCount++;

            ICCIPTokenPoolAdmin.ChainUpdate memory update = ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: route.chainSelector,
                remotePoolAddresses: route.remotePools,
                remoteTokenAddress: route.remoteToken,
                outboundRateLimiterConfig: route.outbound,
                inboundRateLimiterConfig: route.inbound
            });
            // Surface the config policy's own validation at build time
            c.config.validateAddChain(update);
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPTokenPoolConfig.addChain.selector, update),
                string.concat("Add the ", route.remoteChain, " route to the token pool")
            );
        }

        if (missingCount != expected.length || !(added[0] && added[1] && added[2] && added[3])) {
            revert CCIPTokenPoolConfigProposal_MissingRouteSetMismatch(
                missingCount,
                expected.length
            );
        }
    }

    /// @notice Reverts unless the pool holds the minimum backing and every mainnet lane toward a
    ///         burn/mint destination carries the raised OHM delivery gas budget. Checked at build
    ///         time and re-checked by `_validate`.
    function _requireBackingAndFeeBudgets(Contracts memory c) internal view {
        uint256 minBacking = CCIPConfigLib.minimumPoolBacking(_readEnv(), _chain());
        uint256 poolBalance = IERC20(c.ohm).balanceOf(address(c.pool));
        if (poolBalance < minBacking) {
            revert CCIPTokenPoolConfigProposal_BackingTooLow(poolBalance, minBacking);
        }

        string memory env = _readEnv();
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, _chain());
        for (uint256 i; i < desired.length; ++i) {
            if (!desired[i].enabled) continue;
            if (!CCIPConfigLib.isBurnMintEvmChain(desired[i].remoteChain)) continue;
            CCIPFeeBudgetLib.requireOhmFeeBudget(env, _chain(), desired[i].remoteChain);
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
        CCIPConfigLib.DesiredConfig memory desired = CCIPConfigLib.desiredConfig(
            _readEnv(),
            _chain()
        );

        _requireDeployment(c);
        _validateLifecycle(c);
        _validatePoolAuthority(c, desired);
        _validateRegistry(c);
        _validateRoles(c, addresses.getAddress("proposer"));
        _validateParameters(c, desired);
        _requireRoutesMatchEnv(c.pool, true);
        _requireBackingAndFeeBudgets(c);

        // The periphery is untouched
        _requireAddress("CCIPCrossChainBridge owner", Owned(c.bridge).owner(), c.daoMS);
    }

    // ========== VALIDATION HELPERS ========== //

    function _validateLifecycle(Contracts memory c) internal view {
        _requireActive(address(c.config));
        _requireActive(address(c.configTimelock));
        _requireEnabled(address(c.config));
        _requireEnabled(address(c.configTimelock));
    }

    function _validatePoolAuthority(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired
    ) internal view {
        _requireAddress("pool owner", c.pool.owner(), address(c.config));
        address pendingOwner = _pendingOwner(address(c.pool));
        if (pendingOwner != address(0)) {
            revert CCIPTokenPoolConfigProposal_PendingMismatch(
                "pool owner",
                pendingOwner,
                address(0)
            );
        }
        _requireAddress("config operator", c.config.configOperator(), address(c.configTimelock));
        _requireAddress(
            "pool rebalancer",
            ICCIPLockReleaseTokenPool(address(c.pool)).getRebalancer(),
            c.ocgTimelock
        );
        _requireAddress(
            "pool rate limit admin",
            c.pool.getRateLimitAdmin(),
            desired.rateLimitAdmin
        );
    }

    function _validateRegistry(Contracts memory c) internal view {
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = c.registry.getTokenConfig(c.ohm);
        _requireAddress("OHM administrator", tokenConfig.administrator, c.ocgTimelock);
        if (tokenConfig.pendingAdministrator != address(0)) {
            revert CCIPTokenPoolConfigProposal_PendingMismatch(
                "OHM administrator",
                tokenConfig.pendingAdministrator,
                address(0)
            );
        }
        _requireAddress("TokenAdminRegistry pool", tokenConfig.tokenPool, address(c.pool));
    }

    function _validateRoles(Contracts memory c, address proposer) internal view {
        _requireRole(c.roles, ADMIN_ROLE, c.ocgTimelock);
        _requireRole(c.roles, BRIDGE_ADMIN_ROLE, c.daoMS);
        _requireRole(c.roles, EMERGENCY_ROLE, c.emergencyMS);
        // ROLES keeps no enumeration of role holders, so only known addresses can be sampled
        // here; the guarantee that bridge_rate_limiter is unassigned anywhere is procedural:
        // this proposal grants it to nobody and no prior grant is recorded.
        address[6] memory noRateLimiter = [
            c.daoMS,
            c.emergencyMS,
            c.ocgTimelock,
            address(c.config),
            address(c.configTimelock),
            proposer
        ];
        for (uint256 i; i < noRateLimiter.length; ++i) {
            if (c.roles.hasRole(noRateLimiter[i], BRIDGE_RATE_LIMITER_ROLE)) {
                revert CCIPTokenPoolConfigProposal_RoleNotUnassigned(
                    BRIDGE_RATE_LIMITER_ROLE,
                    noRateLimiter[i]
                );
            }
        }
    }

    function _validateParameters(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired
    ) internal view {
        _requireParameter(
            "CCIPTokenPoolConfig grace period",
            IGracePeriod(address(c.config)).gracePeriod(),
            desired.gracePeriod
        );
        _requireParameter(
            "CCIPTokenPoolConfigTimelock grace period",
            IGracePeriod(address(c.configTimelock)).gracePeriod(),
            desired.gracePeriod
        );
        _requireParameter(
            "CCIPTokenPoolConfigTimelock delay",
            c.configTimelock.timelockDelay(),
            desired.timelockDelay
        );
    }

    /// @notice Reverts unless the config policy, the timelock and the pool are bound together
    ///         and the pool serves OHM.
    function _requireDeployment(Contracts memory c) internal view {
        _requireAddress("CCIPTokenPoolConfig pool", c.config.pool(), address(c.pool));
        _requireAddress(
            "CCIPTokenPoolConfigTimelock config",
            c.configTimelock.config(),
            address(c.config)
        );
        _requireAddress(
            "CCIPTokenPoolConfig kernel",
            address(Policy(address(c.config)).kernel()),
            address(_kernel)
        );
        _requireAddress(
            "CCIPTokenPoolConfigTimelock kernel",
            address(Policy(address(c.configTimelock)).kernel()),
            address(_kernel)
        );
        if (!c.config.isLiquidityContainer()) {
            revert CCIPTokenPoolConfigProposal_NotLiquidityContainer(address(c.pool));
        }
        _requireAddress("pool token", c.pool.getToken(), c.ohm);
        _requireActive(address(c.config));
        _requireActive(address(c.configTimelock));
        _requireVersion(address(c.config));
        _requireVersion(address(c.configTimelock));
    }

    /// @notice Reverts unless the policy reports version 1.0.
    function _requireVersion(address policy_) internal view {
        (uint8 major, uint8 minor) = IVersioned(policy_).VERSION();
        if (major != 1 || minor != 0) {
            revert CCIPTokenPoolConfigProposal_VersionMismatch(policy_, major, minor);
        }
    }

    /// @notice Reverts unless the policy is active in the Kernel.
    function _requireActive(address policy_) internal view {
        if (!_kernel.isPolicyActive(Policy(policy_))) {
            revert CCIPTokenPoolConfigProposal_PolicyNotActive(policy_);
        }
    }

    /// @notice Reverts unless the policy is enabled.
    function _requireEnabled(address policy_) internal view {
        if (!IEnabler(policy_).isEnabled())
            revert CCIPTokenPoolConfigProposal_PolicyNotEnabled(policy_);
    }

    /// @notice Reverts unless the account holds the role.
    function _requireRole(ROLESv1 roles_, bytes32 role_, address account_) internal view {
        if (!roles_.hasRole(account_, role_))
            revert CCIPTokenPoolConfigProposal_MissingRole(role_, account_);
    }

    /// @notice Reverts unless the read address equals the expected one.
    function _requireAddress(
        string memory field_,
        address actual_,
        address expected_
    ) internal pure {
        if (actual_ != expected_)
            revert CCIPTokenPoolConfigProposal_AddressMismatch(field_, actual_, expected_);
    }

    /// @notice Reverts unless the read parameter equals the declared one.
    function _requireParameter(
        string memory name_,
        uint256 actual_,
        uint256 expected_
    ) internal pure {
        if (actual_ != expected_)
            revert CCIPTokenPoolConfigProposal_ParameterMismatch(name_, actual_, expected_);
    }

    /// @notice Reverts unless every route declared in `env.json` matches the pool field by
    ///         field (existence, remote token, accepted remote pools and both rate limits),
    ///         every live route of the pool is declared as enabled in `env.json` with both
    ///         limiters enabled, and every route declared with `enabled: false` (the removal
    ///         marker) is absent from the pool.
    /// @param requireDesiredLive_ Whether a desired enabled route missing from the pool reverts.
    ///        The build passes false and requires the missing set to equal the four expected
    ///        chains instead; the post-execution validation passes true.
    function _requireRoutesMatchEnv(
        ICCIPTokenPoolAdmin pool_,
        bool requireDesiredLive_
    ) internal view {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(
            _readEnv(),
            _chain()
        );
        if (desired.length == 0) revert CCIPTokenPoolConfigProposal_NoRoutesDeclared();

        _requireLiveRoutesDeclared(pool_, desired);
        _requireDesiredRoutesConverged(pool_, desired, requireDesiredLive_);
    }

    /// @notice Reverts unless every live route of the pool is declared as enabled in `env.json`
    ///         with both limiters enabled.
    function _requireLiveRoutesDeclared(
        ICCIPTokenPoolAdmin pool_,
        CCIPConfigLib.DesiredRoute[] memory desired
    ) internal view {
        uint64[] memory liveSelectors = pool_.getSupportedChains();
        for (uint256 i; i < liveSelectors.length; ++i) {
            bool declared;
            for (uint256 j; j < desired.length; ++j) {
                if (desired[j].chainSelector == liveSelectors[i] && desired[j].enabled) {
                    declared = true;
                    break;
                }
            }
            if (!declared) revert CCIPTokenPoolConfigProposal_RouteUndeclared(liveSelectors[i]);
            CCIPConfigLib.LiveRoute memory liveState = CCIPConfigLib.liveRoute(
                pool_,
                liveSelectors[i]
            );
            if (!liveState.outbound.isEnabled || !liveState.inbound.isEnabled) {
                revert CCIPTokenPoolConfigProposal_RouteLimiterDisabled(liveSelectors[i]);
            }
        }
    }

    /// @notice Reverts unless every desired route matches the pool: a route declared with
    ///         `enabled: false` is absent, an enabled route is present (when required) and
    ///         matches field by field.
    function _requireDesiredRoutesConverged(
        ICCIPTokenPoolAdmin pool_,
        CCIPConfigLib.DesiredRoute[] memory desired,
        bool requireDesiredLive_
    ) internal view {
        for (uint256 i; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(
                pool_,
                route.chainSelector
            );
            if (!route.enabled) {
                if (live.exists)
                    revert CCIPTokenPoolConfigProposal_RouteNotRemoved(route.remoteChain);
                continue;
            }
            if (!live.exists) {
                if (requireDesiredLive_)
                    revert CCIPTokenPoolConfigProposal_RouteMissing(route.remoteChain);
                continue;
            }
            if (CCIPConfigLib.hasChanges(CCIPConfigLib.diffRoute(route, live))) {
                revert CCIPTokenPoolConfigProposal_RouteDrift(route.remoteChain);
            }
        }
    }

    // ========== INTERNAL HELPERS ========== //

    function _contracts(Addresses addresses) internal view returns (Contracts memory c) {
        c.config = ICCIPTokenPoolConfig(
            addresses.getAddress("olympus-policy-ccip-token-pool-config")
        );
        c.configTimelock = ICCIPTokenPoolConfigTimelock(
            addresses.getAddress("olympus-policy-ccip-token-pool-config-timelock")
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

    /// @notice Reads `env.json`, the desired-state source that the proposal validates the
    ///         deployment and the routes against.
    /// @dev Read from disk on every use rather than cached in storage: `run` executes as one
    ///      isolated transaction under the block gas limit, and storing the file would spend most
    ///      of it.
    function _readEnv() internal view returns (string memory env) {
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        return vm.readFile(_ENV_PATH);
    }

    function _chain() internal view returns (string memory chain) {
        return ChainUtils._getChainName(block.chainid);
    }
}

contract CCIPTokenPoolConfigProposalScript is ProposalScript {
    constructor() ProposalScript(new CCIPTokenPoolConfigProposal()) {}
}
