// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPMigrationForkTestBase} from "./CCIPMigrationForkTestBase.sol";

/// @notice Base of the Ethereum migration fork tests: a mainnet fork pinned at a recent
///         block, the live contracts read from env.json, and the bootstrap of the config
///         pair over the live pool (DAO batch, pool funding, OCG proposal) as a reusable
///         procedure the replacement suites build on.
/// @dev    Live preconditions the suites rely on are checked in setUp with labelled
///         requires: the DAO Multisig is the Kernel executor, owns the pool and administers
///         OHM in the TokenAdminRegistry; the OCG timelock is the RolesAdmin admin and holds
///         the admin role; the pool already serves the Solana route. If mainnet has moved
///         past this (for instance the bootstrap has been executed live), the requires fail
///         with an explicit message and the pin or the procedure needs updating.
///
///         The counterpart burn/mint pools are not deployed yet (their env.json slots are
///         zero), so the remote pool half of each new route uses a labelled placeholder
///         address: no step of the migration reads or validates that value, and the real
///         rollout fills it in when the counterpart chain deploys.
abstract contract CCIPEthereumMigrationForkTest is CCIPMigrationForkTestBase {
    // ========== FORK PIN ========== //

    /// @notice Pinned so RPC responses are cached and the live-state preconditions are stable.
    uint256 internal constant MAINNET_FORK_BLOCK = 25_873_641;

    // ========== LIVE CONTRACTS (env.json) ========== //

    Kernel internal kernel;
    RolesAdmin internal rolesAdmin;
    ROLESv1 internal roles;
    ICCIPTokenAdminRegistry internal registry;
    ICCIPTokenPoolAdmin internal pool;
    IERC20 internal ohm;

    address internal daoMS;
    address internal ocgTimelock;
    address internal emergencyMS;
    address internal routerAddress;
    address internal rmnAddress;

    uint64 internal solanaSelector;
    uint256 internal minimumPoolBacking;

    // ========== NEW ROUTE SPECS (env.json declarations) ========== //

    struct RouteSpec {
        string name;
        uint64 chainSelector;
        bytes remoteToken;
        bytes remotePool;
        ICCIPRateLimiter.Config outbound;
        ICCIPRateLimiter.Config inbound;
    }

    /// @notice The four burn/mint routes the bootstrap proposal opens, built from env.json:
    ///         real selectors and counterpart OHM addresses, declared rate limits, and a
    ///         placeholder remote pool (see the contract NatSpec).
    RouteSpec[] internal burnMintRoutes;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.createSelectFork("mainnet", MAINNET_FORK_BLOCK);
        _loadEnv();

        kernel = Kernel(_envAddress("mainnet", "olympus.Kernel"));
        vm.label(address(kernel), "kernel");
        rolesAdmin = RolesAdmin(_envAddress("mainnet", "olympus.policies.RolesAdmin"));
        vm.label(address(rolesAdmin), "rolesAdmin");
        roles = ROLESv1(_envAddress("mainnet", "olympus.modules.OlympusRoles"));
        vm.label(address(roles), "rolesModule");
        registry = ICCIPTokenAdminRegistry(
            _envAddress("mainnet", "external.ccip.TokenAdminRegistry")
        );
        vm.label(address(registry), "tokenAdminRegistry");
        pool = ICCIPTokenPoolAdmin(
            _envAddress("mainnet", "olympus.periphery.CCIPLockReleaseTokenPool")
        );
        vm.label(address(pool), "lockReleasePool");
        ohm = IERC20(_envAddress("mainnet", "olympus.legacy.OHM"));
        vm.label(address(ohm), "ohm");

        daoMS = _envAddress("mainnet", "olympus.multisig.dao");
        vm.label(daoMS, "daoMS");
        ocgTimelock = _envAddress("mainnet", "olympus.governance.Timelock");
        vm.label(ocgTimelock, "ocgTimelock");
        emergencyMS = _envAddress("mainnet", "olympus.multisig.emergency");
        vm.label(emergencyMS, "emergencyMS");
        routerAddress = _envAddress("mainnet", "external.ccip.Router");
        vm.label(routerAddress, "ccipRouter");
        rmnAddress = _envAddress("mainnet", "external.ccip.RMN");
        vm.label(rmnAddress, "rmnProxy");

        solanaSelector = _envChainSelector("solana");
        minimumPoolBacking = _envUint("mainnet", "olympus.config.CCIP.minimumPoolBacking");

        string[4] memory counterparts = ["arbitrum", "base", "berachain", "optimism"];
        for (uint256 i; i < counterparts.length; ++i) {
            string memory name = counterparts[i];
            address placeholderPool = makeAddr(string.concat("futurePool:", name));
            burnMintRoutes.push(
                RouteSpec({
                    name: name,
                    chainSelector: _envChainSelector(name),
                    remoteToken: abi.encode(_envAddress(name, "olympus.legacy.OHM")),
                    remotePool: abi.encode(placeholderPool),
                    outbound: _envRouteLimit("mainnet", name, "outboundRateLimit"),
                    inbound: _envRouteLimit("mainnet", name, "inboundRateLimit")
                })
            );
        }

        // Live preconditions of the suites; a failure here means mainnet has moved, not
        // that a migration step is broken
        require(kernel.executor() == daoMS, "live: the DAO MS should be the Kernel executor");
        require(pool.owner() == daoMS, "live: the DAO MS should own the pool");
        require(
            rolesAdmin.admin() == ocgTimelock,
            "live: the OCG timelock should administer RolesAdmin"
        );
        require(
            roles.hasRole(ocgTimelock, "admin"),
            "live: the OCG timelock should hold the admin role"
        );
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        require(
            tokenConfig.administrator == daoMS,
            "live: the DAO MS should administer OHM in the registry"
        );
        require(
            tokenConfig.tokenPool == address(pool),
            "live: the registry should point at the pool"
        );
        require(
            pool.isSupportedChain(solanaSelector),
            "live: the pool should already serve the Solana route"
        );
    }

    // ========== BOOTSTRAP STEPS (the procedure the replacement suites build on) ========== //

    /// @notice Deploys the pair over the live pool; the bindings are fixed at construction.
    function _deployPairOverLivePool() internal {
        _deployPair(kernel, address(pool));
    }

    /// @notice The DAO Multisig batch: activates both policies and, when `proposeHandovers_`
    ///         is set, proposes the pool ownership to the config and nominates the OCG
    ///         timelock as the OHM administrator; both stay pending until the OCG proposal
    ///         accepts them.
    function _daoBatchActivateAndProposeHandovers(bool proposeHandovers_) internal {
        address ohmAddress = address(ohm);
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        if (proposeHandovers_) {
            pool.transferOwnership(address(config));
            registry.transferAdminRole(ohmAddress, ocgTimelock);
        }
        vm.stopPrank();
    }

    /// @notice The pool funding that must precede the proposal: the DAO Multisig tops the
    ///         pool up to the recorded minimum backing with real OHM.
    function _fundPoolToMinimumBacking() internal {
        uint256 balance = ohm.balanceOf(address(pool));
        if (balance >= minimumPoolBacking) return;
        uint256 deficit = minimumPoolBacking - balance;
        require(
            ohm.balanceOf(daoMS) >= deficit,
            "live: the DAO MS should hold enough OHM to fund the pool"
        );
        vm.prank(daoMS);
        bool funded = ohm.transfer(address(pool), deficit);
        assertTrue(funded, "the funding transfer should succeed");
    }

    /// @notice The OCG proposal, replayed as pranked calls of the OCG timelock in
    ///         the proposal's action order. The role grant is conditional on the live state,
    ///         exactly as the proposal builds it.
    function _ocgProposalAcceptAndWireStack() internal {
        address ohmAddress = address(ohm);
        bool needsBridgeAdminGrant = !roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE);
        vm.startPrank(ocgTimelock);
        registry.acceptAdminRole(ohmAddress);
        if (needsBridgeAdminGrant) rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, daoMS);
        config.enable("");
        config.acceptPoolOwnership();
        config.setConfigOperator(address(timelock));
        config.setRebalancer(ocgTimelock);
        config.setRateLimitAdmin(address(0));
        timelock.enable("");
        for (uint256 i; i < burnMintRoutes.length; ++i) {
            config.addChain(_toChainUpdate(burnMintRoutes[i]));
        }
        vm.stopPrank();
    }

    /// @notice The full bootstrap, for the suites that start from an already migrated stack.
    function _bootstrapStack() internal {
        _deployPairOverLivePool();
        _daoBatchActivateAndProposeHandovers(true);
        _fundPoolToMinimumBacking();
        _ocgProposalAcceptAndWireStack();
    }

    function _toChainUpdate(
        RouteSpec memory spec_
    ) internal pure returns (ICCIPTokenPoolAdmin.ChainUpdate memory) {
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = spec_.remotePool;
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: spec_.chainSelector,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: spec_.remoteToken,
                outboundRateLimiterConfig: spec_.outbound,
                inboundRateLimiterConfig: spec_.inbound
            });
    }
}
