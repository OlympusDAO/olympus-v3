// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IBurnMintERC20} from "@chainlink-ccip-1.6.0/shared/token/ERC20/IBurnMintERC20.sol";
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {BurnMintTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/BurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CCIPBridgeConfig} from "src/policies/bridge/CCIPBridgeConfig.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

/// @notice Shared abstract base of the CCIPBridgeConfig test suite.
/// @dev    The setup deploys the full Kernel stack (Kernel, OlympusRoles, RolesAdmin), a real
///         Chainlink lock/release pool with liquidity acceptance and an empty allowlist over
///         MockOhm at 9 decimals, a real burn/mint pool over the same token as the second
///         deploy variant, activates the policy and grants the admin, emergency, bridge admin
///         and bridge rate limiter roles to distinct accounts.
///
///         Default state after setUp: the policy is activated in the kernel but DISABLED, the
///         config operator is unset, and the primary pool ownership is PENDING to the config
///         (the test contract deployed the pool, owns it and has proposed the config). The
///         burn/mint pool stays owned by the test contract until givenBurnMintPoolRig runs.
///
///         Default constants, in base units of the 9-decimals MockOhm: outbound rate limiter
///         {true, 10_000, 100}, inbound {true, 20_000, 200} (deliberately distinct per
///         direction so cross-wired assertions fail; skip(10) refills 1_000 outbound units).
///         Remote addresses are EVM-shaped ABI encodings of labelled accounts. The liquidity
///         source pool is funded with 1_000_000_000 base units (1 OHM).
///
///         Time moves only with skip() and reads only with vm.getBlockTimestamp(). Every
///         deployed contract is labelled; test accounts come from makeAddr.
///
///         Prank convention: read every contract handle and address needed for a pranked
///         call before vm.prank, because any external view call placed between the prank and
///         the target call consumes the prank.
///
///         Log convention: the emit statement that follows vm.expectEmit is itself a real
///         log from the test contract and lands in vm.getRecordedLogs(), so count and
///         absence assertions over recorded logs filter by emitter and topic zero, never by
///         the total array length.
abstract contract CCIPBridgeConfigTest is Test {
    // ========== KERNEL STACK ========== //

    Kernel internal kernel;
    OlympusRoles internal rolesModule;
    RolesAdmin internal rolesAdmin;

    // ========== POOL RIG ========== //

    MockOhm internal ohm;
    MockCCIPRouter internal ccipRouter;
    MockRMNProxy internal rmnProxy;
    LockReleaseTokenPool internal pool;
    BurnMintTokenPool internal burnMintPool;

    /// @notice The second lock/release pool used as the liquidity source; deployed by the
    ///         givenLiquiditySource* modifiers and owned by the test contract.
    LockReleaseTokenPool internal sourcePool;

    // ========== POLICY UNDER TEST ========== //

    CCIPBridgeConfig internal config;

    // ========== ACCOUNTS ========== //

    address internal admin;
    address internal emergency;
    address internal bridgeAdmin;
    address internal bridgeRateLimiter;
    address internal operator;
    address internal thirdParty;
    address internal onRamp;
    address internal offRamp;
    address internal allowListedOne;
    address internal allowListedTwo;

    // ========== DEFAULT REMOTE ADDRESSES (EVM-shaped, set in setUp) ========== //

    bytes internal REMOTE_TOKEN;
    bytes internal REMOTE_POOL_ONE;
    bytes internal REMOTE_POOL_TWO;
    bytes internal REMOTE_TOKEN_B;
    bytes internal REMOTE_POOL_B;

    // ========== CONSTANTS ========== //

    uint32 internal constant GRACE_PERIOD = 3 days;
    uint64 internal constant CHAIN_SELECTOR_A = 1111;
    uint64 internal constant CHAIN_SELECTOR_B = 2222;

    uint8 internal constant OHM_DECIMALS = 9;

    /// @notice Default rate limiter constants, in OHM base units (9 decimals).
    uint128 internal constant DEFAULT_OUTBOUND_CAPACITY = 10_000;
    uint128 internal constant DEFAULT_OUTBOUND_RATE = 100;
    uint128 internal constant DEFAULT_INBOUND_CAPACITY = 20_000;
    uint128 internal constant DEFAULT_INBOUND_RATE = 200;

    /// @notice Funding of the liquidity source pool: 1 OHM in base units (9 decimals).
    uint256 internal constant SOURCE_POOL_FUNDING = 1_000_000_000;

    // ========== EXPOSED MODIFIER STATE ========== //

    /// @notice The grace deadline computed by givenGraceExpired, for error-argument asserts.
    uint48 internal graceDeadline;

    // ========== SETUP ========== //

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        bridgeAdmin = makeAddr("bridgeAdmin");
        bridgeRateLimiter = makeAddr("bridgeRateLimiter");
        operator = makeAddr("operator");
        thirdParty = makeAddr("thirdParty");
        onRamp = makeAddr("onRamp");
        offRamp = makeAddr("offRamp");
        allowListedOne = makeAddr("allowListedOne");
        allowListedTwo = makeAddr("allowListedTwo");

        REMOTE_TOKEN = abi.encode(makeAddr("remoteToken"));
        REMOTE_POOL_ONE = abi.encode(makeAddr("remotePoolOne"));
        REMOTE_POOL_TWO = abi.encode(makeAddr("remotePoolTwo"));
        REMOTE_TOKEN_B = abi.encode(makeAddr("remoteTokenB"));
        REMOTE_POOL_B = abi.encode(makeAddr("remotePoolB"));

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
        burnMintPool = new BurnMintTokenPool(
            IBurnMintERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            address(ccipRouter)
        );
        vm.label(address(burnMintPool), "burnMintPool");

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

        config = new CCIPBridgeConfig(kernel, address(pool), GRACE_PERIOD);
        vm.label(address(config), "config");
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        // The test contract owns the pool; the config becomes the pending owner
        pool.transferOwnership(address(config));
    }

    // ========== DEPLOY HELPERS ========== //

    /// @notice Deploys a fresh, unactivated config instance for constructor-style tests.
    function _newConfig(
        address pool_,
        uint32 gracePeriod_
    ) internal returns (CCIPBridgeConfig newConfig) {
        newConfig = new CCIPBridgeConfig(kernel, pool_, gracePeriod_);
        vm.label(address(newConfig), "freshConfig");
        return newConfig;
    }

    /// @notice Deploys the funded liquidity source pool, optionally setting the primary pool
    ///         as its rebalancer. The test contract deploys and therefore owns it.
    function _deployLiquiditySource(bool rebalancerToPool_) internal {
        sourcePool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            true,
            address(ccipRouter)
        );
        vm.label(address(sourcePool), "sourcePool");
        ohm.mint(address(sourcePool), SOURCE_POOL_FUNDING);
        if (rebalancerToPool_) sourcePool.setRebalancer(address(pool));
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

    /// @notice Writes bucket configurations directly on the current rig's pool, impersonating
    ///         the pool owner. A seeding shortcut for shapes the config's validated paths
    ///         cannot produce; bypasses the policy entirely.
    function _setPoolRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(rigPool.owner());
        rigPool.setChainRateLimiterConfig(chainSelector_, outbound_, inbound_);
    }

    /// @notice Adds `count_` routes with default parameters and sequential selectors starting
    ///         at 10_000, as the admin. Requires the enabled policy owning the pool.
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

    /// @notice Consumes `amount_` base units from the inbound bucket through a real
    ///         releaseOrMint call from the mocked off-ramp. Funds the pool first (the release
    ///         transfers tokens out) and requires REMOTE_POOL_ONE to be an accepted remote
    ///         pool of the route.
    function _consumeInbound(uint64 chainSelector_, uint256 amount_) internal {
        // The pool handle is read before the prank so the view call does not consume it
        LockReleaseTokenPool rigPool = LockReleaseTokenPool(config.pool());
        _armRmnProxy(chainSelector_);
        ccipRouter.setOffRamp(offRamp);
        ohm.mint(address(rigPool), amount_);
        vm.prank(offRamp);
        rigPool.releaseOrMint(
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(makeAddr("bridgeSender")),
                remoteChainSelector: chainSelector_,
                receiver: makeAddr("bridgeReceiver"),
                amount: amount_,
                localToken: address(ohm),
                sourcePoolAddress: REMOTE_POOL_ONE,
                sourcePoolData: "",
                offchainTokenData: ""
            })
        );
    }

    /// @notice Drains both buckets of a route down to the target fill levels without touching
    ///         their configurations, all in the current block so no refill lands in between.
    /// @dev    Targets at or above two units use a temporary capacity clamp through
    ///         setChainRateLimits ({true, target, 1}, then the original configuration in the
    ///         same block). Targets of zero or one clamp to two first and then consume the
    ///         remainder through a real transfer, because two is the smallest capacity of an
    ///         enabled configuration with a rate of one. Requires the enabled policy with pool
    ///         authority and targets at or below the current fills; a direction left at its
    ///         current fill is a no-op.
    function _setBucketFills(
        uint64 chainSelector_,
        uint128 outboundTokens_,
        uint128 inboundTokens_
    ) internal {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        ICCIPRateLimiter.Config memory outboundConfig = _toConfig(
            rigPool.getCurrentOutboundRateLimiterState(chainSelector_)
        );
        ICCIPRateLimiter.Config memory inboundConfig = _toConfig(
            rigPool.getCurrentInboundRateLimiterState(chainSelector_)
        );

        uint128 outboundClamp = outboundTokens_ < 2 ? 2 : outboundTokens_;
        uint128 inboundClamp = inboundTokens_ < 2 ? 2 : inboundTokens_;

        vm.startPrank(admin);
        config.setChainRateLimits(
            chainSelector_,
            _rateLimiterConfig(true, outboundClamp, 1),
            _rateLimiterConfig(true, inboundClamp, 1)
        );
        config.setChainRateLimits(chainSelector_, outboundConfig, inboundConfig);
        vm.stopPrank();

        if (outboundTokens_ < 2) _consumeOutbound(chainSelector_, 2 - outboundTokens_);
        if (inboundTokens_ < 2) _consumeInbound(chainSelector_, 2 - inboundTokens_);
    }

    // ========== AUTHORIZATION PROBE ========== //

    /// @notice Probes the route-function authorization of an account without any route setup.
    ///         Calls applyAllowListUpdates on the primary (no-allowlist) rig: an unauthorized
    ///         caller stops at NotAuthorised, an authorized one reaches the first validation
    ///         check and reverts AllowListNotEnabled.
    function _isAuthorizedForRouteFunctions(address account_) internal returns (bool authorized) {
        vm.prank(account_);
        try config.applyAllowListUpdates(new address[](0), new address[](0)) {
            revert("route probe: the call must revert on the primary rig");
        } catch (bytes memory reason_) {
            // casting to 'bytes4' is deliberate: only the error selector of the revert
            // reason is inspected
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorSelector = bytes4(reason_);
            if (errorSelector == IPolicyAdmin.NotAuthorised.selector) return false;
            if (errorSelector == ICCIPTokenPoolAdmin.AllowListNotEnabled.selector) return true;
            revert("route probe: unexpected revert reason");
        }
    }

    // ========== ROUTE SNAPSHOTS ========== //

    struct RouteSnapshot {
        bytes remoteToken;
        bytes[] remotePools;
        ICCIPRateLimiter.TokenBucket outbound;
        ICCIPRateLimiter.TokenBucket inbound;
    }

    function _snapshotRoute(uint64 chainSelector_) internal view returns (RouteSnapshot memory) {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        return
            RouteSnapshot({
                remoteToken: rigPool.getRemoteToken(chainSelector_),
                remotePools: rigPool.getRemotePools(chainSelector_),
                outbound: rigPool.getCurrentOutboundRateLimiterState(chainSelector_),
                inbound: rigPool.getCurrentInboundRateLimiterState(chainSelector_)
            });
    }

    /// @notice Asserts that a route matches an earlier snapshot. Compare within the block the
    ///         snapshot was taken in, so the lazy refill projection cannot drift the fills.
    function _assertRouteEqualsSnapshot(
        uint64 chainSelector_,
        RouteSnapshot memory snapshot_,
        string memory label_
    ) internal view {
        RouteSnapshot memory current = _snapshotRoute(chainSelector_);
        assertEq(
            current.remoteToken,
            snapshot_.remoteToken,
            string.concat(label_, ": remote token changed")
        );
        _assertRemotePoolsEq(
            current.remotePools,
            snapshot_.remotePools,
            string.concat(label_, ": remote pools")
        );
        _assertBucketEq(current.outbound, snapshot_.outbound, string.concat(label_, ": outbound"));
        _assertBucketEq(current.inbound, snapshot_.inbound, string.concat(label_, ": inbound"));
    }

    // ========== ASSERTION HELPERS ========== //

    /// @notice Asserts every field of a bucket: the configuration and the fill together.
    function _assertBucket(
        ICCIPRateLimiter.TokenBucket memory bucket_,
        bool isEnabled_,
        uint128 capacity_,
        uint128 rate_,
        uint128 tokens_,
        string memory label_
    ) internal pure {
        assertEq(bucket_.isEnabled, isEnabled_, string.concat(label_, ": isEnabled"));
        assertEq(bucket_.capacity, capacity_, string.concat(label_, ": capacity"));
        assertEq(bucket_.rate, rate_, string.concat(label_, ": rate"));
        assertEq(bucket_.tokens, tokens_, string.concat(label_, ": tokens"));
    }

    function _assertBucketEq(
        ICCIPRateLimiter.TokenBucket memory actual_,
        ICCIPRateLimiter.TokenBucket memory expected_,
        string memory label_
    ) internal pure {
        _assertBucket(
            actual_,
            expected_.isEnabled,
            expected_.capacity,
            expected_.rate,
            expected_.tokens,
            label_
        );
    }

    function _assertConfigEq(
        ICCIPRateLimiter.Config memory actual_,
        ICCIPRateLimiter.Config memory expected_,
        string memory label_
    ) internal pure {
        assertEq(actual_.isEnabled, expected_.isEnabled, string.concat(label_, ": isEnabled"));
        assertEq(actual_.capacity, expected_.capacity, string.concat(label_, ": capacity"));
        assertEq(actual_.rate, expected_.rate, string.concat(label_, ": rate"));
    }

    function _assertRemotePoolsEq(
        bytes[] memory actual_,
        bytes[] memory expected_,
        string memory label_
    ) internal pure {
        assertEq(actual_.length, expected_.length, string.concat(label_, ": length"));
        for (uint256 i; i < expected_.length; ++i) {
            assertEq(actual_[i], expected_[i], string.concat(label_, ": entry"));
        }
    }

    /// @notice Extracts the configuration fields of a bucket, mirroring the config contract.
    function _toConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (ICCIPRateLimiter.Config memory) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: bucket_.isEnabled,
                capacity: bucket_.capacity,
                rate: bucket_.rate
            });
    }

    // ========== BUCKET GETTERS ========== //

    /// @notice Reads the outbound bucket of the current rig's pool, projected to now.
    function _outboundBucket(
        uint64 chainSelector_
    ) internal view returns (ICCIPRateLimiter.TokenBucket memory) {
        return
            ICCIPTokenPoolAdmin(config.pool()).getCurrentOutboundRateLimiterState(chainSelector_);
    }

    /// @notice Reads the inbound bucket of the current rig's pool, projected to now.
    function _inboundBucket(
        uint64 chainSelector_
    ) internal view returns (ICCIPRateLimiter.TokenBucket memory) {
        return ICCIPTokenPoolAdmin(config.pool()).getCurrentInboundRateLimiterState(chainSelector_);
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

    function _expectRevertOnlyCallableByOwner() internal {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector));
    }

    // ========== LIFECYCLE MODIFIERS ========== //

    /// @dev The admin enables the policy from the setUp base state
    modifier givenEnabled() {
        vm.prank(admin);
        config.enable("");
        _;
    }

    /// @dev The admin disables the policy; composes after givenEnabled
    modifier givenDisabled() {
        vm.prank(admin);
        config.disable("");
        _;
    }

    /// @dev The bridge admin re-enables the policy; composes after givenDisabled
    modifier givenReEnabled() {
        vm.prank(bridgeAdmin);
        config.reEnable();
        _;
    }

    /// @dev Lands exactly at deadline + 1 and exposes the deadline through graceDeadline;
    ///      composes after givenDisabled
    modifier givenGraceExpired() {
        uint256 deadline = uint256(config.lastTransitionAt()) + config.gracePeriod();
        // casting to 'uint48' is safe because the sum of a uint48 timestamp and a uint32
        // period fits in 49 bits, far below the uint48 maximum for realistic test times
        // forge-lint: disable-next-line(unsafe-typecast)
        graceDeadline = uint48(deadline);
        skip(deadline + 1 - vm.getBlockTimestamp());
        _;
    }

    /// @dev The admin sets the config operator to the operator account; composes after
    ///      givenEnabled
    modifier givenConfigOperatorSet() {
        vm.prank(admin);
        config.setConfigOperator(operator);
        _;
    }

    /// @dev The kernel executor deactivates the policy
    modifier givenPolicyDeactivatedInKernel() {
        kernel.executeAction(Actions.DeactivatePolicy, address(config));
        _;
    }

    // ========== POOL STATE MODIFIERS ========== //

    /// @dev The admin accepts the pending pool ownership; composes after givenEnabled
    modifier givenPoolOwnershipAccepted() {
        vm.prank(admin);
        config.acceptPoolOwnership();
        _;
    }

    /// @dev The admin proposes an unrelated third party through the config, and the third
    ///      party accepts; composes after givenPoolOwnershipAccepted
    modifier givenPoolOwnedByThirdParty() {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(admin);
        config.transferPoolOwnership(thirdParty);
        vm.prank(thirdParty);
        rigPool.acceptOwnership();
        _;
    }

    /// @dev The current pool owner sets the config policy as the pool rate limit admin,
    ///      whoever that owner is at composition time (the test contract on the never-enabled
    ///      rig, the config after acceptance, the third party after a migration)
    modifier givenConfigIsRateLimitAdmin() {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(rigPool.owner());
        rigPool.setRateLimitAdmin(address(config));
        _;
    }

    /// @dev The pool owner proposes the zero address, clearing the pending ownership slot;
    ///      runs while the test contract still owns the pool
    modifier givenPendingOwnershipCleared() {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(rigPool.owner());
        rigPool.transferOwnership(address(0));
        _;
    }

    /// @dev The pool owner proposes an unrelated third party; runs while the test contract
    ///      still owns the pool
    modifier givenPendingOwnershipToThirdParty() {
        ICCIPTokenPoolAdmin rigPool = ICCIPTokenPoolAdmin(config.pool());
        vm.prank(rigPool.owner());
        rigPool.transferOwnership(thirdParty);
        _;
    }

    /// @dev Rebinds config to the deploy variant over the real BurnMintTokenPool, whose
    ///      ERC165 answer lacks the liquidity container identifier; the pool handle on this
    ///      rig is burnMintPool, since the pool variable is typed as LockReleaseTokenPool.
    ///      The variant is activated and the burn/mint pool ownership becomes pending to it,
    ///      matching the primary rig's default state. Runs before the other modifiers.
    modifier givenBurnMintPoolRig() {
        config = new CCIPBridgeConfig(kernel, address(burnMintPool), GRACE_PERIOD);
        vm.label(address(config), "configBurnMintRig");
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        burnMintPool.transferOwnership(address(config));
        _;
    }

    /// @dev Deploys a second lock/release pool funded with OHM whose rebalancer is the
    ///      primary pool, as the source for transferLiquidity
    modifier givenLiquiditySourceConfigured() {
        _deployLiquiditySource(true);
        _;
    }

    /// @dev Deploys a second funded lock/release pool whose rebalancer is left unset
    modifier givenLiquiditySourceRebalancerUnset() {
        _deployLiquiditySource(false);
        _;
    }

    // ========== ROUTE STATE MODIFIERS ========== //

    /// @dev The admin adds CHAIN_SELECTOR_A with enabled default limits and two remote pools;
    ///      composes after givenPoolOwnershipAccepted
    modifier givenChainAdded() {
        vm.prank(admin);
        config.addChain(_defaultChainUpdate(CHAIN_SELECTOR_A));
        _;
    }

    /// @dev The admin adds CHAIN_SELECTOR_B with enabled default limits and its own remote
    ///      token and pool, so sibling-independence assertions cannot alias; composes after
    ///      givenPoolOwnershipAccepted
    modifier givenSecondChainAdded() {
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

    /// @dev The admin adds CHAIN_SELECTOR_A with a single remote pool; composes after
    ///      givenPoolOwnershipAccepted
    modifier givenChainAddedWithSinglePool() {
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

    /// @dev CHAIN_SELECTOR_A is seeded directly on the pool with the outbound bucket disabled
    ///      ({false, 0, 0}) and the inbound bucket at the default configuration, while the
    ///      test contract still owns the pool; runs before the ownership handover
    modifier givenRouteWithDisabledOutboundBucket() {
        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            _defaultRemotePools(),
            REMOTE_TOKEN,
            _disabledConfig(),
            _defaultInboundConfig()
        );
        _;
    }

    /// @dev CHAIN_SELECTOR_A is seeded directly on the pool with the outbound bucket at the
    ///      default configuration and the inbound bucket disabled ({false, 0, 0}), while the
    ///      test contract still owns the pool; runs before the ownership handover
    modifier givenRouteWithDisabledInboundBucket() {
        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            _defaultRemotePools(),
            REMOTE_TOKEN,
            _defaultOutboundConfig(),
            _disabledConfig()
        );
        _;
    }

    /// @dev CHAIN_SELECTOR_A is seeded directly on the pool with an empty remote pool list
    ///      while the test contract still owns the pool; runs before the ownership handover
    modifier givenRouteWithNoRemotePools() {
        _seedRouteOnPool(
            CHAIN_SELECTOR_A,
            new bytes[](0),
            REMOTE_TOKEN,
            _defaultOutboundConfig(),
            _defaultInboundConfig()
        );
        _;
    }

    /// @dev The emergency role contains CHAIN_SELECTOR_A through disableChain; composes after
    ///      givenChainAdded
    modifier givenRouteContained() {
        vm.prank(emergency);
        config.disableChain(CHAIN_SELECTOR_A);
        _;
    }

    /// @dev Rebinds config and pool to the deploy variant whose lock/release pool was
    ///      constructed with a non-empty allowlist (allowListedOne, allowListedTwo). The
    ///      variant is activated and the pool ownership becomes pending to it, matching the
    ///      primary rig's default state. Runs before the other modifiers.
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
        config = new CCIPBridgeConfig(kernel, address(pool), GRACE_PERIOD);
        vm.label(address(config), "configAllowListRig");
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        pool.transferOwnership(address(config));
        _;
    }
}
