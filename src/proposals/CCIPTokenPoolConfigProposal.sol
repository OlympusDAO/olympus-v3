// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.24;

// Proposal code, run off-chain by forge to build and check the proposal: calls in loops are
// simulated rather than paid for on-chain, and a failed check is meant to abort the run.
// forge-lint: disable-start(calls-loop,require-revert-in-loop)

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
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ICCIPTokenPoolConfigProposalChecker} from "src/proposals/interfaces/ICCIPTokenPoolConfigProposalChecker.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CCIPTokenPoolConfigProposalChecker} from "src/proposals/CCIPTokenPoolConfigProposalChecker.sol";

// The proposal and the script that submits it share one file, like the other proposals here
// forge-lint: disable-start(multi-contract-file)

/// @notice OCG proposal that re-activates OHM bridging through Chainlink CCIP: it opens the
///         mainnet routes to Arbitrum, Optimism, Base, Berachain and Robinhood Chain on the OHM
///         token pool, and moves the pool under the CCIPTokenPoolConfig policy and its CCIPTokenPoolConfigTimelock
///         and the OHM administrator position in the Chainlink TokenAdminRegistry under the OCG
///         timelock.
///
///         The first action calls the deployed CCIPTokenPoolConfigProposalChecker, a read-only
///         contract that asserts at execution time what the build read: the precondition of
///         each handover action the proposal includes, the end state of each handover action
///         the live state already satisfies, the absence of the five routes from the pool and
///         the minimum backing of the pool. Every handover action is conditional on the live
///         state, so the proposal is idempotent with respect to steps that had already happened
///         when it was built; a step that happens between the build and the execution fails
///         the first action instead. The actions read, in order: check the preconditions,
///         accept the OHM administrator
///         role, grant `bridge_admin` to the DAO MS, enable the config policy, accept the pool
///         ownership, set the config timelock as config operator, set the OCG timelock as
///         rebalancer, clear the native rate limit admin, enable the config timelock, and add
///         the five routes through `CCIPTokenPoolConfig.addChain`. At most fourteen actions, so
///         no activator contract is needed.
///
///         The route actions come after the handover actions because `addChain` requires the
///         config policy to be enabled and to own the pool, both of which happen earlier in the
///         same execution. The gap between submission and execution is covered by the checker:
///         until execution the only party able to change the pool, the registry entry or the
///         routes is the DAO MS (the pool owner, the pool rebalancer and the OHM administrator
///         until the proposal accepts both transfers), and a change that invalidates an action
///         or lowers the backing below the minimum makes the first action revert with a named
///         error, so no handover action runs. The one change the checker cannot see is a
///         repointed pending pool owner, since the pool exposes no read of it; that case
///         reverts at the acceptance action with `MustBeProposedOwner`. If a route is added
///         directly before submission, the build-time check of the missing set fails closed:
///         investigate, rebuild and resubmit.
///
///         Assumes:
///         - CCIPTokenPoolConfig, CCIPTokenPoolConfigTimelock and
///           CCIPTokenPoolConfigProposalChecker have been deployed on Ethereum mainnet and
///           recorded in `src/proposals/addresses.json` and `src/scripts/env.json`.
///         - The DAO MS has run `CCIPTokenPoolConfigBatch.prepareHandover`: both policies are
///           active in the Kernel, CCIPTokenPoolConfig is the pending owner of the pool and the OCG
///           timelock is the pending OHM administrator in the TokenAdminRegistry.
///         - The OCG timelock holds the `admin` role.
///         - The live Solana route of the pool matches `olympus.config.CCIP.routes` in
///           `src/scripts/env.json`; the exact five routes to Arbitrum, Optimism, Base,
///           Berachain and Robinhood Chain are declared there and missing from the pool.
///         - The burn/mint pools of those five chains are deployed and recorded in
///           `src/scripts/env.json` (`olympus.policies.CCIPBurnMintTokenPool`), since each route
///           resolves its accepted remote pool from there unless it declares an explicit
///           `remotePools` override; so is the OHM of Robinhood Chain (`olympus.legacy.OHM`),
///           the default remote token of its route, which the tracked file records as the zero
///           address until it is deployed.
///         - The pool holds at least `olympus.config.CCIP.minimumPoolBacking` OHM (the supply
///           outstanding on the burn/mint chains; `CCIPTokenPoolBatch.fundPool`).
///         - Every mainnet lane toward the five chains carries an enabled OHM fee entry with a
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

    /// @notice Thrown when a desired route missing from the pool is not one of the five chains
    ///         this proposal opens.
    /// @param remoteChain The remote chain name.
    error CCIPTokenPoolConfigProposal_UnexpectedMissingRoute(string remoteChain);

    /// @notice Thrown when the set of desired routes missing from the pool is not exactly the
    ///         five chains this proposal opens (investigate, rebuild and resubmit).
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

    /// @dev The chain selectors of the five routes this proposal opens. The build fails closed
    ///      unless the set of desired routes missing from the pool equals exactly this set.
    uint256 internal constant _EXPECTED_ROUTE_COUNT = 5;
    uint64 internal constant _ARBITRUM_SELECTOR = 4949039107694359620;
    uint64 internal constant _OPTIMISM_SELECTOR = 3734403246176062136;
    uint64 internal constant _BASE_SELECTOR = 15971525489660198786;
    uint64 internal constant _BERACHAIN_SELECTOR = 1294465214383781161;
    uint64 internal constant _ROBINHOOD_SELECTOR = 6180753054346818345;

    // ========== DATA STRUCTURES ========== //

    /// @dev The contracts and accounts the proposal acts on, resolved from the address registry.
    struct Contracts {
        ICCIPTokenPoolConfig config;
        ICCIPTokenPoolConfigTimelock configTimelock;
        CCIPTokenPoolConfigProposalChecker checker;
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
                "This proposal re-activates OHM bridging through Chainlink CCIP. It opens the mainnet routes to Arbitrum, Optimism, Base, Berachain and Robinhood Chain on the OHM token pool, which so far serves only Solana, so that OHM can move between Ethereum and the five EVM chains through the CCIP lanes, next to the existing Ethereum-Solana route.\n",
                "\n",
                "## Justification\n",
                "\n",
                "OHM on Arbitrum, Optimism, Base and Berachain was issued by the LayerZero v1 bridge, which is closed to traffic. Robinhood Chain joins as a fifth burn/mint chain: it carries no OHM yet, and its supply is minted only by CCIP deliveries, from Ethereum against OHM locked in the mainnet pool or from Arbitrum and Base against OHM burned there. CCIP already carries OHM between Ethereum and Solana through the mainnet lock/release pool; opening the five routes on that pool restores bridging to every supported chain through one infrastructure, with the pool funded with the OHM outstanding on the burn/mint chains so that it can release against tokens burned there.\n",
                "\n",
                "To make the pool and its routes governable, the proposal also moves the pool and the OHM entry in the Chainlink TokenAdminRegistry, both held by the DAO MS today, under on-chain governance: the OCG timelock becomes the OHM administrator, the CCIPTokenPoolConfig policy becomes the owner of the pool, and the DAO MS keeps the `bridge_admin` role to queue route changes on the CCIPTokenPoolConfigTimelock. The complete allocation is listed under Authority Model below the proposal steps.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- Operator documentation: `documentation/bridge/ccip/RUNBOOK.md` in the olympus-v3 repository.\n",
                "- Contracts: `src/policies/bridge/CCIPTokenPoolConfig.sol`, `src/policies/bridge/CCIPTokenPoolConfigTimelock.sol`.\n",
                "- Audit report: [Cyfrin CCIP audit report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2026-10-16-cyfrin-olympus-ccip-exp-v2.0.pdf).\n",
                "- CCIP bridging implementation: [PR #338: CCIP Bridging](https://github.com/OlympusDAO/olympus-v3/pull/338).\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- CCIPTokenPoolConfig and CCIPTokenPoolConfigTimelock have been deployed on Ethereum mainnet with a 3-day grace period and a 1-day initial timelock delay, together with CCIPTokenPoolConfigProposalChecker, the read-only contract that the first step calls.\n",
                "- The DAO MS has activated both policies in the Kernel, proposed CCIPTokenPoolConfig as the new owner of the token pool and nominated the OCG timelock as the OHM administrator in the TokenAdminRegistry.\n",
                "- The OCG timelock holds the `admin` role.\n",
                "- The live Solana route of the pool matches the desired configuration and the five new routes are not configured yet.\n",
                "- The CCIP contracts of Arbitrum, Optimism, Base, Berachain and Robinhood Chain (the burn/mint pool, its config policy, its config timelock and the periphery) have been deployed, the OHM administrator role in each local TokenAdminRegistry is held by the local DAO MS, and each local pool has been proposed to its config policy as the new owner.\n",
                "- The pool has been funded with at least the OHM supply outstanding on Arbitrum, Optimism, Base and Berachain (Robinhood Chain holds none yet), so it can release against tokens burned there.\n",
                "- Chainlink has raised the OHM delivery gas budget to at least 175,000 on every mainnet lane toward the five chains; without it every inbound transfer on those chains would fail on arrival.\n"
            );
    }

    function _descriptionSteps() private pure returns (string memory) {
        return
            string.concat(
                "\n",
                "## Proposal Steps\n",
                "\n",
                "The first step is always included; each later step is included only if the live state requires it.\n",
                "\n",
                "1. Call CCIPTokenPoolConfigProposalChecker, a read-only contract that reverts unless the state the later steps rely on still holds at execution: the precondition of each step included, the end state of each step not included, none of the five routes configured on the pool yet, and the pool holding at least the minimum backing. The pool exposes no read of its pending owner, so the precondition of step 5 is its current owner. A revert here fails the whole proposal before any other step runs.\n",
                "2. Accept the OHM administrator role in the Chainlink TokenAdminRegistry. The registered OHM pool is not changed.\n",
                "3. Grant the `bridge_admin` role to the DAO MS.\n",
                "4. Enable the CCIPTokenPoolConfig policy.\n",
                "5. Accept the ownership of the token pool through CCIPTokenPoolConfig.\n",
                "6. Set the CCIPTokenPoolConfigTimelock as the config operator of CCIPTokenPoolConfig.\n",
                "7. Set the OCG timelock as the rebalancer of the token pool.\n",
                "8. Clear the native rate limit admin of the token pool.\n",
                "9. Enable the CCIPTokenPoolConfigTimelock policy.\n",
                "10. Add the Arbitrum route to the token pool.\n",
                "11. Add the Base route to the token pool.\n",
                "12. Add the Berachain route to the token pool.\n",
                "13. Add the Optimism route to the token pool.\n",
                "14. Add the Robinhood Chain route to the token pool.\n",
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
                "Each of the five routes (Arbitrum, Optimism, Base, Berachain, Robinhood Chain) opens with independent rate limit buckets in OHM base units (9 decimals) with a one-day window. The figures of the four LayerZero chains are sized from the LayerZero v2 figures; Robinhood Chain has no LayerZero history, so its route takes the same figures as the other four:\n",
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
                "- On Arbitrum, Optimism, Base, Berachain and Robinhood Chain: the local CCIP contracts, including the local pool's routes to mainnet and to the other burn/mint chains (less the pairs for which Chainlink serves no lane: Optimism-Berachain, Robinhood-Optimism and Robinhood-Berachain), are configured during the voting period, with the local pool left disabled and unregistered so that the chain stays dormant. On the four LayerZero chains the same batch deactivates the legacy LayerZero CrossChainBridge policy in the local Kernel, which is already closed to traffic and holds no mint approval, both asserted before the deactivation. Immediately after this proposal executes, the local DAO MS enables the local pool and registers it in the local TokenAdminRegistry, which is what opens the chain toward mainnet and the other burn/mint chains.\n",
                "- On mainnet and on those five chains: set the trusted remotes and gas limits of the CCIPCrossChainBridge periphery, and enable the five new peripheries.\n",
                "\n",
                "The routes between Solana and the five chains are not part of this rollout. The existing Ethereum-Solana route is unchanged.\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

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
        // The routes this proposal opens are allowed to be missing; _missingRoutes requires
        // the missing set to be exactly the five expected chains.
        _requireRoutesMatchEnv(c.pool, false);
        uint256 minBacking = _minimumPoolBacking();
        _requireBackingAndFeeBudgets(c, minBacking);

        // The expectations of the checker are the record of the live reads that decide each
        // conditional action, so they are read first and the actions follow them.
        ICCIPTokenPoolConfigProposalChecker.Expectations memory expectations = _expectations(
            c,
            desired,
            minBacking
        );
        (
            ICCIPTokenPoolAdmin.ChainUpdate[] memory routeUpdates,
            string[] memory routeNames
        ) = _missingRoutes(c);
        expectations.routesToAdd = _selectorsOf(routeUpdates);
        // The checker accepts the state the build read, so a successful build is one whose
        // first action passes on that state
        c.checker.check(expectations);

        // 1. The checker call, before every other action: it asserts the expectations at
        // execution time and fails the proposal with a named error when one no longer holds.
        _pushAction(
            address(c.checker),
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker.check.selector,
                expectations
            ),
            "Check the handover preconditions and the pool backing on chain"
        );
        // 2-3. Registry and role actions
        _pushAuthorityActions(c, expectations);
        // 4-9. Config policy and timelock actions
        _pushConfigActions(c, expectations);
        // 10-14. Add the five routes, after the handover actions: addChain requires the config
        // policy to be enabled and to own the pool, both established earlier in this execution.
        _pushRouteActions(c, routeUpdates, routeNames);
    }

    /// @notice Reads the live state that decides each conditional handover action and records
    ///         the decisions as the expectations of the checker: for each action, whether it is
    ///         included, which the checker turns into the precondition the action needs or the
    ///         end state the action would have left.
    /// @dev    Reverts with `PendingMismatch` when a two-step transfer is neither completed nor
    ///         pending to the right party, and with `AddressMismatch` when the registry does
    ///         not register the pool, when the pool ownership is to be accepted but the DAO MS
    ///         does not own the pool, or when the grant of `bridge_admin` is needed but the OCG
    ///         timelock does not administer RolesAdmin. The route selectors are filled by the
    ///         caller from `_missingRoutes`.
    function _expectations(
        Contracts memory c,
        CCIPConfigLib.DesiredConfig memory desired,
        uint256 minBacking_
    ) internal view returns (ICCIPTokenPoolConfigProposalChecker.Expectations memory e) {
        // The OHM administrator role (conditional)
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = c.registry.getTokenConfig(c.ohm);
        _requireAddress("TokenAdminRegistry pool", tokenConfig.tokenPool, address(c.pool));
        e.acceptAdminRole = tokenConfig.administrator != c.ocgTimelock;
        if (e.acceptAdminRole && tokenConfig.pendingAdministrator != c.ocgTimelock) {
            revert CCIPTokenPoolConfigProposal_PendingMismatch(
                "OHM administrator",
                tokenConfig.pendingAdministrator,
                c.ocgTimelock
            );
        }

        // bridge_admin for the DAO MS (conditional)
        e.grantBridgeAdmin = !c.roles.hasRole(c.daoMS, BRIDGE_ADMIN_ROLE);
        if (e.grantBridgeAdmin) {
            _requireAddress("RolesAdmin admin", RolesAdmin(c.rolesAdmin).admin(), c.ocgTimelock);
        }

        // The config policy lifecycle (conditional); its admin functions require it enabled
        e.enableConfig = !IEnabler(address(c.config)).isEnabled();

        // The pool ownership (conditional): the acceptance needs the DAO MS to own the pool and
        // the config policy to be its pending owner
        e.acceptPoolOwnership = c.pool.owner() != address(c.config);
        if (e.acceptPoolOwnership) {
            _requireAddress("pool owner", c.pool.owner(), c.daoMS);
            address pendingOwner = _pendingOwner(address(c.pool));
            if (pendingOwner != address(c.config)) {
                revert CCIPTokenPoolConfigProposal_PendingMismatch(
                    "pool owner",
                    pendingOwner,
                    address(c.config)
                );
            }
        }

        // The config operator, the rebalancer and the rate limit admin (conditional): the config
        // policy rejects a setter call that carries the value already held
        e.setConfigOperator =
            IConfigOperator(address(c.config)).configOperator() != address(c.configTimelock);
        e.rebalancer = desired.rebalancer;
        e.setRebalancer =
            ICCIPLockReleaseTokenPool(address(c.pool)).getRebalancer() != desired.rebalancer;
        e.rateLimitAdmin = desired.rateLimitAdmin;
        e.setRateLimitAdmin = c.pool.getRateLimitAdmin() != desired.rateLimitAdmin;

        // The config timelock lifecycle (conditional)
        e.enableTimelock = !IEnabler(address(c.configTimelock)).isEnabled();

        e.minimumPoolBacking = minBacking_;
    }

    /// @notice Adds the registry and role actions the expectations include: accept the OHM
    ///         administrator role and grant `bridge_admin` to the DAO MS.
    function _pushAuthorityActions(
        Contracts memory c,
        ICCIPTokenPoolConfigProposalChecker.Expectations memory e
    ) internal {
        // 2. Accept the OHM administrator role (conditional)
        if (e.acceptAdminRole) {
            _pushAction(
                address(c.registry),
                abi.encodeWithSelector(ICCIPTokenAdminRegistry.acceptAdminRole.selector, c.ohm),
                "Accept the OHM administrator role in the TokenAdminRegistry"
            );
        }

        // 3. Grant bridge_admin to the DAO MS (conditional)
        if (e.grantBridgeAdmin) {
            _pushAction(
                c.rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, BRIDGE_ADMIN_ROLE, c.daoMS),
                "Grant bridge_admin role to the DAO MS"
            );
        }
    }

    /// @notice Adds the config policy and timelock actions the expectations include: enable the
    ///         config policy, accept the pool ownership, set the config operator, the rebalancer
    ///         and the rate limit admin, and enable the timelock.
    function _pushConfigActions(
        Contracts memory c,
        ICCIPTokenPoolConfigProposalChecker.Expectations memory e
    ) internal {
        // 4. Enable the config policy (conditional); its admin functions require it
        if (e.enableConfig) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(IEnabler.enable.selector, ""),
                "Enable CCIPTokenPoolConfig"
            );
        }

        // 5. Accept the pool ownership (conditional)
        if (e.acceptPoolOwnership) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPTokenPoolConfig.acceptPoolOwnership.selector),
                "Accept the token pool ownership through CCIPTokenPoolConfig"
            );
        }

        // 6. Set the config timelock as config operator (conditional)
        if (e.setConfigOperator) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    IConfigOperator.setConfigOperator.selector,
                    address(c.configTimelock)
                ),
                "Set CCIPTokenPoolConfigTimelock as the config operator of CCIPTokenPoolConfig"
            );
        }

        // 7. Set the OCG timelock as rebalancer (conditional)
        if (e.setRebalancer) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPTokenPoolConfig.setRebalancer.selector, e.rebalancer),
                "Set the OCG timelock as the rebalancer of the token pool"
            );
        }

        // 8. Clear the native rate limit admin (conditional)
        if (e.setRateLimitAdmin) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(
                    ICCIPTokenPoolConfig.setRateLimitAdmin.selector,
                    e.rateLimitAdmin
                ),
                "Set the native rate limit admin of the token pool"
            );
        }

        // 9. Enable the config timelock (conditional)
        if (e.enableTimelock) {
            _pushAction(
                address(c.configTimelock),
                abi.encodeWithSelector(IEnabler.enable.selector, ""),
                "Enable CCIPTokenPoolConfigTimelock"
            );
        }
    }

    /// @notice Returns one `addChain` update per desired route missing from the pool, in remote
    ///         chain name order with the remote chain names alongside, and requires the missing
    ///         set to be exactly the five expected chains (Arbitrum, Optimism, Base, Berachain,
    ///         Robinhood Chain).
    ///         Each update passes the config policy's own validation.
    /// @dev Fails closed on any drift: a missing route outside the expected set (an undeclared
    ///      selector cannot appear here since the routes come from `env.json`, so this means the
    ///      declaration changed), or an expected route that is already configured (someone added
    ///      it directly while the DAO MS still owned the pool). Both need investigation and a
    ///      rebuild rather than a silently smaller proposal.
    function _missingRoutes(
        Contracts memory c
    )
        internal
        view
        returns (ICCIPTokenPoolAdmin.ChainUpdate[] memory updates, string[] memory names)
    {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(
            _readEnv(),
            _chain()
        );
        uint64[_EXPECTED_ROUTE_COUNT] memory expected = [
            _ARBITRUM_SELECTOR,
            _OPTIMISM_SELECTOR,
            _BASE_SELECTOR,
            _BERACHAIN_SELECTOR,
            _ROBINHOOD_SELECTOR
        ];
        bool[_EXPECTED_ROUTE_COUNT] memory added;
        ICCIPTokenPoolAdmin.ChainUpdate[] memory buffer = new ICCIPTokenPoolAdmin.ChainUpdate[](
            desired.length
        );
        string[] memory bufferNames = new string[](desired.length);
        uint256 missingCount = 0;

        for (uint256 i = 0; i < desired.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = desired[i];
            if (!route.enabled) continue;
            if (CCIPConfigLib.liveRoute(c.pool, route.chainSelector).exists) continue;

            uint256 expectedIndex = type(uint256).max;
            for (uint256 j = 0; j < expected.length; ++j) {
                if (expected[j] == route.chainSelector) {
                    expectedIndex = j;
                    break;
                }
            }
            if (expectedIndex == type(uint256).max) {
                revert CCIPTokenPoolConfigProposal_UnexpectedMissingRoute(route.remoteChain);
            }
            added[expectedIndex] = true;

            ICCIPTokenPoolAdmin.ChainUpdate memory update = ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: route.chainSelector,
                remotePoolAddresses: route.remotePools,
                remoteTokenAddress: route.remoteToken,
                outboundRateLimiterConfig: route.outbound,
                inboundRateLimiterConfig: route.inbound
            });
            // Surface the config policy's own validation at build time
            c.config.validateAddChain(update);
            buffer[missingCount] = update;
            bufferNames[missingCount] = route.remoteChain;
            missingCount++;
        }

        if (
            missingCount != expected.length ||
            !(added[0] && added[1] && added[2] && added[3] && added[4])
        ) {
            revert CCIPTokenPoolConfigProposal_MissingRouteSetMismatch(
                missingCount,
                expected.length
            );
        }

        updates = new ICCIPTokenPoolAdmin.ChainUpdate[](missingCount);
        names = new string[](missingCount);
        for (uint256 i = 0; i < missingCount; ++i) {
            updates[i] = buffer[i];
            names[i] = bufferNames[i];
        }
    }

    /// @notice Adds one `addChain` action per route update, in the order given.
    function _pushRouteActions(
        Contracts memory c,
        ICCIPTokenPoolAdmin.ChainUpdate[] memory updates,
        string[] memory names
    ) internal {
        // 10-14. Add the routes
        for (uint256 i = 0; i < updates.length; ++i) {
            _pushAction(
                address(c.config),
                abi.encodeWithSelector(ICCIPTokenPoolConfig.addChain.selector, updates[i]),
                string.concat("Add the ", names[i], " route to the token pool")
            );
        }
    }

    /// @notice The chain selectors of the route updates, in the same order.
    function _selectorsOf(
        ICCIPTokenPoolAdmin.ChainUpdate[] memory updates
    ) internal pure returns (uint64[] memory selectors) {
        selectors = new uint64[](updates.length);
        for (uint256 i = 0; i < updates.length; ++i) {
            selectors[i] = updates[i].remoteChainSelector;
        }
    }

    /// @notice The expectations of the end state the proposal leaves: no handover action
    ///         included, no route to add, the declared rebalancer, rate limit admin and
    ///         minimum backing.
    function _endStateExpectations(
        CCIPConfigLib.DesiredConfig memory desired,
        uint256 minBacking_
    ) internal pure returns (ICCIPTokenPoolConfigProposalChecker.Expectations memory e) {
        e.rebalancer = desired.rebalancer;
        e.rateLimitAdmin = desired.rateLimitAdmin;
        e.routesToAdd = new uint64[](0);
        e.minimumPoolBacking = minBacking_;
    }

    /// @notice Reads `olympus.config.CCIP.minimumPoolBacking` of the chain.
    function _minimumPoolBacking() internal view returns (uint256 minBacking) {
        return CCIPConfigLib.minimumPoolBacking(_readEnv(), _chain());
    }

    /// @notice Reverts unless the pool holds the minimum backing and every mainnet lane toward a
    ///         burn/mint destination carries the raised OHM delivery gas budget. Checked at build
    ///         time and re-checked by `_validate`.
    function _requireBackingAndFeeBudgets(Contracts memory c, uint256 minBacking_) internal view {
        uint256 poolBalance = IERC20(c.ohm).balanceOf(address(c.pool));
        if (poolBalance < minBacking_) {
            revert CCIPTokenPoolConfigProposal_BackingTooLow(poolBalance, minBacking_);
        }

        string memory env = _readEnv();
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, _chain());
        for (uint256 i = 0; i < desired.length; ++i) {
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
        // The checker accepts the end state: no handover action included, no route to add, the
        // declared rebalancer, rate limit admin and minimum backing
        uint256 minBacking = _minimumPoolBacking();
        c.checker.check(_endStateExpectations(desired, minBacking));
        _validateLifecycle(c);
        _validatePoolAuthority(c, desired);
        _validateRegistry(c);
        _validateRoles(c, addresses.getAddress("proposer"));
        _validateParameters(c, desired);
        _requireRoutesMatchEnv(c.pool, true);
        _requireBackingAndFeeBudgets(c, minBacking);

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
        _requireAddress(
            "config operator",
            IConfigOperator(address(c.config)).configOperator(),
            address(c.configTimelock)
        );
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
        for (uint256 i = 0; i < noRateLimiter.length; ++i) {
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
            ITimelockBatchQueue(address(c.configTimelock)).timelockDelay(),
            desired.timelockDelay
        );
    }

    /// @notice Reverts unless the config policy, the timelock and the pool are bound together,
    ///         the pool serves OHM and the checker is bound to the same contracts and accounts.
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
        _requireCheckerBindings(c);
    }

    /// @notice Reverts unless the checker reports the contracts and accounts this proposal acts
    ///         on as its bindings.
    function _requireCheckerBindings(Contracts memory c) internal view {
        CCIPTokenPoolConfigProposalChecker checker = c.checker;
        _requireAddress("checker kernel", address(checker.KERNEL()), address(_kernel));
        _requireAddress("checker config", address(checker.CONFIG()), address(c.config));
        _requireAddress(
            "checker config timelock",
            address(checker.CONFIG_TIMELOCK()),
            address(c.configTimelock)
        );
        _requireAddress("checker pool", address(checker.POOL()), address(c.pool));
        _requireAddress("checker OHM", address(checker.OHM()), c.ohm);
        _requireAddress("checker registry", address(checker.REGISTRY()), address(c.registry));
        _requireAddress("checker ROLES", address(checker.ROLES()), address(c.roles));
        _requireAddress("checker OCG timelock", checker.OCG_TIMELOCK(), c.ocgTimelock);
        _requireAddress("checker DAO MS", checker.DAO_MS(), c.daoMS);
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
    ///        The build passes false and requires the missing set to equal the five expected
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
        for (uint256 i = 0; i < liveSelectors.length; ++i) {
            bool declared = false;
            for (uint256 j = 0; j < desired.length; ++j) {
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
        for (uint256 i = 0; i < desired.length; ++i) {
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
        c.checker = CCIPTokenPoolConfigProposalChecker(
            addresses.getAddress("olympus-periphery-ccip-token-pool-config-proposal-checker")
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
    function _readEnv() internal view virtual returns (string memory env) {
        // The path is the constant `_ENV_PATH`: the tracked `env.json` and nothing else is read
        // forge-lint: disable-next-line(unsafe-cheatcode)
        return vm.readFile(_ENV_PATH);
    }

    function _chain() internal view returns (string memory chain) {
        return ChainUtils._getChainName(block.chainid);
    }
}

contract CCIPTokenPoolConfigProposalScript is ProposalScript {
    constructor() ProposalScript(new CCIPTokenPoolConfigProposal()) {}
}

// forge-lint: disable-end(multi-contract-file)

// forge-lint: disable-end(calls-loop,require-revert-in-loop)
