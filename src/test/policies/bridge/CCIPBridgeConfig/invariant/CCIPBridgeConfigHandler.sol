// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";

import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {CCIPBridgeConfig} from "src/policies/bridge/CCIPBridgeConfig.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";
import {MockRouterCandidate} from "src/test/policies/bridge/mocks/MockRouterCandidate.sol";
import {MockVersionedCCIPRouter} from "src/test/policies/bridge/mocks/MockVersionedCCIPRouter.sol";

/// @notice Invariant-test handler that drives CCIPBridgeConfig through its production entry
///         points over a small fixed selector space, with every action pranked as the role
///         that owns it. The handler is guarded: every action either no-ops when its
///         preconditions do not hold or succeeds, so the suite runs with fail-on-revert and
///         any unexpected revert surfaces as a failure.
/// @dev    Two kinds of properties live here rather than in the invariant functions:
///           1. Ghost flags and running totals for history-dependent claims, compared at the
///              action boundary (a bucket fill raised beyond the two-unit floor, a reEnable
///              succeeding past the grace deadline, an unauthorized caller succeeding
///              anywhere, a direct bucket write without the pool's rate limit grant, and the
///              amount moved out of the liquidity source).
///           2. Action postconditions that can only be observed against the pre-state of the
///              same call (lifecycle, operator and grace window actions leave the pool
///              untouched, the remote token replacement preserves everything but the token,
///              containment clamps without refilling, consumption decrements exactly, a
///              liquidity transfer conserves the token supply, a rejected router candidate
///              leaves the router in place, an ownership round trip restores the pool state).
///         Deliberate negative probes (reEnable past the deadline, the rejected router
///         candidates, the outsider probe, the rate limit bypass probe) use try/catch or a
///         low-level call; every catch tolerates only the expected error and bubbles anything
///         else.
///
///         The pool ownership rests with the config at every action boundary: the migration
///         action moves it to a candidate and back inside a single call, so no partial
///         migration can freeze the owner-gated actions for the rest of a sequence.
contract CCIPBridgeConfigHandler is Test {
    // ========== RIG REFERENCES ========== //

    CCIPBridgeConfig public immutable config;
    ICCIPTokenPoolAdmin public immutable pool;
    MockOhm internal immutable ohm;
    MockCCIPRouter internal immutable ccipRouter;
    MockRMNProxy internal immutable rmnProxy;

    // ========== ACTORS ========== //

    address public immutable admin;
    address public immutable emergency;
    address public immutable bridgeAdmin;
    address public immutable bridgeRateLimiter;
    address public immutable operatorPrimary;
    address public immutable operatorAlternate;
    address public immutable outsider;
    address internal immutable onRamp;
    address internal immutable offRamp;

    /// @notice The account the ownership migration action hands the pool to and takes it back
    ///         from within one call.
    address public immutable ownershipCandidate;

    /// @notice The unvalidated candidate the rebalancer action writes.
    address public immutable rebalancerCandidate;

    /// @notice The account the rate limit admin action grants and revokes, and the caller of
    ///         the bypass probe.
    address public immutable rateLimitAdminCandidate;

    // ========== LIQUIDITY SOURCE ========== //

    /// @notice The funded lock/release pool whose rebalancer is the pool under management; the
    ///         only account that can move its tokens is therefore the config's transfer path.
    address public immutable liquiditySource;

    // ========== TRACKED SELECTORS AND CANDIDATES ========== //

    uint64[5] public trackedSelectors;
    bytes[] internal tokenCandidates;
    bytes[] internal poolCandidates;

    // ========== ROUTER CANDIDATES ========== //

    /// @notice Candidates the config's probe accepts (a valid version string, the empty string
    ///         at exactly the minimum length, and undecodable data above it). They also serve
    ///         the pool's ramp lookups, so transfers keep working after an installation.
    MockVersionedCCIPRouter[3] internal acceptingRouters;

    /// @notice Candidates the probe rejects: a reverting answer and one below the minimum
    ///         return length.
    MockRouterCandidate[2] internal rejectingRouters;

    /// @notice A codeless candidate, rejected before the probe runs.
    address internal immutable codelessRouter;

    // ========== ACTION BOUNDS ========== //

    uint256 internal constant MAX_SKIP = 2 days;
    uint256 internal constant MAX_CAPACITY = 1_000_000_000_000;
    uint256 internal constant MAX_GRACE_PERIOD = 7 days;

    // ========== GHOST FLAGS (read by the invariant functions) ========== //

    /// @notice Set when any config-mediated bucket write leaves a fill above both its
    ///         pre-call projected level and the two-unit floor.
    bool public ghost_fillRaisedBeyondFloor;

    /// @notice Set when a reEnable call succeeds although the grace deadline has passed.
    bool public ghost_reEnabledPastGraceDeadline;

    /// @notice Set when the outsider succeeds on any state-changing config function.
    bool public ghost_unauthorizedCallSucceeded;

    /// @notice Set when an account that is neither the pool owner nor its rate limit admin
    ///         writes pool rate limits directly.
    bool public ghost_rateLimitBypassWithoutGrant;

    /// @notice The total moved out of the liquidity source through the config's transfer path,
    ///         in token base units.
    uint256 public ghost_liquidityMovedFromSource;

    // ========== COVERAGE COUNTERS ========== //

    uint256 public lifecycleTransitions;
    uint256 public reEnableProbesPastDeadline;
    uint256 public routesAdded;
    uint256 public routesRemoved;
    uint256 public remotePoolChanges;
    uint256 public remoteTokenReplacements;
    uint256 public rateLimitWrites;
    uint256 public containmentCalls;
    uint256 public bucketConsumptions;
    uint256 public outsiderProbes;
    uint256 public fillTransitionsChecked;
    uint256 public poolDigestChecks;
    uint256 public routerChanges;
    uint256 public routerRejections;
    uint256 public rebalancerChanges;
    uint256 public rateLimitAdminChanges;
    uint256 public rateLimitBypassProbes;
    uint256 public liquidityTransfers;
    uint256 public graceWindowUpdates;
    uint256 public ownershipRoundTrips;

    // ========== CONSTRUCTOR ========== //

    constructor(
        CCIPBridgeConfig config_,
        MockOhm ohm_,
        MockCCIPRouter ccipRouter_,
        MockRMNProxy rmnProxy_,
        address admin_,
        address emergency_,
        address bridgeAdmin_,
        address bridgeRateLimiter_,
        address operator_,
        address liquiditySource_
    ) {
        config = config_;
        pool = ICCIPTokenPoolAdmin(config_.pool());
        ohm = ohm_;
        ccipRouter = ccipRouter_;
        rmnProxy = rmnProxy_;
        admin = admin_;
        emergency = emergency_;
        bridgeAdmin = bridgeAdmin_;
        bridgeRateLimiter = bridgeRateLimiter_;
        operatorPrimary = operator_;
        operatorAlternate = makeAddr("operatorAlternate");
        outsider = makeAddr("outsider");
        onRamp = makeAddr("handlerOnRamp");
        offRamp = makeAddr("handlerOffRamp");
        liquiditySource = liquiditySource_;
        ownershipCandidate = makeAddr("ownershipCandidate");
        rebalancerCandidate = makeAddr("rebalancerCandidate");
        rateLimitAdminCandidate = makeAddr("rateLimitAdminCandidate");
        codelessRouter = makeAddr("codelessRouter");

        trackedSelectors = [uint64(1111), 2222, 3333, 4444, 5555];

        // Arm the RMN proxy for every tracked selector and wire the mock ramps once, so the
        // consumption actions run the pool's full transfer validation
        for (uint256 i; i < trackedSelectors.length; ++i) {
            rmnProxy_.setIsCursed(bytes16(uint128(trackedSelectors[i])), false);
        }
        ccipRouter_.setOnRamp(onRamp);
        ccipRouter_.setOffRamp(offRamp);

        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenOne")));
        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenTwo")));
        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenThree")));
        // A 64-byte family-encoded shape next to the EVM encodings
        tokenCandidates.push(
            abi.encodePacked(keccak256("handlerFamilyTokenA"), keccak256("handlerFamilyTokenB"))
        );

        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolOne")));
        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolTwo")));
        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolThree")));
        // A 32-byte raw shape next to the EVM encodings
        poolCandidates.push(abi.encodePacked(keccak256("handlerFamilyPool")));

        // The accepted router candidates carry the ramp wiring of the rig's router, so a run
        // keeps consuming buckets after one of them is installed
        for (uint256 i; i < acceptingRouters.length; ++i) {
            MockVersionedCCIPRouter candidate = new MockVersionedCCIPRouter();
            candidate.setOnRamp(onRamp);
            candidate.setOffRamp(offRamp);
            acceptingRouters[i] = candidate;
        }
        acceptingRouters[1].setMode(MockRouterCandidate.ReturnMode.EmptyString);
        acceptingRouters[2].setMode(MockRouterCandidate.ReturnMode.LongGarbage);

        rejectingRouters[0] = new MockRouterCandidate();
        rejectingRouters[0].setMode(MockRouterCandidate.ReturnMode.Reverting);
        rejectingRouters[1] = new MockRouterCandidate();
        rejectingRouters[1].setMode(MockRouterCandidate.ReturnMode.ShortReturn);
    }

    // ========== LIFECYCLE ACTIONS ========== //

    function enablePolicy(uint256) external {
        if (config.isEnabled()) return;
        bytes32 digestBefore = _poolDigest();

        vm.prank(admin);
        config.enable("");

        assertTrue(config.isEnabled(), "enable must move the policy to the enabled state");
        _assertPoolUntouched(digestBefore, "enable");
        lifecycleTransitions += 1;
    }

    function disablePolicy(uint256 callerSeed_) external {
        if (!config.isEnabled()) return;
        address caller = callerSeed_ % 2 == 0 ? admin : emergency;
        bytes32 digestBefore = _poolDigest();

        vm.prank(caller);
        config.disable("");

        assertFalse(config.isEnabled(), "disable must move the policy to the disabled state");
        _assertPoolUntouched(digestBefore, "disable");
        lifecycleTransitions += 1;
    }

    /// @notice Re-enables within the grace window, or deliberately probes the closed window
    ///         and records a success there in a ghost flag.
    function reEnablePolicy(uint256) external {
        if (config.isEnabled() || config.lastTransitionAt() == 0) return;
        uint256 deadline = uint256(config.lastTransitionAt()) + config.gracePeriod();
        bytes32 digestBefore = _poolDigest();

        if (vm.getBlockTimestamp() <= deadline) {
            vm.prank(bridgeAdmin);
            config.reEnable();
            assertTrue(config.isEnabled(), "reEnable within the window must enable the policy");
            lifecycleTransitions += 1;
        } else {
            vm.prank(bridgeAdmin);
            try config.reEnable() {
                ghost_reEnabledPastGraceDeadline = true;
            } catch (bytes memory reason_) {
                // Only the grace error is tolerated; anything else bubbles so the run fails
                // casting to 'bytes4' is deliberate: only the error selector is inspected
                // forge-lint: disable-next-line(unsafe-typecast)
                if (bytes4(reason_) != IGracePeriod.GracePeriod_Expired.selector) {
                    assembly {
                        revert(add(reason_, 0x20), mload(reason_))
                    }
                }
            }
            reEnableProbesPastDeadline += 1;
        }

        _assertPoolUntouched(digestBefore, "reEnable");
    }

    function rotateOperator(uint256 seed_) external {
        if (!config.isEnabled()) return;
        address candidate = [operatorPrimary, operatorAlternate, address(0)][seed_ % 3];
        bytes32 digestBefore = _poolDigest();

        vm.prank(admin);
        config.setConfigOperator(candidate);

        assertEq(config.configOperator(), candidate, "the operator rotation must land");
        _assertPoolUntouched(digestBefore, "setConfigOperator");
    }

    /// @notice Moves the re-enable window while the policy is enabled, so the closed-window
    ///         probe runs against a deadline that varies over a sequence.
    function setGraceWindow(uint256 seed_) external {
        if (!config.isEnabled()) return;
        // casting to 'uint32' is safe because the bound keeps the value below one week
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 period = uint32(bound(seed_, 1, MAX_GRACE_PERIOD));
        bytes32 digestBefore = _poolDigest();

        vm.prank(admin);
        config.setGracePeriod(period);

        assertEq(config.gracePeriod(), period, "the grace window must be written");
        _assertPoolUntouched(digestBefore, "setGracePeriod");
        graceWindowUpdates += 1;
    }

    function skipTime(uint256 seed_) external {
        skip(bound(seed_, 1, MAX_SKIP));
    }

    // ========== ADMIN INFRASTRUCTURE ACTIONS ========== //

    /// @notice Points the pool at a router candidate, or probes one the config must reject.
    ///         An accepted candidate lands and keeps serving the ramp lookups; a rejected one
    ///         leaves the pool pointing where it did.
    function setPoolRouter(uint256 seed_) external {
        if (!config.isEnabled()) return;
        uint256 branch = seed_ % 7;
        address candidate = _routerCandidate(branch);

        if (branch < acceptingRouters.length) {
            vm.prank(admin);
            config.setRouter(candidate);

            assertEq(
                pool.getRouter(),
                candidate,
                "the accepted candidate must become the pool router"
            );
            routerChanges += 1;
            return;
        }

        address routerBefore = pool.getRouter();
        _rejectRouterCandidate(candidate);

        assertEq(
            pool.getRouter(),
            routerBefore,
            "a rejected candidate must not change the pool router"
        );
        routerRejections += 1;
    }

    /// @dev Fires a candidate the config must reject. Only the two candidate errors are
    ///      tolerated; anything else bubbles so the run fails.
    function _rejectRouterCandidate(address candidate_) internal {
        vm.prank(admin);
        try config.setRouter(candidate_) {
            revert("an invalid router candidate must be rejected");
        } catch (bytes memory reason_) {
            // casting to 'bytes4' is deliberate: only the error selector is inspected
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorSelector = bytes4(reason_);
            if (
                errorSelector != ICCIPBridgeConfig.CCIPBridgeConfig_InvalidRouter.selector &&
                errorSelector != ICCIPBridgeConfig.CCIPBridgeConfig_InvalidAddress.selector
            ) {
                assembly {
                    revert(add(reason_, 0x20), mload(reason_))
                }
            }
        }
    }

    /// @notice Writes the pool's rebalancer, which the config does not validate: the zero
    ///         address clears it and any other value is accepted.
    function setPoolRebalancer(uint256 seed_) external {
        if (!config.isEnabled()) return;
        address candidate = [address(0), rebalancerCandidate, liquiditySource][seed_ % 3];

        vm.prank(admin);
        config.setRebalancer(candidate);

        assertEq(
            LockReleaseTokenPool(address(pool)).getRebalancer(),
            candidate,
            "the pool rebalancer must be written"
        );
        rebalancerChanges += 1;
    }

    /// @notice Grants or revokes the pool's rate limit admin, the only authority besides the
    ///         ownership that can write bucket configurations directly.
    function setPoolRateLimitAdmin(uint256 seed_) external {
        if (!config.isEnabled()) return;
        address candidate = [address(0), rateLimitAdminCandidate, address(config)][seed_ % 3];

        vm.prank(admin);
        config.setRateLimitAdmin(candidate);

        assertEq(pool.getRateLimitAdmin(), candidate, "the pool rate limit admin must be written");
        rateLimitAdminChanges += 1;
    }

    /// @notice Probes the direct pool path as the rate limit admin candidate. The write is the
    ///         route's current configuration, so the observable state cannot change and the
    ///         probe measures authority only: it must succeed exactly while the grant is held.
    function probeRateLimitAdminBypass(uint256 selectorSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;

        ICCIPRateLimiter.TokenBucket memory outBefore = pool.getCurrentOutboundRateLimiterState(
            selector
        );
        ICCIPRateLimiter.TokenBucket memory inBefore = pool.getCurrentInboundRateLimiterState(
            selector
        );
        bool granted = pool.getRateLimitAdmin() == rateLimitAdminCandidate;
        bytes memory payload = abi.encodeCall(
            ICCIPTokenPoolAdmin.setChainRateLimiterConfig,
            (selector, _toConfig(outBefore), _toConfig(inBefore))
        );

        vm.prank(rateLimitAdminCandidate);
        // A low-level call so the expected rejection does not bubble
        // forge-lint: disable-next-line(unchecked-call)
        (bool success, ) = address(pool).call(payload);

        if (granted) {
            assertTrue(success, "the granted rate limit admin must reach the pool");
        } else if (success) {
            ghost_rateLimitBypassWithoutGrant = true;
        }
        ICCIPRateLimiter.TokenBucket memory outAfter = pool.getCurrentOutboundRateLimiterState(
            selector
        );
        ICCIPRateLimiter.TokenBucket memory inAfter = pool.getCurrentInboundRateLimiterState(
            selector
        );
        _assertSameConfig(outBefore, outAfter, "bypass probe outbound");
        _assertSameConfig(inBefore, inAfter, "bypass probe inbound");
        assertEq(outAfter.tokens, outBefore.tokens, "the probe must not move the outbound fill");
        assertEq(inAfter.tokens, inBefore.tokens, "the probe must not move the inbound fill");
        rateLimitBypassProbes += 1;
    }

    /// @notice Pulls liquidity from the funded source pool into the managed pool and asserts
    ///         the three-way accounting: the source pays exactly what the pool receives, the
    ///         token supply is unchanged and the policy keeps nothing.
    function transferSourceLiquidity(uint256 amountSeed_) external {
        if (!config.isEnabled()) return;
        uint256 sourceBalanceBefore = ohm.balanceOf(liquiditySource);
        if (sourceBalanceBefore == 0) return;
        uint256 amount = bound(amountSeed_, 1, sourceBalanceBefore);
        uint256 poolBalanceBefore = ohm.balanceOf(address(pool));
        uint256 supplyBefore = ohm.totalSupply();

        vm.prank(admin);
        config.transferLiquidity(liquiditySource, amount);

        assertEq(
            ohm.balanceOf(liquiditySource),
            sourceBalanceBefore - amount,
            "the source must pay exactly the transferred amount"
        );
        assertEq(
            ohm.balanceOf(address(pool)),
            poolBalanceBefore + amount,
            "the pool must receive exactly the transferred amount"
        );
        assertEq(ohm.totalSupply(), supplyBefore, "the transfer must conserve the token supply");
        assertEq(
            ohm.balanceOf(address(config)),
            0,
            "the transfer must leave nothing on the config policy"
        );
        ghost_liquidityMovedFromSource += amount;
        liquidityTransfers += 1;
    }

    /// @notice Migrates the pool ownership to a candidate and back inside one call: the
    ///         proposals alone never move the ownership, the acceptances do, and the route
    ///         state comes out byte-identical.
    function ownershipRoundTrip(uint256) external {
        if (!config.isEnabled() || pool.owner() != address(config)) return;
        bytes32 digestBefore = _poolDigest();
        address candidate = ownershipCandidate;

        vm.prank(admin);
        config.transferPoolOwnership(candidate);
        assertEq(pool.owner(), address(config), "a proposal must not move the pool ownership");

        vm.prank(candidate);
        pool.acceptOwnership();
        assertEq(pool.owner(), candidate, "the acceptance must move the pool ownership");

        vm.prank(candidate);
        pool.transferOwnership(address(config));
        assertEq(pool.owner(), candidate, "the proposal back must not move the pool ownership");

        vm.prank(admin);
        config.acceptPoolOwnership();

        assertEq(pool.owner(), address(config), "the round trip must restore the config as owner");
        _assertPoolUntouched(digestBefore, "ownership round trip");
        ownershipRoundTrips += 1;
    }

    // ========== ROUTE ACTIONS ========== //

    function addRoute(uint256 selectorSeed_, uint256 shapeSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || pool.isSupportedChain(selector)) return;

        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(shapeSeed_);
        bytes[] memory remotePools = new bytes[](1 + (shapeSeed_ % 2));
        uint256 firstPoolIndex = shapeSeed_ % poolCandidates.length;
        remotePools[0] = poolCandidates[firstPoolIndex];
        if (remotePools.length == 2) {
            remotePools[1] = poolCandidates[(firstPoolIndex + 1) % poolCandidates.length];
        }
        address caller = _routeCaller(shapeSeed_);

        vm.prank(caller);
        config.addChain(
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: selector,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: tokenCandidates[shapeSeed_ % tokenCandidates.length],
                outboundRateLimiterConfig: outbound,
                inboundRateLimiterConfig: inbound
            })
        );

        assertTrue(pool.isSupportedChain(selector), "the added route must be supported");
        (uint128 outTokens, uint128 inTokens) = _fills(selector);
        assertEq(outTokens, outbound.capacity, "the outbound bucket must start full");
        assertEq(inTokens, inbound.capacity, "the inbound bucket must start full");
        routesAdded += 1;
    }

    function removeRoute(uint256 selectorSeed_, uint256 callerSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        address caller = _routeCaller(callerSeed_);

        vm.prank(caller);
        config.removeChain(selector);

        assertFalse(pool.isSupportedChain(selector), "the removed route must be unsupported");
        routesRemoved += 1;
    }

    function addRemotePoolToRoute(uint256 selectorSeed_, uint256 poolSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        bytes memory candidate = poolCandidates[poolSeed_ % poolCandidates.length];
        if (pool.isRemotePool(selector, candidate)) return;
        address caller = _routeCaller(poolSeed_);

        vm.prank(caller);
        config.addRemotePool(selector, candidate);

        assertTrue(pool.isRemotePool(selector, candidate), "the remote pool must be accepted");
        remotePoolChanges += 1;
    }

    function removeRemotePoolFromRoute(uint256 selectorSeed_, uint256 indexSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        bytes[] memory remotePools = pool.getRemotePools(selector);
        if (remotePools.length <= 1) return;
        bytes memory victim = remotePools[indexSeed_ % remotePools.length];
        address caller = _routeCaller(indexSeed_);

        vm.prank(caller);
        config.removeRemotePool(selector, victim);

        assertFalse(pool.isRemotePool(selector, victim), "the remote pool must be removed");
        remotePoolChanges += 1;
    }

    /// @notice Replaces the remote token and asserts the full preservation contract of the
    ///         route recreation: pools and bucket configurations unchanged, the fill restored
    ///         exactly at or above two units and floored to two below.
    function replaceRemoteToken(uint256 selectorSeed_, uint256 tokenSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        bytes memory candidate = tokenCandidates[tokenSeed_ % tokenCandidates.length];
        if (keccak256(candidate) == keccak256(pool.getRemoteToken(selector))) return;

        bytes[] memory poolsBefore = pool.getRemotePools(selector);
        ICCIPRateLimiter.TokenBucket memory outBefore = pool.getCurrentOutboundRateLimiterState(
            selector
        );
        ICCIPRateLimiter.TokenBucket memory inBefore = pool.getCurrentInboundRateLimiterState(
            selector
        );
        address caller = _routeCaller(tokenSeed_);

        vm.prank(caller);
        config.setRemoteToken(selector, candidate);

        assertEq(pool.getRemoteToken(selector), candidate, "the remote token must be replaced");
        bytes[] memory poolsAfter = pool.getRemotePools(selector);
        assertEq(poolsAfter.length, poolsBefore.length, "the remote pool set must be preserved");
        for (uint256 i; i < poolsBefore.length; ++i) {
            assertEq(poolsAfter[i], poolsBefore[i], "a remote pool entry must be preserved");
        }
        ICCIPRateLimiter.TokenBucket memory outAfter = pool.getCurrentOutboundRateLimiterState(
            selector
        );
        ICCIPRateLimiter.TokenBucket memory inAfter = pool.getCurrentInboundRateLimiterState(
            selector
        );
        _assertSameConfig(outBefore, outAfter, "outbound");
        _assertSameConfig(inBefore, inAfter, "inbound");
        // The fill is restored exactly at or above two units; below, the smallest enabled
        // capacity at a rate of one floors it to two
        assertEq(
            outAfter.tokens,
            outBefore.tokens >= 2 ? outBefore.tokens : 2,
            "the outbound fill must be restored with the two-unit floor"
        );
        assertEq(
            inAfter.tokens,
            inBefore.tokens >= 2 ? inBefore.tokens : 2,
            "the inbound fill must be restored with the two-unit floor"
        );
        _checkFillTransition(selector, outBefore.tokens, inBefore.tokens);
        remoteTokenReplacements += 1;
    }

    function setRouteRateLimits(
        uint256 selectorSeed_,
        uint256 shapeSeed_,
        uint256 callerSeed_
    ) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(shapeSeed_);
        (uint128 outTokensBefore, uint128 inTokensBefore) = _fills(selector);
        address caller = _rateLimitCaller(callerSeed_);

        vm.prank(caller);
        config.setChainRateLimits(selector, outbound, inbound);

        ICCIPRateLimiter.TokenBucket memory outAfter = pool.getCurrentOutboundRateLimiterState(
            selector
        );
        assertEq(outAfter.capacity, outbound.capacity, "the outbound capacity must be written");
        assertEq(outAfter.rate, outbound.rate, "the outbound rate must be written");
        _checkFillTransition(selector, outTokensBefore, inTokensBefore);
        rateLimitWrites += 1;
    }

    // ========== CONTAINMENT ACTIONS ========== //

    function containChain(uint256 selectorSeed_, uint256 callerSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;
        (uint128 outTokensBefore, uint128 inTokensBefore) = _fills(selector);
        address caller = _containmentCaller(callerSeed_);

        vm.prank(caller);
        config.disableChain(selector);

        _assertContained(selector, outTokensBefore, inTokensBefore);
        _checkFillTransition(selector, outTokensBefore, inTokensBefore);
        containmentCalls += 1;
    }

    function containAllChains(uint256 callerSeed_) external {
        uint64[] memory selectors = pool.getSupportedChains();
        uint128[] memory outTokensBefore = new uint128[](selectors.length);
        uint128[] memory inTokensBefore = new uint128[](selectors.length);
        for (uint256 i; i < selectors.length; ++i) {
            (outTokensBefore[i], inTokensBefore[i]) = _fills(selectors[i]);
        }
        address caller = _containmentCaller(callerSeed_);

        vm.prank(caller);
        config.disableAllChains();

        for (uint256 i; i < selectors.length; ++i) {
            _assertContained(selectors[i], outTokensBefore[i], inTokensBefore[i]);
            _checkFillTransition(selectors[i], outTokensBefore[i], inTokensBefore[i]);
        }
        containmentCalls += 1;
    }

    // ========== BUCKET CONSUMPTION ACTIONS ========== //

    function consumeOutbound(uint256 selectorSeed_, uint256 amountSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;
        (uint128 outTokensBefore, uint128 inTokensBefore) = _fills(selector);
        if (outTokensBefore == 0) return;
        uint256 amount = bound(amountSeed_, 1, outTokensBefore);
        LockReleaseTokenPool rigPool = LockReleaseTokenPool(address(pool));

        // Mirror the production flow: the tokens land on the pool before the lock
        ohm.mint(address(rigPool), amount);
        vm.prank(onRamp);
        rigPool.lockOrBurn(
            Pool.LockOrBurnInV1({
                receiver: abi.encode(makeAddr("handlerBridgeReceiver")),
                remoteChainSelector: selector,
                originalSender: makeAddr("handlerBridgeSender"),
                amount: amount,
                localToken: address(ohm)
            })
        );

        (uint128 outTokensAfter, ) = _fills(selector);
        assertEq(
            uint256(outTokensAfter),
            uint256(outTokensBefore) - amount,
            "the outbound consumption must decrement the fill exactly"
        );
        _checkFillTransition(selector, outTokensBefore, inTokensBefore);
        bucketConsumptions += 1;
    }

    function consumeInbound(uint256 selectorSeed_, uint256 amountSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;
        bytes[] memory remotePools = pool.getRemotePools(selector);
        if (remotePools.length == 0) return;
        (uint128 outTokensBefore, uint128 inTokensBefore) = _fills(selector);
        if (inTokensBefore == 0) return;
        uint256 amount = bound(amountSeed_, 1, inTokensBefore);
        LockReleaseTokenPool rigPool = LockReleaseTokenPool(address(pool));

        // The release transfers tokens out of the pool, so it is funded first
        ohm.mint(address(rigPool), amount);
        vm.prank(offRamp);
        rigPool.releaseOrMint(
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(makeAddr("handlerBridgeSender")),
                remoteChainSelector: selector,
                receiver: makeAddr("handlerBridgeReceiver"),
                amount: amount,
                localToken: address(ohm),
                sourcePoolAddress: remotePools[0],
                sourcePoolData: "",
                offchainTokenData: ""
            })
        );

        (, uint128 inTokensAfter) = _fills(selector);
        assertEq(
            uint256(inTokensAfter),
            uint256(inTokensBefore) - amount,
            "the inbound consumption must decrement the fill exactly"
        );
        _checkFillTransition(selector, outTokensBefore, inTokensBefore);
        bucketConsumptions += 1;
    }

    // ========== OUTSIDER PROBE ========== //

    /// @notice Fires one state-changing config function as the outsider and records any
    ///         success in a ghost flag: the authorization surface must never expand,
    ///         whatever state the sequence has reached.
    function probeUnauthorized(uint256 seed_) external {
        bytes memory payload = _probePayload(seed_ % 20);

        vm.prank(outsider);
        // A low-level call so a revert (the expected outcome) does not bubble
        // forge-lint: disable-next-line(unchecked-call)
        (bool success, ) = address(config).call(payload);

        if (success) ghost_unauthorizedCallSucceeded = true;
        outsiderProbes += 1;
    }

    function _probePayload(uint256 branch_) internal view returns (bytes memory) {
        uint64 selector = trackedSelectors[0];
        ICCIPRateLimiter.Config memory someConfig = ICCIPRateLimiter.Config({
            isEnabled: true,
            capacity: 10,
            rate: 1
        });
        if (branch_ == 0) return abi.encodeCall(IEnabler.enable, (""));
        if (branch_ == 1) return abi.encodeCall(IEnabler.disable, (""));
        if (branch_ == 2) return abi.encodeCall(IReEnabler.reEnable, ());
        if (branch_ == 3) return abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(1 days)));
        if (branch_ == 4) return abi.encodeCall(IConfigOperator.setConfigOperator, (outsider));
        if (branch_ == 5) return abi.encodeCall(ICCIPBridgeConfig.acceptPoolOwnership, ());
        if (branch_ == 6)
            return abi.encodeCall(ICCIPBridgeConfig.transferPoolOwnership, (outsider));
        if (branch_ == 7) return abi.encodeCall(ICCIPBridgeConfig.setRouter, (address(ccipRouter)));
        if (branch_ == 8) return abi.encodeCall(ICCIPBridgeConfig.setRebalancer, (outsider));
        if (branch_ == 9) return abi.encodeCall(ICCIPBridgeConfig.setRateLimitAdmin, (outsider));
        if (branch_ == 10) {
            return abi.encodeCall(ICCIPBridgeConfig.transferLiquidity, (outsider, 1));
        }
        if (branch_ == 11) {
            return
                abi.encodeCall(
                    ICCIPBridgeConfig.addChain,
                    (
                        ICCIPTokenPoolAdmin.ChainUpdate({
                            remoteChainSelector: selector,
                            remotePoolAddresses: new bytes[](0),
                            remoteTokenAddress: "",
                            outboundRateLimiterConfig: someConfig,
                            inboundRateLimiterConfig: someConfig
                        })
                    )
                );
        }
        if (branch_ == 12) return abi.encodeCall(ICCIPBridgeConfig.removeChain, (selector));
        if (branch_ == 13) {
            return abi.encodeCall(ICCIPBridgeConfig.setRemoteToken, (selector, hex"01"));
        }
        if (branch_ == 14) {
            return abi.encodeCall(ICCIPBridgeConfig.addRemotePool, (selector, hex"01"));
        }
        if (branch_ == 15) {
            return abi.encodeCall(ICCIPBridgeConfig.removeRemotePool, (selector, hex"01"));
        }
        if (branch_ == 16) {
            return
                abi.encodeCall(
                    ICCIPBridgeConfig.applyAllowListUpdates,
                    (new address[](0), new address[](0))
                );
        }
        if (branch_ == 17) {
            return
                abi.encodeCall(
                    ICCIPBridgeConfig.setChainRateLimits,
                    (selector, someConfig, someConfig)
                );
        }
        if (branch_ == 18) return abi.encodeCall(ICCIPBridgeConfig.disableChain, (selector));
        return abi.encodeCall(ICCIPBridgeConfig.disableAllChains, ());
    }

    // ========== SELECTION HELPERS ========== //

    function _pickSelector(uint256 seed_) internal view returns (uint64) {
        return trackedSelectors[seed_ % trackedSelectors.length];
    }

    /// @dev The route functions accept the config operator or the admin; picks the current
    ///      operator when one is set and the seed points at it.
    function _routeCaller(uint256 seed_) internal view returns (address) {
        address currentOperator = config.configOperator();
        if (currentOperator != address(0) && seed_ % 2 == 0) return currentOperator;
        return admin;
    }

    function _rateLimitCaller(uint256 seed_) internal view returns (address) {
        uint256 choice = seed_ % 3;
        if (choice == 0) return bridgeRateLimiter;
        if (choice == 1) return admin;
        address currentOperator = config.configOperator();
        return currentOperator != address(0) ? currentOperator : admin;
    }

    function _containmentCaller(uint256 seed_) internal view returns (address) {
        return [emergency, admin, bridgeAdmin, bridgeRateLimiter][seed_ % 4];
    }

    /// @dev The router candidate space: the three accepted answers first, then the four the
    ///      config must reject (a reverting probe, a return below the minimum length, the zero
    ///      address and a codeless account).
    function _routerCandidate(uint256 branch_) internal view returns (address) {
        if (branch_ < acceptingRouters.length) return address(acceptingRouters[branch_]);
        if (branch_ == 3) return address(rejectingRouters[0]);
        if (branch_ == 4) return address(rejectingRouters[1]);
        if (branch_ == 5) return address(0);
        return codelessRouter;
    }

    /// @dev Enabled rate limiter configurations bounded so the pool accepts them: the
    ///      capacity in [2, MAX_CAPACITY] base units and the rate in [1, capacity - 1].
    function _boundedConfigs(
        uint256 seed_
    )
        internal
        pure
        returns (ICCIPRateLimiter.Config memory outbound, ICCIPRateLimiter.Config memory inbound)
    {
        uint256 mixed = uint256(keccak256(abi.encode(seed_)));
        // casting to 'uint128' is safe because the bounds stay far below the uint128 maximum
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 outCapacity = uint128(bound(mixed & type(uint64).max, 2, MAX_CAPACITY));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 outRate = uint128(bound((mixed >> 64) & type(uint64).max, 1, outCapacity - 1));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 inCapacity = uint128(bound((mixed >> 128) & type(uint64).max, 2, MAX_CAPACITY));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 inRate = uint128(bound(mixed >> 192, 1, inCapacity - 1));
        outbound = ICCIPRateLimiter.Config({isEnabled: true, capacity: outCapacity, rate: outRate});
        inbound = ICCIPRateLimiter.Config({isEnabled: true, capacity: inCapacity, rate: inRate});
        return (outbound, inbound);
    }

    // ========== STATE OBSERVATION HELPERS ========== //

    /// @dev Both projected fills of a route, read in the current block.
    function _fills(uint64 selector_) internal view returns (uint128 outTokens, uint128 inTokens) {
        outTokens = pool.getCurrentOutboundRateLimiterState(selector_).tokens;
        inTokens = pool.getCurrentInboundRateLimiterState(selector_).tokens;
        return (outTokens, inTokens);
    }

    /// @dev Digest of the whole observable pool state: authority pointers plus every route's
    ///      token, remote pools and both projected buckets. Pre/post pairs are read in one
    ///      block, so the projection cannot drift between them.
    function _poolDigest() internal view returns (bytes32) {
        uint64[] memory selectors = pool.getSupportedChains();
        bytes memory acc = abi.encode(
            pool.owner(),
            pool.getRateLimitAdmin(),
            pool.getRouter(),
            LockReleaseTokenPool(address(pool)).getRebalancer(),
            selectors
        );
        for (uint256 i; i < selectors.length; ++i) {
            acc = bytes.concat(
                acc,
                abi.encode(
                    pool.getRemoteToken(selectors[i]),
                    pool.getRemotePools(selectors[i]),
                    pool.getCurrentOutboundRateLimiterState(selectors[i]),
                    pool.getCurrentInboundRateLimiterState(selectors[i])
                )
            );
        }
        return keccak256(acc);
    }

    function _assertPoolUntouched(bytes32 digestBefore_, string memory action_) internal {
        assertEq(
            _poolDigest(),
            digestBefore_,
            string.concat(action_, " must not mutate any pool state")
        );
        poolDigestChecks += 1;
    }

    /// @dev Containment postcondition: both buckets hold the disabled configuration and each
    ///      fill is clamped downward, never refilled (two units from at or above two,
    ///      untouched below two).
    function _assertContained(
        uint64 selector_,
        uint128 outTokensBefore_,
        uint128 inTokensBefore_
    ) internal view {
        ICCIPRateLimiter.TokenBucket memory outbound = pool.getCurrentOutboundRateLimiterState(
            selector_
        );
        ICCIPRateLimiter.TokenBucket memory inbound = pool.getCurrentInboundRateLimiterState(
            selector_
        );
        assertTrue(
            outbound.isEnabled && outbound.capacity == 2 && outbound.rate == 1,
            "containment must write the disabled configuration outbound"
        );
        assertTrue(
            inbound.isEnabled && inbound.capacity == 2 && inbound.rate == 1,
            "containment must write the disabled configuration inbound"
        );
        assertEq(
            outbound.tokens,
            outTokensBefore_ >= 2 ? 2 : outTokensBefore_,
            "containment must clamp the outbound fill without refilling"
        );
        assertEq(
            inbound.tokens,
            inTokensBefore_ >= 2 ? 2 : inTokensBefore_,
            "containment must clamp the inbound fill without refilling"
        );
        assertTrue(config.isChainDisabled(selector_), "the contained route must read disabled");
    }

    /// @dev The configuration fields of a bucket, in the shape the pool's setters take.
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

    function _assertSameConfig(
        ICCIPRateLimiter.TokenBucket memory before_,
        ICCIPRateLimiter.TokenBucket memory after_,
        string memory label_
    ) internal pure {
        assertEq(
            after_.isEnabled,
            before_.isEnabled,
            string.concat(label_, ": isEnabled must be preserved")
        );
        assertEq(
            after_.capacity,
            before_.capacity,
            string.concat(label_, ": capacity must be preserved")
        );
        assertEq(after_.rate, before_.rate, string.concat(label_, ": rate must be preserved"));
    }

    /// @dev Ghost check run after every bucket-touching action: a projected fill that ends
    ///      above both its pre-call level and the two-unit floor was raised by a config-
    ///      mediated call, which no path is allowed to do.
    function _checkFillTransition(
        uint64 selector_,
        uint128 outTokensBefore_,
        uint128 inTokensBefore_
    ) internal {
        (uint128 outTokensAfter, uint128 inTokensAfter) = _fills(selector_);
        if (
            (outTokensAfter > outTokensBefore_ && outTokensAfter > 2) ||
            (inTokensAfter > inTokensBefore_ && inTokensAfter > 2)
        ) {
            ghost_fillRaisedBeyondFloor = true;
        }
        fillTransitionsChecked += 1;
    }
}
