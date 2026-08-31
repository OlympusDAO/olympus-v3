// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPMigrationForkTestBase} from "./CCIPMigrationForkTestBase.sol";

/// @notice Base of the non-Ethereum EVM migration fork tests: a base-sepolia fork pinned at
///         a recent block, the live contracts read from env.json, and the adoption bootstrap
///         of the already-serving burn/mint pool as a reusable procedure the replacement
///         suites build on.
/// @dev    base-sepolia is further along than a pristine bootstrap target: the burn/mint pool
///         policy is deployed, active, enabled and registered, and it already serves live
///         routes. The bootstrap here is therefore the adoption variant the procedure's
///         idempotent tooling produces on such a chain: the steps whose live state is already
///         satisfied fall away, and what remains is retiring the legacy LayerZero bridge,
///         deploying and wiring the config pair, and handing the pool ownership from the
///         current owner (a direct call, since the owner is an EOA rather than an outgoing
///         config policy). Service continuity is part of what the bootstrap suite asserts: the pool
///         stays enabled and registered throughout.
///
///         On this testnet the DAO Multisig, the Kernel executor and the RolesAdmin admin are
///         one EOA; the procedures do not care, and the same pranks apply.
abstract contract CCIPNonEthereumMigrationForkTest is CCIPMigrationForkTestBase {
    // ========== FORK PIN ========== //

    /// @notice Pinned so RPC responses are cached and the live-state preconditions are stable.
    uint256 internal constant BASE_SEPOLIA_FORK_BLOCK = 46_195_775;

    // ========== LIVE CONTRACTS (env.json) ========== //

    Kernel internal kernel;
    RolesAdmin internal rolesAdmin;
    ROLESv1 internal roles;
    MINTRv1 internal mintr;
    ICCIPTokenAdminRegistry internal registry;
    CCIPBurnMintTokenPool internal pool;
    CrossChainBridge internal legacyBridge;
    IERC20 internal ohm;

    address internal daoMS;
    address internal emergencyMS;
    address internal routerAddress;
    address internal rmnAddress;

    /// @notice The live counterpart route the pool already serves: the Ethereum-side testnet.
    uint64 internal sepoliaSelector;
    bytes internal sepoliaRemotePool;
    bytes internal sepoliaRemoteToken;

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.createSelectFork("base-sepolia", BASE_SEPOLIA_FORK_BLOCK);
        _loadEnv();

        kernel = Kernel(_envAddress("base-sepolia", "olympus.Kernel"));
        vm.label(address(kernel), "kernel");
        rolesAdmin = RolesAdmin(_envAddress("base-sepolia", "olympus.policies.RolesAdmin"));
        vm.label(address(rolesAdmin), "rolesAdmin");
        roles = ROLESv1(_envAddress("base-sepolia", "olympus.modules.OlympusRoles"));
        vm.label(address(roles), "rolesModule");
        mintr = MINTRv1(_envAddress("base-sepolia", "olympus.modules.OlympusMinter"));
        vm.label(address(mintr), "mintrModule");
        registry = ICCIPTokenAdminRegistry(
            _envAddress("base-sepolia", "external.ccip.TokenAdminRegistry")
        );
        vm.label(address(registry), "tokenAdminRegistry");
        pool = CCIPBurnMintTokenPool(
            _envAddress("base-sepolia", "olympus.policies.CCIPBurnMintTokenPool")
        );
        vm.label(address(pool), "burnMintPool");
        legacyBridge = CrossChainBridge(
            _envAddress("base-sepolia", "olympus.policies.CrossChainBridge")
        );
        vm.label(address(legacyBridge), "legacyLzBridge");
        ohm = IERC20(_envAddress("base-sepolia", "olympus.legacy.OHM"));
        vm.label(address(ohm), "ohm");

        daoMS = _envAddress("base-sepolia", "olympus.multisig.dao");
        vm.label(daoMS, "daoMS");
        emergencyMS = _envAddress("base-sepolia", "olympus.multisig.emergency");
        vm.label(emergencyMS, "emergencyMS");
        routerAddress = _envAddress("base-sepolia", "external.ccip.Router");
        vm.label(routerAddress, "ccipRouter");
        rmnAddress = _envAddress("base-sepolia", "external.ccip.RMN");
        vm.label(rmnAddress, "rmnProxy");

        sepoliaSelector = _envChainSelector("sepolia");
        sepoliaRemotePool = abi.encode(
            _envAddress("sepolia", "olympus.periphery.CCIPLockReleaseTokenPool")
        );
        sepoliaRemoteToken = abi.encode(_envAddress("sepolia", "olympus.legacy.OHM"));

        // Live preconditions of the suites; a failure here means the testnet has moved,
        // not that a migration step is broken
        require(kernel.executor() == daoMS, "live: the DAO MS should be the Kernel executor");
        require(rolesAdmin.admin() == daoMS, "live: the DAO MS should administer RolesAdmin");
        require(roles.hasRole(daoMS, "admin"), "live: the DAO MS should hold the admin role");
        require(
            roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE),
            "live: the DAO MS should hold the bridge admin role"
        );
        require(pool.owner() == daoMS, "live: the DAO MS should own the pool");
        require(kernel.isPolicyActive(pool), "live: the pool policy should be active");
        require(pool.isEnabled(), "live: the pool policy should be enabled");
        require(
            kernel.isPolicyActive(legacyBridge),
            "live: the legacy LayerZero bridge should still be active"
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
            pool.isSupportedChain(sepoliaSelector),
            "live: the pool should already serve the sepolia route"
        );
        require(
            pool.isRemotePool(sepoliaSelector, sepoliaRemotePool),
            "live: the sepolia route should accept the counterpart pool"
        );
    }

    // ========== BOOTSTRAP STEPS (the adoption the replacement suites build on) ========== //

    /// @notice Retires the legacy LayerZero bridge: switches it off (the live testnet still
    ///         has it on), asserts the zero mint approval the procedure requires, and
    ///         deactivates it in the kernel.
    function _retireLegacyBridge() internal {
        if (legacyBridge.bridgeActive()) {
            vm.prank(daoMS);
            legacyBridge.setBridgeStatus(false);
        }
        assertEq(
            mintr.mintApproval(address(legacyBridge)),
            0,
            "the legacy bridge should hold no mint approval before deactivation"
        );
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, address(legacyBridge));
    }

    /// @notice Activates the freshly deployed pair and grants whichever local roles are still
    ///         missing, the way the setup batch does (each action only when the live state
    ///         lacks it).
    function _activatePairAndGrantRoles() internal {
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        vm.stopPrank();
        if (!roles.hasRole(emergencyMS, EMERGENCY_ROLE)) {
            vm.prank(daoMS);
            rolesAdmin.grantRole(EMERGENCY_ROLE, emergencyMS);
        }
    }

    /// @notice Wires the stack: the config is enabled, adopts the pool through the direct
    ///         owner handover, seats the timelock and enables it.
    function _wireStack() internal {
        address configAddress = address(config);
        vm.startPrank(daoMS);
        config.enable("");
        // The owner is an EOA, so the handover is a direct proposal by the current owner
        // rather than a call through an outgoing config policy
        pool.transferOwnership(configAddress);
        config.acceptPoolOwnership();
        config.setConfigOperator(address(timelock));
        timelock.enable("");
        vm.stopPrank();
    }

    /// @notice The full adoption bootstrap, for the suites that start from an already migrated
    ///         stack. The pool's live routes are declared and already exist, so the
    ///         route step of the setup batch is empty on this chain.
    function _bootstrapStack() internal {
        _retireLegacyBridge();
        _deployPair(kernel, address(pool));
        _activatePairAndGrantRoles();
        _wireStack();
    }

    // ========== SHARED FIXTURES ========== //

    /// @notice A validated chain update toward a not-yet-served counterpart, for route
    ///         addition probes; the arbitrum-sepolia selector is real, the pool placeholder
    ///         is labelled (no counterpart pool is deployed there).
    function _newCounterpartUpdate()
        internal
        returns (ICCIPTokenPoolAdmin.ChainUpdate memory update)
    {
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(makeAddr("futurePool:arbitrum-sepolia"));
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: _envChainSelector("arbitrum-sepolia"),
                remotePoolAddresses: remotePools,
                remoteTokenAddress: abi.encode(
                    _envAddress("arbitrum-sepolia", "olympus.legacy.OHM")
                ),
                outboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: 10_000,
                    rate: 100
                }),
                inboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: 20_000,
                    rate: 200
                })
            });
    }
}
