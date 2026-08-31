// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

/// @notice Shared abstract base of the CCIPTokenPoolConfigTimelock test suite.
/// @dev    The rig is real end to end: no mock of the config policy and no mock pool, so the
///         queue-time validation runs the real validate mirrors against the real pool and the
///         dispatch runs the real route functions.
///
///         The setup deploys the full Kernel stack (Kernel, OlympusRoles, RolesAdmin), a real
///         CCIPTokenPoolConfig over a real Chainlink lock/release pool with liquidity acceptance
///         and an empty allowlist over MockOhm at 9 decimals, and the timelock under test over
///         that config with an initial delay of 1 day and a grace period of 3 days. Both
///         policies are activated in the kernel.
///
///         Default state after setUp: the config policy is ENABLED, the pool ownership is
///         ACCEPTED by the config, the config operator is set to the timelock, no routes are
///         added, and the timelock under test is DISABLED. givenEnabled enables the timelock;
///         the route fixtures add routes through the config as the admin, reusing the
///         CCIPTokenPoolConfigTest defaults verbatim: selectors 1111/2222, outbound
///         {true, 10_000, 100}, inbound {true, 20_000, 200} in OHM base units, EVM-shaped
///         remote addresses, two remote pools on route A.
///
///         Roles are granted to distinct makeAddr accounts: admin, emergency, bridgeAdmin and
///         bridgeRateLimiter; thirdParty holds nothing. The timelock's queue caller is
///         bridgeAdmin; bridgeRateLimiter holds no timelock authority and serves the negative
///         cases.
///
///         The canonical queued action of givenActionQueued is queueSetChainRateLimits on
///         route A with the non-default CANONICAL_* values, so drift, conflict and
///         cancellation tests all reference one shape built by _canonicalOutboundConfig and
///         _canonicalInboundConfig through _queueRateLimitAction.
///
///         The allowlist cases run on a second full stack (givenAllowListPoolRig) whose
///         lock/release pool is deployed with a two-entry allowlist and which carries its own
///         config and timelock; the primary rig's pool has no allowlist, so every
///         queueApplyAllowListUpdates on it reverts AllowListNotEnabled at queue time.
///
///         Bucket spending for the volatile-state cases goes through a real lockOrBurn call
///         from the mocked on-ramp (MockCCIPRouter.setOnRamp), which consumes the outbound
///         bucket without touching its configuration. That path runs the pool's RMN probe, and
///         MockRMNProxy.isCursed reverts NotSet for an un-armed selector: every route fixture
///         therefore arms the proxy with rmnProxy.setIsCursed(bytes16(uint128(selector)),
///         false) for its selector.
///
///         Time moves only with skip() and reads only with vm.getBlockTimestamp(). Every
///         deployed contract is labelled; test accounts come from makeAddr. Prank convention:
///         read every contract handle and address needed for a pranked call before vm.prank,
///         because any external view call placed between the prank and the target call
///         consumes the prank.
///
///         Log convention: the emit statement that follows vm.expectEmit is itself a real
///         log from the test contract and lands in vm.getRecordedLogs(), so count and
///         absence assertions over recorded logs filter by emitter and topic zero, never by
///         the total array length.
abstract contract CCIPTokenPoolConfigTimelockTest is Test {
    // ========== KERNEL STACK ========== //

    Kernel internal kernel;
    OlympusRoles internal rolesModule;
    RolesAdmin internal rolesAdmin;

    // ========== POOL RIG ========== //

    MockOhm internal ohm;
    MockCCIPRouter internal ccipRouter;
    MockRMNProxy internal rmnProxy;
    LockReleaseTokenPool internal pool;

    // ========== CONFIG POLICY AND POLICY UNDER TEST ========== //

    CCIPTokenPoolConfig internal config;
    CCIPTokenPoolConfigTimelock internal timelock;

    // ========== ACCOUNTS ========== //

    address internal admin;
    address internal emergency;
    address internal bridgeAdmin;
    address internal bridgeRateLimiter;
    address internal thirdParty;
    address internal onRamp;
    address internal offRamp;
    address internal allowListedOne;
    address internal allowListedTwo;

    /// @notice The default addition of the canonical allowlist action; never in any
    ///         constructor allowlist.
    address internal allowListedThree;

    // ========== DEFAULT REMOTE ADDRESSES (EVM-shaped, set in setUp) ========== //

    bytes internal REMOTE_TOKEN;
    bytes internal REMOTE_POOL_ONE;
    bytes internal REMOTE_POOL_TWO;
    bytes internal REMOTE_TOKEN_B;
    bytes internal REMOTE_POOL_B;

    /// @notice A remote pool value accepted on no route by default, for addRemotePool
    ///         fixtures.
    bytes internal REMOTE_POOL_THREE;

    // ========== CONSTANTS ========== //

    /// @notice The initial timelock delay of the instance under test.
    uint48 internal constant TIMELOCK_DELAY = 1 days;

    /// @notice The grace period of the instance under test.
    uint32 internal constant GRACE_PERIOD = 3 days;

    uint64 internal constant CHAIN_SELECTOR_A = 1111;
    uint64 internal constant CHAIN_SELECTOR_B = 2222;

    uint8 internal constant OHM_DECIMALS = 9;

    /// @notice Default rate limiter constants, in OHM base units (9 decimals).
    uint128 internal constant DEFAULT_OUTBOUND_CAPACITY = 10_000;
    uint128 internal constant DEFAULT_OUTBOUND_RATE = 100;
    uint128 internal constant DEFAULT_INBOUND_CAPACITY = 20_000;
    uint128 internal constant DEFAULT_INBOUND_RATE = 200;

    /// @notice The canonical queued-action rate limiter constants: deliberately distinct from
    ///         the route defaults, so executing the canonical action observably rewrites the
    ///         pool state.
    uint128 internal constant CANONICAL_OUTBOUND_CAPACITY = 5_000;
    uint128 internal constant CANONICAL_OUTBOUND_RATE = 50;
    uint128 internal constant CANONICAL_INBOUND_CAPACITY = 8_000;
    uint128 internal constant CANONICAL_INBOUND_RATE = 80;

    // ========== EXPOSED MODIFIER STATE ========== //

    /// @notice The action id queued by givenActionQueued, for the queue and lifecycle passes.
    uint64 internal queuedActionId;

    /// @notice The grace deadline computed by givenGraceExpired, for error-argument asserts.
    uint48 internal graceDeadline;

    // ========== SETUP ========== //

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        bridgeAdmin = makeAddr("bridgeAdmin");
        bridgeRateLimiter = makeAddr("bridgeRateLimiter");
        thirdParty = makeAddr("thirdParty");
        onRamp = makeAddr("onRamp");
        offRamp = makeAddr("offRamp");
        allowListedOne = makeAddr("allowListedOne");
        allowListedTwo = makeAddr("allowListedTwo");
        allowListedThree = makeAddr("allowListedThree");

        REMOTE_TOKEN = abi.encode(makeAddr("remoteToken"));
        REMOTE_POOL_ONE = abi.encode(makeAddr("remotePoolOne"));
        REMOTE_POOL_TWO = abi.encode(makeAddr("remotePoolTwo"));
        REMOTE_TOKEN_B = abi.encode(makeAddr("remoteTokenB"));
        REMOTE_POOL_B = abi.encode(makeAddr("remotePoolB"));
        REMOTE_POOL_THREE = abi.encode(makeAddr("remotePoolThree"));

        ohm = new MockOhm("Olympus", "OHM", OHM_DECIMALS);
        vm.label(address(ohm), "ohm");
        ccipRouter = new MockCCIPRouter();
        vm.label(address(ccipRouter), "ccipRouter");
        rmnProxy = new MockRMNProxy();
        vm.label(address(rmnProxy), "rmnProxy");

        pool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            true,
            address(ccipRouter)
        );
        vm.label(address(pool), "pool");

        kernel = new Kernel();
        vm.label(address(kernel), "kernel");
        rolesModule = new OlympusRoles(kernel);
        vm.label(address(rolesModule), "rolesModule");
        rolesAdmin = new RolesAdmin(kernel);
        vm.label(address(rolesAdmin), "rolesAdmin");

        kernel.executeAction(Actions.InstallModule, address(rolesModule));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, bridgeAdmin);
        rolesAdmin.grantRole(BRIDGE_RATE_LIMITER_ROLE, bridgeRateLimiter);

        config = new CCIPTokenPoolConfig(kernel, address(pool), GRACE_PERIOD);
        vm.label(address(config), "config");
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        // The test contract owns the pool; the config becomes the pending owner
        pool.transferOwnership(address(config));

        timelock = new CCIPTokenPoolConfigTimelock(
            kernel,
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(timelock), "timelock");
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));

        // Default state: config ENABLED, pool ownership ACCEPTED, operator seat set to the
        // timelock; the timelock itself stays DISABLED
        vm.startPrank(admin);
        config.enable("");
        config.acceptPoolOwnership();
        config.setConfigOperator(address(timelock));
        vm.stopPrank();
    }

    // ========== DEPLOY HELPERS ========== //

    /// @notice Deploys a fresh, unactivated timelock instance for constructor-style tests.
    function _newTimelock(
        address config_,
        uint48 delay_,
        uint32 gracePeriod_
    ) internal returns (CCIPTokenPoolConfigTimelock newTimelock) {
        newTimelock = new CCIPTokenPoolConfigTimelock(kernel, config_, delay_, gracePeriod_);
        vm.label(address(newTimelock), "freshTimelock");
        return newTimelock;
    }

    /// @notice Deploys a fresh, unactivated and disabled config over the primary pool on the
    ///         given kernel, plus an unactivated timelock over that config on the same kernel.
    ///         Run against the primary kernel it serves the fresh-config and key-namespace
    ///         cases; through _deployStackOnForeignKernel it serves the kernel-mismatch cases.
    function _deployStackOnKernel(
        Kernel kernel_
    )
        internal
        returns (CCIPTokenPoolConfig stackConfig, CCIPTokenPoolConfigTimelock stackTimelock)
    {
        stackConfig = new CCIPTokenPoolConfig(kernel_, address(pool), GRACE_PERIOD);
        vm.label(address(stackConfig), "secondConfig");
        stackTimelock = new CCIPTokenPoolConfigTimelock(
            kernel_,
            address(stackConfig),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(stackTimelock), "secondTimelock");
        return (stackConfig, stackTimelock);
    }

    /// @notice Deploys a second kernel and a config-plus-timelock stack on it, over the
    ///         primary pool. No module is installed on the foreign kernel: the constructor
    ///         paths that use this helper never touch ROLES.
    function _deployStackOnForeignKernel()
        internal
        returns (
            Kernel foreignKernel,
            CCIPTokenPoolConfig foreignConfig,
            CCIPTokenPoolConfigTimelock foreignTimelock
        )
    {
        foreignKernel = new Kernel();
        vm.label(address(foreignKernel), "foreignKernel");
        (foreignConfig, foreignTimelock) = _deployStackOnKernel(foreignKernel);
        vm.label(address(foreignConfig), "foreignConfig");
        vm.label(address(foreignTimelock), "foreignTimelock");
        return (foreignKernel, foreignConfig, foreignTimelock);
    }

    // ========== CONFIG AND CHAIN UPDATE FACTORIES ========== //

    function _rateLimiterConfig(
        bool isEnabled_,
        uint128 capacity_,
        uint128 rate_
    ) internal pure returns (ICCIPRateLimiter.Config memory) {
        return ICCIPRateLimiter.Config({isEnabled: isEnabled_, capacity: capacity_, rate: rate_});
    }

    /// @notice The default outbound configuration: {true, 10_000, 100} in base units.
    function _defaultOutboundConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(true, DEFAULT_OUTBOUND_CAPACITY, DEFAULT_OUTBOUND_RATE);
    }

    /// @notice The default inbound configuration: {true, 20_000, 200} in base units.
    function _defaultInboundConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(true, DEFAULT_INBOUND_CAPACITY, DEFAULT_INBOUND_RATE);
    }

    /// @notice The canonical outbound configuration of the queued action: {true, 5_000, 50}.
    function _canonicalOutboundConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(true, CANONICAL_OUTBOUND_CAPACITY, CANONICAL_OUTBOUND_RATE);
    }

    /// @notice The canonical inbound configuration of the queued action: {true, 8_000, 80}.
    function _canonicalInboundConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(true, CANONICAL_INBOUND_CAPACITY, CANONICAL_INBOUND_RATE);
    }

    /// @notice The containment shape {true, 2, 1}: the disabled rate limiter configuration
    ///         that the containment functions write.
    function _containmentConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(true, 2, 1);
    }

    /// @notice The pool's disabled shape {false, 0, 0}: no rate limiting at all. The config's
    ///         own validated paths reject it; only direct pool writes can produce it.
    function _disabledConfig() internal pure returns (ICCIPRateLimiter.Config memory) {
        return _rateLimiterConfig(false, 0, 0);
    }

    function _defaultRemotePools() internal view returns (bytes[] memory pools) {
        pools = new bytes[](2);
        pools[0] = REMOTE_POOL_ONE;
        pools[1] = REMOTE_POOL_TWO;
        return pools;
    }

    function _singleRemotePool() internal view returns (bytes[] memory pools) {
        pools = new bytes[](1);
        pools[0] = REMOTE_POOL_ONE;
        return pools;
    }

    function _singleAddress(address entry_) internal pure returns (address[] memory entries) {
        entries = new address[](1);
        entries[0] = entry_;
        return entries;
    }

    /// @notice ChainUpdate factory. Tests override single fields by mutating the returned
    ///         memory struct.
    function _chainUpdate(
        uint64 chainSelector_,
        bytes[] memory remotePools_,
        bytes memory remoteToken_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal pure returns (ICCIPTokenPoolAdmin.ChainUpdate memory) {
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: chainSelector_,
                remotePoolAddresses: remotePools_,
                remoteTokenAddress: remoteToken_,
                outboundRateLimiterConfig: outbound_,
                inboundRateLimiterConfig: inbound_
            });
    }

    /// @notice The default ChainUpdate: two remote pools, the default remote token and the
    ///         default rate limiter configurations.
    function _defaultChainUpdate(
        uint64 chainSelector_
    ) internal view returns (ICCIPTokenPoolAdmin.ChainUpdate memory) {
        return
            _chainUpdate(
                chainSelector_,
                _defaultRemotePools(),
                REMOTE_TOKEN,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            );
    }

    // ========== BATCH ACTION FACTORIES ========== //

    /// @notice BatchAction factory over the current rig's config. The typed factories below
    ///         mirror the abi.encode of the corresponding queue helper exactly, so batch
    ///         payloads built through them are canonical by construction.
    function _batchAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction({
                target: address(config),
                selector: selector_,
                payload: payload_
            });
    }

    function _addChainBatchAction(
        ICCIPTokenPoolAdmin.ChainUpdate memory update_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return _batchAction(ICCIPTokenPoolConfig.addChain.selector, abi.encode(update_));
    }

    function _removeChainBatchAction(
        uint64 chainSelector_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return _batchAction(ICCIPTokenPoolConfig.removeChain.selector, abi.encode(chainSelector_));
    }

    function _setRemoteTokenBatchAction(
        uint64 chainSelector_,
        bytes memory remoteToken_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _batchAction(
                ICCIPTokenPoolConfig.setRemoteToken.selector,
                abi.encode(chainSelector_, remoteToken_)
            );
    }

    function _addRemotePoolBatchAction(
        uint64 chainSelector_,
        bytes memory remotePool_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _batchAction(
                ICCIPTokenPoolConfig.addRemotePool.selector,
                abi.encode(chainSelector_, remotePool_)
            );
    }

    function _removeRemotePoolBatchAction(
        uint64 chainSelector_,
        bytes memory remotePool_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _batchAction(
                ICCIPTokenPoolConfig.removeRemotePool.selector,
                abi.encode(chainSelector_, remotePool_)
            );
    }

    function _applyAllowListUpdatesBatchAction(
        address[] memory removes_,
        address[] memory adds_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _batchAction(
                ICCIPTokenPoolConfig.applyAllowListUpdates.selector,
                abi.encode(removes_, adds_)
            );
    }

    function _setChainRateLimitsBatchAction(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _batchAction(
                ICCIPTokenPoolConfig.setChainRateLimits.selector,
                abi.encode(chainSelector_, outbound_, inbound_)
            );
    }

    function _singleActionBatch(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory batch) {
        batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = action_;
        return batch;
    }

    // ========== QUEUE WRAPPERS ========== //

    /// @notice Queues the canonical rate limit action for a route as the bridge admin: the
    ///         CANONICAL_* configurations, non-default on purpose.
    function _queueRateLimitAction(uint64 chainSelector_) internal returns (uint64 actionId) {
        vm.prank(bridgeAdmin);
        return
            timelock.queueSetChainRateLimits(
                chainSelector_,
                _canonicalOutboundConfig(),
                _canonicalInboundConfig()
            );
    }

    /// @notice Queues the default addChain action for a selector as the bridge admin.
    function _queueAddChainAction(uint64 chainSelector_) internal returns (uint64 actionId) {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _defaultChainUpdate(chainSelector_);
        vm.prank(bridgeAdmin);
        return timelock.queueAddChain(update);
    }

    /// @notice Queues a removeChain action for a route as the bridge admin.
    function _queueRemoveChainAction(uint64 chainSelector_) internal returns (uint64 actionId) {
        vm.prank(bridgeAdmin);
        return timelock.queueRemoveChain(chainSelector_);
    }

    /// @notice Queues a setRemoteToken action replacing the route's token with REMOTE_TOKEN_B,
    ///         as the bridge admin.
    function _queueSetRemoteTokenAction(uint64 chainSelector_) internal returns (uint64 actionId) {
        bytes memory remoteToken = REMOTE_TOKEN_B;
        vm.prank(bridgeAdmin);
        return timelock.queueSetRemoteToken(chainSelector_, remoteToken);
    }

    /// @notice Queues an addRemotePool action adding REMOTE_POOL_THREE, as the bridge admin.
    function _queueAddRemotePoolAction(uint64 chainSelector_) internal returns (uint64 actionId) {
        bytes memory remotePool = REMOTE_POOL_THREE;
        vm.prank(bridgeAdmin);
        return timelock.queueAddRemotePool(chainSelector_, remotePool);
    }

    /// @notice Queues a removeRemotePool action removing REMOTE_POOL_TWO, as the bridge
    ///         admin. On the default two-pool route the removal never trips the
    ///         last-remote-pool floor.
    function _queueRemoveRemotePoolAction(
        uint64 chainSelector_
    ) internal returns (uint64 actionId) {
        bytes memory remotePool = REMOTE_POOL_TWO;
        vm.prank(bridgeAdmin);
        return timelock.queueRemoveRemotePool(chainSelector_, remotePool);
    }

    /// @notice Queues the canonical allowlist action (no removals, add allowListedThree) as
    ///         the bridge admin. Valid only on the allowlist rig.
    function _queueApplyAllowListUpdatesAction() internal returns (uint64 actionId) {
        address[] memory adds = _singleAddress(allowListedThree);
        vm.prank(bridgeAdmin);
        return timelock.queueApplyAllowListUpdates(new address[](0), adds);
    }

    // ========== DIRECT-CHANGE WRAPPERS (DRIFT ACTORS) ========== //

    /// @notice The admin adds a route directly on the config, bypassing the timelock.
    function _directAddChain(ICCIPTokenPoolAdmin.ChainUpdate memory update_) internal {
        vm.prank(admin);
        config.addChain(update_);
    }

    /// @notice The admin removes a route directly on the config.
    function _directRemoveChain(uint64 chainSelector_) internal {
        vm.prank(admin);
        config.removeChain(chainSelector_);
    }

    /// @notice The admin replaces a route's remote token directly on the config.
    function _directSetRemoteToken(uint64 chainSelector_, bytes memory remoteToken_) internal {
        vm.prank(admin);
        config.setRemoteToken(chainSelector_, remoteToken_);
    }

    /// @notice The admin adds a remote pool directly on the config.
    function _directAddRemotePool(uint64 chainSelector_, bytes memory remotePool_) internal {
        vm.prank(admin);
        config.addRemotePool(chainSelector_, remotePool_);
    }

    /// @notice The admin removes a remote pool directly on the config.
    function _directRemoveRemotePool(uint64 chainSelector_, bytes memory remotePool_) internal {
        vm.prank(admin);
        config.removeRemotePool(chainSelector_, remotePool_);
    }

    /// @notice The admin applies allowlist updates directly on the config.
    function _directApplyAllowListUpdates(
        address[] memory removes_,
        address[] memory adds_
    ) internal {
        vm.prank(admin);
        config.applyAllowListUpdates(removes_, adds_);
    }

    /// @notice The admin writes both bucket configurations directly on the config.
    function _directSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal {
        vm.prank(admin);
        config.setChainRateLimits(chainSelector_, outbound_, inbound_);
    }

    /// @notice A containment-role holder disables a route through config.disableChain.
    function _containRoute(uint64 chainSelector_, address caller_) internal {
        vm.prank(caller_);
        config.disableChain(chainSelector_);
    }

    // ========== DIRECT POOL SEEDING ========== //

    /// @notice Adds a route directly on the current rig's pool, impersonating the pool owner.
    ///         Produces shapes the config's validated paths reject (disabled buckets, an empty
    ///         remote pool set).
    function _seedRouteOnPool(
        uint64 chainSelector_,
        bytes[] memory remotePools_,
        bytes memory remoteToken_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        ICCIPTokenPoolAdmin.ChainUpdate[]
            memory chainsToAdd = new ICCIPTokenPoolAdmin.ChainUpdate[](1);
        chainsToAdd[0] = _chainUpdate(
            chainSelector_,
            remotePools_,
            remoteToken_,
            outbound_,
            inbound_
        );
        vm.prank(rigPool.owner());
        rigPool.applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    /// @notice Adds `count_` routes with default parameters and sequential selectors starting
    ///         at 10_000, as the admin, arming the RMN proxy per selector. Requires the
    ///         enabled config policy owning the pool.
    function _addRoutes(uint256 count_) internal returns (uint64[] memory selectors) {
        selectors = new uint64[](count_);
        vm.startPrank(admin);
        for (uint256 i; i < count_; ++i) {
            // casting to 'uint64' is safe because the selector base plus a route count
            // stays far below the uint64 maximum
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 selector = uint64(10_000 + i);
            config.addChain(_defaultChainUpdate(selector));
            selectors[i] = selector;
        }
        vm.stopPrank();
        for (uint256 i; i < count_; ++i) {
            _armRmnProxy(selectors[i]);
        }
        return selectors;
    }

    // ========== BUCKET FILL MANIPULATION ========== //

    /// @notice Arms the RMN proxy for a selector so the pool's transfer validation passes.
    ///         MockRMNProxy reverts NotSet for a selector it was never told about; mind the
    ///         bytes16(uint128()) encoding the pool uses for the probe.
    function _armRmnProxy(uint64 chainSelector_) internal {
        rmnProxy.setIsCursed(bytes16(uint128(chainSelector_)), false);
    }

    /// @notice Consumes `amount_` base units from the outbound bucket through a real
    ///         lockOrBurn call from the mocked on-ramp. Mirrors the production flow by moving
    ///         the tokens to the pool first.
    function _consumeOutbound(uint64 chainSelector_, uint256 amount_) internal {
        // The pool handle is read before the prank so the view call does not consume it
        LockReleaseTokenPool rigPool = LockReleaseTokenPool(config.pool());
        _armRmnProxy(chainSelector_);
        ccipRouter.setOnRamp(onRamp);
        ohm.mint(address(rigPool), amount_);
        vm.prank(onRamp);
        rigPool.lockOrBurn(
            Pool.LockOrBurnInV1({
                receiver: abi.encode(makeAddr("bridgeReceiver")),
                remoteChainSelector: chainSelector_,
                originalSender: makeAddr("bridgeSender"),
                amount: amount_,
                localToken: address(ohm)
            })
        );
    }

    // ========== TIME HELPERS ========== //

    /// @notice Skips so the timestamp lands EXACTLY on the stored executableAt of an action.
    ///         Requires the current timestamp to be at or before that boundary.
    function _warpToExecutableAt(uint64 actionId_) internal {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId_);
        skip(uint256(action.executableAt) - vm.getBlockTimestamp());
    }

    /// @notice Skips so the timestamp lands EXACTLY on the stored expiresAt of an action.
    ///         Requires the current timestamp to be at or before that boundary.
    function _warpToExpiresAt(uint64 actionId_) internal {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId_);
        skip(uint256(action.expiresAt) - vm.getBlockTimestamp());
    }

    // ========== EXPECTED STATE HASHES ========== //

    /// @notice Recomputes the rate limits state hash of a route from the live pool, per the
    ///         documented preimage: (domain, selector, outbound isEnabled/capacity/rate,
    ///         inbound isEnabled/capacity/rate). Fill levels and refill timestamps are
    ///         excluded on purpose.
    function _expectedRateLimitsHash(uint64 chainSelector_) internal view returns (bytes32) {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        ICCIPRateLimiter.TokenBucket memory outbound = rigPool.getCurrentOutboundRateLimiterState(
            chainSelector_
        );
        ICCIPRateLimiter.TokenBucket memory inbound = rigPool.getCurrentInboundRateLimiterState(
            chainSelector_
        );
        return
            keccak256(
                abi.encode(
                    timelock.RATE_LIMITS_DOMAIN(),
                    chainSelector_,
                    outbound.isEnabled,
                    outbound.capacity,
                    outbound.rate,
                    inbound.isEnabled,
                    inbound.capacity,
                    inbound.rate
                )
            );
    }

    /// @notice Recomputes the remote pools state hash of a route from the live pool, per the
    ///         documented preimage: (domain, selector, count, XOR of keccak256 over the raw
    ///         bytes of every accepted remote pool).
    function _expectedRemotePoolsHash(uint64 chainSelector_) internal view returns (bytes32) {
        bytes[] memory remotePools = ICCIPTokenPoolAdmin(config.pool()).getRemotePools(
            chainSelector_
        );
        uint256 count = remotePools.length;
        bytes32 aggregate;
        for (uint256 i; i < count; ++i) {
            aggregate ^= keccak256(remotePools[i]);
        }
        return
            keccak256(abi.encode(timelock.REMOTE_POOLS_DOMAIN(), chainSelector_, count, aggregate));
    }

    /// @notice Recomputes the route identity state hash from the live pool, per the
    ///         documented preimage: (domain, selector, isSupportedChain, remoteToken).
    function _expectedRouteIdentityHash(uint64 chainSelector_) internal view returns (bytes32) {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        return
            keccak256(
                abi.encode(
                    timelock.ROUTE_IDENTITY_DOMAIN(),
                    chainSelector_,
                    rigPool.isSupportedChain(chainSelector_),
                    rigPool.getRemoteToken(chainSelector_)
                )
            );
    }

    /// @notice Recomputes the allowlist state hash from the live pool, per the documented
    ///         preimage: (domain, allowListEnabled, count, XOR of keccak256(abi.encode(member))
    ///         over every allowlisted address).
    function _expectedAllowListHash() internal view returns (bytes32) {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        address[] memory allowList = rigPool.getAllowList();
        uint256 count = allowList.length;
        bytes32 aggregate;
        for (uint256 i; i < count; ++i) {
            aggregate ^= keccak256(abi.encode(allowList[i]));
        }
        return
            keccak256(
                abi.encode(
                    timelock.ALLOWLIST_DOMAIN(),
                    rigPool.getAllowListEnabled(),
                    count,
                    aggregate
                )
            );
    }

    // ========== RESERVATION ASSERTIONS ========== //

    /// @notice Asserts that all three route domain keys of a selector are reserved by one
    ///         action.
    function _assertRouteKeysHeldBy(
        uint64 chainSelector_,
        uint64 actionId_,
        string memory label_
    ) internal view {
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(chainSelector_)),
            actionId_,
            string.concat(label_, ": rate limits key owner")
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(chainSelector_)),
            actionId_,
            string.concat(label_, ": remote pools key owner")
        );
        assertEq(
            timelock.pendingActionId(timelock.getRouteIdentityKey(chainSelector_)),
            actionId_,
            string.concat(label_, ": route identity key owner")
        );
    }

    /// @notice Asserts that all three route domain keys of a selector are free.
    function _assertRouteKeysFree(uint64 chainSelector_, string memory label_) internal view {
        assertEq(
            timelock.pendingActionId(timelock.getRateLimitsKey(chainSelector_)),
            0,
            string.concat(label_, ": rate limits key should be free")
        );
        assertEq(
            timelock.pendingActionId(timelock.getRemotePoolsKey(chainSelector_)),
            0,
            string.concat(label_, ": remote pools key should be free")
        );
        assertEq(
            timelock.pendingActionId(timelock.getRouteIdentityKey(chainSelector_)),
            0,
            string.concat(label_, ": route identity key should be free")
        );
    }

    /// @notice Asserts the complete stored shape of a freshly queued single-sub-action
    ///         action: metadata, timestamps, the stored sub-action triple, the destination,
    ///         and the reserved keys with their recorded hashes. Call in the same block as
    ///         the queueing and before any delay change, since the timestamp assertions
    ///         recompute executableAt from the live delay.
    function _assertQueuedSingleAction(
        uint64 actionId_,
        address proposer_,
        bytes4 selector_,
        bytes memory payload_,
        bytes32[] memory keys_,
        bytes32[] memory expectedHashes_
    ) internal view {
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId_);
        // queuedAt = now; executableAt = queuedAt + timelockDelay; expiresAt = executableAt
        // + EXECUTION_WINDOW (3 days)
        uint48 timestamp = uint48(vm.getBlockTimestamp());
        assertEq(action.proposer, proposer_, "stored proposer");
        assertEq(action.queuedAt, timestamp, "stored queuedAt");
        assertEq(
            action.executableAt,
            timestamp + timelock.timelockDelay(),
            "stored executableAt should be queuedAt plus the delay"
        );
        assertEq(
            action.expiresAt,
            action.executableAt + timelock.EXECUTION_WINDOW(),
            "stored expiresAt should be executableAt plus the execution window"
        );
        assertFalse(action.executed, "the action should not be executed");
        assertFalse(action.cancelled, "the action should not be cancelled");

        assertEq(timelock.getQueuedActionLength(actionId_), 1, "stored sub-action count");
        (address target, bytes4 storedSelector, bytes memory storedPayload) = timelock
            .getQueuedSubAction(actionId_, 0);
        assertEq(target, address(config), "stored sub-action target");
        assertEq(storedSelector, selector_, "stored sub-action selector");
        assertEq(storedPayload, payload_, "stored sub-action payload");

        assertEq(
            timelock.getQueuedConfigDestination(actionId_, 0),
            address(config),
            "stored config destination"
        );
        assertEq(
            timelock.getQueuedConfigStateCount(actionId_, 0),
            keys_.length,
            "stored config state count"
        );
        for (uint256 i; i < keys_.length; ++i) {
            (bytes32 key, bytes32 expectedStateHash) = timelock.getQueuedConfigState(
                actionId_,
                0,
                i
            );
            assertEq(key, keys_[i], "stored config state key");
            assertEq(expectedStateHash, expectedHashes_[i], "stored config state hash");
            assertEq(
                timelock.pendingActionId(keys_[i]),
                actionId_,
                "the stored key should be reserved by the action"
            );
        }
    }

    // ========== LOG HELPERS ========== //

    /// @notice Counts the recorded logs of one emitter carrying one event signature.
    function _countLogs(
        Vm.Log[] memory logs_,
        address emitter_,
        bytes32 topicZero_
    ) internal pure returns (uint256 count) {
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter == emitter_ && logs_[i].topics[0] == topicZero_) ++count;
        }
        return count;
    }

    /// @notice Counts the recorded logs of one emitter, regardless of the event.
    function _countLogsFrom(
        Vm.Log[] memory logs_,
        address emitter_
    ) internal pure returns (uint256 count) {
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter == emitter_) ++count;
        }
        return count;
    }

    /// @notice Returns the index of the first recorded log of one emitter carrying one event
    ///         signature, failing the test with the label when no such log exists. Serves the
    ///         ordered-scan assertions of the event-interleaving cases.
    function _indexOfLog(
        Vm.Log[] memory logs_,
        address emitter_,
        bytes32 topicZero_,
        string memory label_
    ) internal pure returns (uint256 index) {
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter == emitter_ && logs_[i].topics[0] == topicZero_) return i;
        }
        revert(string.concat(label_, ": expected log not found"));
    }

    // ========== REVERT EXPECTATION HELPERS ========== //

    function _expectRevertRequireRole(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectRevertNotAuthorised() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    function _expectRevertNotDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    function _expectRevertNotConfigOperator(address currentOperator_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigTimelock.CCIPTokenPoolConfigTimelock_NotConfigOperator.selector,
                currentOperator_
            )
        );
    }

    function _expectRevertConfigKeyPending(bytes32 key_, uint64 pendingActionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key_,
                pendingActionId_
            )
        );
    }

    function _expectRevertConfigStateChanged(
        uint64 actionId_,
        uint256 index_,
        bytes32 key_,
        bytes32 expectedStateHash_,
        bytes32 currentStateHash_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId_,
                index_,
                key_,
                expectedStateHash_,
                currentStateHash_
            )
        );
    }

    function _expectRevertTimelockDelayInvalid(uint48 delay_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                timelock.MIN_TIMELOCK_DELAY(),
                timelock.MAX_TIMELOCK_DELAY()
            )
        );
    }

    // ========== LIFECYCLE MODIFIERS ========== //

    /// @dev The admin enables the timelock from the setUp base state
    modifier givenEnabled() {
        vm.prank(admin);
        timelock.enable("");
        _;
    }

    /// @dev The admin disables the timelock; composes after givenEnabled
    modifier givenDisabled() {
        vm.prank(admin);
        timelock.disable("");
        _;
    }

    /// @dev The emergency role disables the timelock; composes after givenEnabled
    modifier givenDisabledByEmergency() {
        vm.prank(emergency);
        timelock.disable("");
        _;
    }

    /// @dev The bridge admin re-enables the timelock within grace; composes after
    ///      givenDisabled. Skips one day first, so the re-enable transition lands mid-window
    ///      with a timestamp distinct from the disable transition.
    modifier givenReEnabled() {
        skip(1 days);
        vm.prank(bridgeAdmin);
        timelock.reEnable();
        _;
    }

    /// @dev Lands exactly at lastTransitionAt + gracePeriod; composes after givenDisabled
    modifier givenTimestampAtGraceDeadline() {
        uint256 deadline = uint256(timelock.lastTransitionAt()) + timelock.gracePeriod();
        skip(deadline - vm.getBlockTimestamp());
        _;
    }

    /// @dev Lands exactly at graceDeadline + 1 and exposes the deadline through graceDeadline;
    ///      composes after givenDisabled
    modifier givenGraceExpired() {
        uint256 deadline = uint256(timelock.lastTransitionAt()) + timelock.gracePeriod();
        // casting to 'uint48' is safe because the sum of a uint48 timestamp and a uint32
        // period fits in 49 bits, far below the uint48 maximum for realistic test times
        // forge-lint: disable-next-line(unsafe-typecast)
        graceDeadline = uint48(deadline);
        skip(deadline + 1 - vm.getBlockTimestamp());
        _;
    }

    /// @dev The kernel executor deactivates the timelock policy
    modifier givenPolicyDeactivatedInKernel() {
        kernel.executeAction(Actions.DeactivatePolicy, address(timelock));
        _;
    }

    /// @dev The admin disables the CONFIG policy; it stays active in the kernel
    modifier givenConfigDisabled() {
        vm.prank(admin);
        config.disable("");
        _;
    }

    /// @dev The kernel executor deactivates the CONFIG policy
    modifier givenConfigDeactivatedInKernel() {
        kernel.executeAction(Actions.DeactivatePolicy, address(config));
        _;
    }

    /// @dev The admin points the config's operator seat at thirdParty
    modifier givenOperatorRotated() {
        vm.prank(admin);
        config.setConfigOperator(thirdParty);
        _;
    }

    /// @dev The admin revokes the config's operator seat (sets the zero address)
    modifier givenOperatorRevoked() {
        vm.prank(admin);
        config.setConfigOperator(address(0));
        _;
    }

    /// @dev The admin proposes thirdParty through config.transferPoolOwnership and the
    ///      third party accepts, so the config no longer owns the pool
    modifier givenPoolOwnershipLost() {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
        vm.prank(thirdParty);
        rigPool.acceptOwnership();
        _;
    }

    // ========== ROUTE FIXTURES ========== //

    /// @dev The admin adds CHAIN_SELECTOR_A through the config directly, with enabled default
    ///      limits and two remote pools, and arms the RMN proxy for the selector
    modifier givenChainAdded() {
        _armRmnProxy(CHAIN_SELECTOR_A);
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
        _;
    }

    /// @dev The admin adds CHAIN_SELECTOR_B through the config directly, with its own remote
    ///      token and a single remote pool, and arms the RMN proxy for the selector
    modifier givenSecondChainAdded() {
        _armRmnProxy(CHAIN_SELECTOR_B);
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = REMOTE_POOL_B;
        vm.prank(admin);
        config.addChain(
            _chainUpdate(
                CHAIN_SELECTOR_B,
                remotePools,
                REMOTE_TOKEN_B,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            )
        );
        _;
    }

    /// @dev The admin adds CHAIN_SELECTOR_A through the config with a single remote pool
    modifier givenChainAddedWithSinglePool() {
        _armRmnProxy(CHAIN_SELECTOR_A);
        vm.prank(admin);
        config.addChain(
            _chainUpdate(
                CHAIN_SELECTOR_A,
                _singleRemotePool(),
                REMOTE_TOKEN,
                _defaultOutboundConfig(),
                _defaultInboundConfig()
            )
        );
        _;
    }

    /// @dev A containment-role holder disables route A through config.disableChain; composes
    ///      after givenChainAdded
    modifier givenRouteContained() {
        _containRoute(CHAIN_SELECTOR_A, emergency);
        _;
    }

    /// @dev Route A is seeded directly on the pool (pranking the pool owner of the moment)
    ///      with the outbound bucket disabled ({false, 0, 0}) and the inbound bucket at the
    ///      default configuration; a shape the config's validated paths cannot produce
    modifier givenRouteWithDisabledOutboundBucket() {
        _armRmnProxy(CHAIN_SELECTOR_A);
        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            _defaultRemotePools(),
            REMOTE_TOKEN,
            _disabledConfig(),
            _defaultInboundConfig()
        );
        _;
    }

    /// @dev Route A is seeded directly on the pool with the outbound bucket at the default
    ///      configuration and the inbound bucket disabled ({false, 0, 0})
    modifier givenRouteWithDisabledInboundBucket() {
        _armRmnProxy(CHAIN_SELECTOR_A);
        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            _defaultRemotePools(),
            REMOTE_TOKEN,
            _defaultOutboundConfig(),
            _disabledConfig()
        );
        _;
    }

    // ========== QUEUE AND TIME FIXTURES ========== //

    /// @dev The bridge admin queues the canonical single action (queueSetChainRateLimits on
    ///      route A with non-default values) and exposes its id through queuedActionId;
    ///      composes after givenEnabled and givenChainAdded
    modifier givenActionQueued() {
        queuedActionId = _queueRateLimitAction(CHAIN_SELECTOR_A);
        _;
    }

    /// @dev Skips to the executableAt of the queued action; composes after givenActionQueued
    modifier givenActionReady() {
        _warpToExecutableAt(queuedActionId);
        _;
    }

    /// @dev Skips to expiresAt + 1 of the queued action; composes after givenActionQueued
    modifier givenActionExpired() {
        _warpToExpiresAt(queuedActionId);
        skip(1);
        _;
    }

    /// @dev The proposer cancels the queued action; composes after givenActionQueued
    modifier givenActionCancelled() {
        vm.prank(bridgeAdmin);
        timelock.cancelQueuedAction(queuedActionId);
        _;
    }

    /// @dev A third party executes the queued action once ready; composes after
    ///      givenActionReady
    modifier givenActionExecuted() {
        vm.prank(thirdParty);
        timelock.executeQueuedAction(queuedActionId);
        _;
    }

    // ========== DEPLOY VARIANTS ========== //

    /// @dev Rebinds pool, config and timelock to a second full stack whose lock/release pool
    ///      is deployed with a two-entry allowlist (allowListedOne, allowListedTwo), matching
    ///      the primary rig's default state otherwise: both policies activated, config
    ///      enabled, pool ownership accepted, operator seat set to the timelock, timelock
    ///      disabled. Runs before the other modifiers.
    modifier givenAllowListPoolRig() {
        address[] memory allowList = new address[](2);
        allowList[0] = allowListedOne;
        allowList[1] = allowListedTwo;
        pool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            OHM_DECIMALS,
            allowList,
            address(rmnProxy),
            true,
            address(ccipRouter)
        );
        vm.label(address(pool), "allowListPool");
        config = new CCIPTokenPoolConfig(kernel, address(pool), GRACE_PERIOD);
        vm.label(address(config), "configAllowListRig");
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        pool.transferOwnership(address(config));
        timelock = new CCIPTokenPoolConfigTimelock(
            kernel,
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(timelock), "timelockAllowListRig");
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        vm.startPrank(admin);
        config.enable("");
        config.acceptPoolOwnership();
        config.setConfigOperator(address(timelock));
        vm.stopPrank();
        _;
    }
}
