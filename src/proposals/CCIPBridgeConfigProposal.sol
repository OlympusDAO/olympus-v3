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
///         policy and its CCIPBridgeConfigTimelock, moves the OHM administrator position in the
///         Chainlink TokenAdminRegistry under the OCG timelock, and opens the mainnet routes to
///         Arbitrum, Optimism, Base and Berachain on the pool.
///
///         Every handover action is conditional on the live state, so the proposal is idempotent
///         with respect to steps that already happened. The actions read, in order:
///         accept the OHM administrator role, grant `bridge_admin` to the DAO MS, enable the
///         config policy, accept the pool ownership, set the config timelock as config operator,
///         set the OCG timelock as rebalancer, clear the native rate limit admin, enable the
///         config timelock, and add the four routes through `CCIPBridgeConfig.addChain`. At most
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
///         - CCIPBridgeConfig and CCIPBridgeConfigTimelock have been deployed on Ethereum mainnet
///           and recorded in `src/proposals/addresses.json` and `src/scripts/env.json`.
///         - The DAO MS has run `CCIPBridgeConfigBatch.prepareHandover`: both policies are active
///           in the Kernel, CCIPBridgeConfig is the pending owner of the pool and the OCG timelock
///           is the pending OHM administrator in the TokenAdminRegistry.
///         - The OCG timelock holds the `admin` role.
///         - The live Solana route of the pool matches `olympus.config.CCIP.routes` in
///           `src/scripts/env.json`; the exact four routes to Arbitrum, Optimism, Base and
///           Berachain are declared there and missing from the pool.
///         - The pool holds at least `olympus.config.CCIP.minimumPoolBacking` OHM (the supply
///           outstanding on the burn/mint chains; `CCIPTokenPool.fundPool`).
///         - Every mainnet lane toward the four chains carries an enabled OHM fee entry with a
///           delivery gas budget of at least 175000, obtained from Chainlink.
contract CCIPBridgeConfigProposal is GovernorBravoProposal {
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
                "This proposal places the Chainlink CCIP OHM token pool on Ethereum mainnet under on-chain governance through the CCIPBridgeConfig policy and the CCIPBridgeConfigTimelock policy, and opens the mainnet CCIP routes to Arbitrum, Optimism, Base and Berachain.\n",
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
                "- The live Solana route of the pool matches the desired configuration and the four new routes are not configured yet.\n",
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
                "3. Enable the CCIPBridgeConfig policy.\n",
                "4. Accept the ownership of the token pool through CCIPBridgeConfig.\n",
                "5. Set the CCIPBridgeConfigTimelock as the config operator of CCIPBridgeConfig.\n",
                "6. Set the OCG timelock as the rebalancer of the token pool.\n",
                "7. Clear the native rate limit admin of the token pool.\n",
                "8. Enable the CCIPBridgeConfigTimelock policy.\n",
                "9. Add the Arbitrum route to the token pool.\n",
                "10. Add the Base route to the token pool.\n",
                "11. Add the Berachain route to the token pool.\n",
                "12. Add the Optimism route to the token pool.\n",
                "\n",
                "## Route Limits\n",
                "\n",
                "Each of the four routes (Arbitrum, Optimism, Base, Berachain) opens with independent rate limit buckets in OHM base units (9 decimals), sized from the LayerZero v2 figures with a one-day window:\n",
                "\n",
                "- Outbound (mainnet to the chain): capacity 100,000 OHM (100000000000000), refill rate 1157407407 per second.\n",
                "- Inbound (the chain to mainnet): capacity 55,000 OHM (55000000000000), refill rate 636574074 per second.\n",
                "\n",
                "The remote token of each route is the chain's OHM token and the accepted remote pool is the chain's CCIPBurnMintTokenPool policy, both read from the desired-state configuration at build time. The pool's Optimism-Berachain pair is not opened anywhere: Chainlink serves no lane between those chains.\n",
                "\n",
                "At the completion of this proposal, route configuration is proposed by the DAO MS through the CCIPBridgeConfigTimelock and executed after its delay, containment is available to the Emergency MS through CCIPBridgeConfig, and the remaining root settings of the pool require an OCG proposal. The four chains stay dormant until their local DAO MS enables and registers the local pool, which is expected immediately after this proposal executes.\n"
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

        // Preconditions: the deployment, the admin role, the routes, the backing, the budgets
        _requireDeployment(c);
        require(
            desired.rebalancer == c.ocgTimelock,
            "env.json olympus.config.CCIPBridgeConfig.rebalancer is not the OCG timelock"
        );
        require(
            c.roles.hasRole(c.ocgTimelock, ADMIN_ROLE),
            "The OCG timelock does not hold the admin role"
        );
        // The routes this proposal opens are allowed to be missing; _buildRouteActions requires
        // the missing set to be exactly the four expected chains.
        _requireRoutesMatchEnv(c.pool, false);
        _requireBackingAndFeeBudgets(c);

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

        // 9-12. Add the four routes, after the handover actions: addChain requires the config
        // policy to be enabled and to own the pool, both established earlier in this execution.
        _buildRouteActions(c);
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
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(_env, _chain());
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
            require(
                expectedIndex != type(uint256).max,
                string.concat(
                    "Missing route is not among the four expected chains: ",
                    route.remoteChain
                )
            );
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
                abi.encodeWithSelector(ICCIPBridgeConfig.addChain.selector, update),
                string.concat("Add the ", route.remoteChain, " route to the token pool")
            );
        }

        require(
            missingCount == expected.length && added[0] && added[1] && added[2] && added[3],
            "The set of missing routes does not equal the four expected chains: investigate, rebuild and resubmit"
        );
    }

    /// @notice Reverts unless the pool holds the minimum backing and every mainnet lane toward a
    ///         burn/mint destination carries the raised OHM delivery gas budget. Checked at build
    ///         time and re-checked by `_validate`.
    function _requireBackingAndFeeBudgets(Contracts memory c) internal view {
        uint256 minBacking = CCIPConfigLib.minimumPoolBacking(_env, _chain());
        uint256 poolBalance = IERC20(c.ohm).balanceOf(address(c.pool));
        require(
            poolBalance >= minBacking,
            string.concat(
                "The pool backing ",
                vm.toString(poolBalance),
                " is below olympus.config.CCIP.minimumPoolBacking ",
                vm.toString(minBacking),
                ": re-read shell/calc_bridged_supply.sh and run CCIPTokenPool.fundPool first"
            )
        );

        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(_env, _chain());
        for (uint256 i; i < desired.length; ++i) {
            if (!desired[i].enabled) continue;
            if (!CCIPConfigLib.isBurnMintEvmChain(desired[i].remoteChain)) continue;
            CCIPFeeBudgetLib.requireOhmFeeBudget(_env, _chain(), desired[i].remoteChain);
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
        _requireRoutesMatchEnv(c.pool, true);
        _requireBackingAndFeeBudgets(c);

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
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(_env, _chain());
        require(desired.length > 0, "env.json declares no CCIP route for this chain");

        // Every live route must be declared and enabled, with both limiters enabled
        uint64[] memory liveSelectors = pool_.getSupportedChains();
        for (uint256 i; i < liveSelectors.length; ++i) {
            bool declared;
            for (uint256 j; j < desired.length; ++j) {
                if (desired[j].chainSelector == liveSelectors[i] && desired[j].enabled) {
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
            if (!route.enabled) {
                require(
                    !live.exists,
                    string.concat(
                        "Route declared with enabled=false is still configured: ",
                        route.remoteChain,
                        "; remove it through CCIPRouteReconcileBatch before the proposal"
                    )
                );
                continue;
            }
            if (!live.exists) {
                require(
                    !requireDesiredLive_,
                    string.concat(
                        "Route is not configured on the pool: ",
                        route.remoteChain,
                        "; apply it before the proposal (direct pool owner batch before the handover, config timelock afterwards)"
                    )
                );
                continue;
            }
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
