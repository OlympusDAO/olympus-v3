// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";

import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Kernel} from "src/Kernel.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

/// @notice Invariant-test handler that drives CCIPTokenPoolConfigTimelock through its production
///         entry points over a small fixed selector space, next to the direct config-policy
///         paths that drift the recorded state, with every action pranked as the role that
///         owns it. The handler is guarded: every action either no-ops when its preconditions
///         do not hold or succeeds, so the suite runs with fail-on-revert and any unexpected
///         revert surfaces as a failure.
/// @dev    The heart of the handler is the ghost registry of queued actions: for every action
///         it ever queued it records the id, the proposer, the queue-time timestamps, the
///         canonical sub-action payloads and, per reserved key, the destination-scoped key and
///         the state hash the handler recomputed itself immediately before queueing. The
///         registry is the independent oracle the invariant functions reconcile against the
///         contract's views after every call, so any release, mutation or divergence the
///         production code performs outside execution and cancellation fails the run.
///
///         Deliberate negative probes use a low-level call and compare the full revert bytes
///         against the exact error they predicted from the registry and the live state
///         (a conflicting queue must name the first reserved key in reservation order and its
///         owner; an untimely execution must name the timestamp, lifecycle or first drifted
///         state in the contract's own check order); an unpredicted revert bubbles so the run
///         fails, and an unexpected success sets a ghost flag. The untimely-execution probe
///         doubles as the retention check: after every predicted failure it asserts the action
///         is still live and still owns every reserved key.
///
///         The allowlist rig is not part of this suite, so queueApplyAllowListUpdates is
///         driven exclusively through the rejected-queue probe: on the primary pool the domain
///         is unreachable and the attempt must always stop at AllowListNotEnabled without
///         reserving anything.
///
///         Time moves through three actions: a bounded small skip, a targeted skip that lands
///         exactly on a live action's executableAt, and a targeted skip that lands exactly one
///         second past a live action's expiresAt. Without the targeted skips a 1-day delay and
///         a 3-day window would almost never be crossed by bounded random skips.
contract CCIPTokenPoolConfigTimelockHandler is Test {
    // ========== GHOST REGISTRY TYPES ========== //

    /// @notice One queued action as the handler recorded it at queue time. The array index is
    ///         `id - 1`: only the handler queues, and ids are sequential from one.
    struct GhostAction {
        address proposer;
        uint48 queuedAt;
        uint48 executableAt;
        uint48 expiresAt;
        // 0 = live, 1 = executed, 2 = cancelled
        uint8 status;
        uint8 subCount;
    }

    /// @notice One sub-action: the config function selector and the canonical payload, encoded
    ///         by the handler exactly as the typed helper builds it.
    struct GhostSub {
        bytes4 selector;
        bytes payload;
    }

    /// @notice One reserved configuration state: the destination-scoped key (recomputed by the
    ///         handler from the documented shape), the state hash the handler recomputed from
    ///         the live pool immediately before queueing, and the domain coordinates needed to
    ///         recompute the current hash later.
    struct GhostState {
        bytes32 scopedKey;
        bytes32 expectedHash;
        // 0 = rate limits, 1 = remote pools, 2 = route identity
        uint8 domainKind;
        uint64 chainSelector;
    }

    // ========== RIG REFERENCES ========== //

    CCIPTokenPoolConfigTimelock public immutable timelock;
    CCIPTokenPoolConfig public immutable config;
    ICCIPTokenPoolAdmin public immutable pool;
    MockOhm internal immutable ohm;
    MockRMNProxy internal immutable rmnProxy;

    // ========== ACTORS ========== //

    address public immutable admin;
    address public immutable emergency;
    address public immutable bridgeAdmin;
    address public immutable bridgeRateLimiter;

    /// @notice The account the operator-seat rotation points the config at while the timelock
    ///         is benched.
    address public immutable seatCandidate;

    /// @notice The roleless account that fires the untimely-execution and authorization
    ///         probes.
    address public immutable outsider;

    /// @notice The account that holds the pool ownership for the duration of the atomic
    ///         ownership-loss probe.
    address public immutable poolOwnerCandidate;

    address internal immutable onRamp;

    // ========== DOMAIN CONSTANTS (cached from the timelock) ========== //

    bytes32 internal immutable RATE_LIMITS_DOMAIN;
    bytes32 internal immutable REMOTE_POOLS_DOMAIN;
    bytes32 internal immutable ROUTE_IDENTITY_DOMAIN;
    bytes32 internal immutable ALLOWLIST_DOMAIN;
    uint48 internal immutable EXECUTION_WINDOW;

    // ========== TRACKED SELECTORS AND CANDIDATES ========== //

    uint64[5] public trackedSelectors;
    bytes[] internal tokenCandidates;
    bytes[] internal poolCandidates;

    // ========== ACTION BOUNDS ========== //

    uint256 internal constant MAX_SKIP = 12 hours;
    uint256 internal constant MAX_CAPACITY = 1_000_000_000_000;
    uint256 internal constant MIN_DELAY = 1 days;
    uint256 internal constant MAX_DELAY = 30 days;
    uint256 internal constant MIN_GRACE = 12 hours;
    uint256 internal constant MAX_GRACE = 7 days;
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @notice The number of gated state-changing entry points the outsider probe covers.
    uint256 internal constant GATED_ENTRY_POINTS = 15;

    // ========== GHOST REGISTRY STORAGE ========== //

    GhostAction[] internal _ghostActions;
    mapping(uint256 => GhostSub[]) internal _ghostSubs;
    mapping(uint256 => mapping(uint256 => GhostState[])) internal _ghostStates;

    /// @notice The number of ghost actions whose status is still live.
    uint256 public liveActionCount;

    // ========== GHOST FLAGS (read by the invariant functions) ========== //

    /// @notice Set when a reEnable call succeeds although the grace deadline has passed.
    bool public ghost_reEnabledPastGraceDeadline;

    /// @notice Set when a queue attempt the registry and live state predict as invalid
    ///         succeeds anyway.
    bool public ghost_rejectedQueueSucceeded;

    /// @notice Set when an execution attempt predicted to fail (untimely, gated or drifted)
    ///         succeeds anyway.
    bool public ghost_untimelyExecuteSucceeded;

    /// @notice Set when a successful dispatch changes the recomputed hash of any tracked
    ///         domain outside the executed action's own reserved key set.
    bool public ghost_dispatchWroteOutsideDomains;

    /// @notice Set when a state-changing call from the roleless outsider succeeds on any gated
    ///         entry point of the timelock.
    bool public ghost_unauthorizedCallSucceeded;

    /// @notice Set when an execution succeeds although the config policy no longer owns the
    ///         pool it configures.
    bool public ghost_dispatchWithoutOwnershipSucceeded;

    // ========== COVERAGE COUNTERS ========== //

    uint256 public queuesSucceeded;
    uint256 public batchesQueued;
    uint256 public executes;
    uint256 public dispatchDomainChecks;
    uint256 public cancels;
    uint256 public cancelsOfExpired;
    uint256 public cancelsWhileTimelockDisabled;
    uint256 public rejectedQueueProbes;
    uint256 public untimelyExecuteProbes;
    uint256 public expiredRetentionChecks;
    uint256 public driftRetentionChecks;
    uint256 public gateRetentionChecks;
    uint256 public resolvedReExecuteProbes;
    uint256 public lifecycleTransitions;
    uint256 public reEnableProbesPastDeadline;
    uint256 public configLifecycleToggles;
    uint256 public seatRotations;
    uint256 public delayWrites;
    uint256 public graceWindowWrites;
    uint256 public directRouteChanges;
    uint256 public containmentCalls;
    uint256 public consumptions;
    uint256 public ripens;
    uint256 public expiries;
    uint256 public outsiderProbes;
    uint256 public maskedMirrorProbes;
    uint256 public ownershipOwnerErrorProbes;
    uint256 public ownershipRateLimitErrorProbes;

    // ========== CONSTRUCTOR ========== //

    constructor(
        CCIPTokenPoolConfigTimelock timelock_,
        CCIPTokenPoolConfig config_,
        MockOhm ohm_,
        MockCCIPRouter ccipRouter_,
        MockRMNProxy rmnProxy_,
        address admin_,
        address emergency_,
        address bridgeAdmin_,
        address bridgeRateLimiter_
    ) {
        timelock = timelock_;
        config = config_;
        pool = ICCIPTokenPoolAdmin(config_.pool());
        ohm = ohm_;
        rmnProxy = rmnProxy_;
        admin = admin_;
        emergency = emergency_;
        bridgeAdmin = bridgeAdmin_;
        bridgeRateLimiter = bridgeRateLimiter_;
        seatCandidate = makeAddr("seatCandidate");
        outsider = makeAddr("outsider");
        poolOwnerCandidate = makeAddr("poolOwnerCandidate");
        onRamp = makeAddr("handlerOnRamp");

        RATE_LIMITS_DOMAIN = timelock_.RATE_LIMITS_DOMAIN();
        REMOTE_POOLS_DOMAIN = timelock_.REMOTE_POOLS_DOMAIN();
        ROUTE_IDENTITY_DOMAIN = timelock_.ROUTE_IDENTITY_DOMAIN();
        ALLOWLIST_DOMAIN = timelock_.ALLOWLIST_DOMAIN();
        EXECUTION_WINDOW = timelock_.EXECUTION_WINDOW();

        trackedSelectors = [uint64(1111), 2222, 3333, 4444, 5555];

        // Arm the RMN proxy for every tracked selector and wire the mock on-ramp once, so the
        // consumption action runs the pool's full transfer validation
        for (uint256 i; i < trackedSelectors.length; ++i) {
            rmnProxy_.setIsCursed(bytes16(uint128(trackedSelectors[i])), false);
        }
        ccipRouter_.setOnRamp(onRamp);

        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenOne")));
        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenTwo")));
        tokenCandidates.push(abi.encode(makeAddr("handlerRemoteTokenThree")));

        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolOne")));
        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolTwo")));
        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolThree")));
        poolCandidates.push(abi.encode(makeAddr("handlerRemotePoolFour")));
    }

    // ========== GHOST REGISTRY GETTERS ========== //

    function ghostActionCount() external view returns (uint256 count) {
        return _ghostActions.length;
    }

    function ghostActionAt(uint256 index_) external view returns (GhostAction memory action) {
        return _ghostActions[index_];
    }

    function ghostSubAt(
        uint256 index_,
        uint256 subIndex_
    ) external view returns (GhostSub memory sub) {
        return _ghostSubs[index_][subIndex_];
    }

    function ghostStateCount(
        uint256 index_,
        uint256 subIndex_
    ) external view returns (uint256 count) {
        return _ghostStates[index_][subIndex_].length;
    }

    function ghostStateAt(
        uint256 index_,
        uint256 subIndex_,
        uint256 stateIndex_
    ) external view returns (GhostState memory state) {
        return _ghostStates[index_][subIndex_][stateIndex_];
    }

    /// @notice The destination-scoped key of a tracked domain, recomputed from the documented
    ///         shape so the invariant functions never depend on the contract's own key views.
    function scopedKeyOf(uint8 domainKind_, uint64 chainSelector_) external view returns (bytes32) {
        return _scopedKey(domainKind_, chainSelector_);
    }

    /// @notice The unique live ghost owner of a scoped key, or zero when no live action holds
    ///         it.
    function ghostKeyOwner(bytes32 scopedKey_) external view returns (uint64 actionId) {
        return _ghostOwnerOf(scopedKey_);
    }

    // ========== LIFECYCLE ACTIONS ========== //

    function enableTimelock(uint256) external {
        if (timelock.isEnabled()) return;

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "enable must move the timelock to the enabled state");
        lifecycleTransitions += 1;
    }

    function disableTimelock(uint256 callerSeed_) external {
        if (!timelock.isEnabled()) return;
        address caller = callerSeed_ % 2 == 0 ? admin : emergency;

        vm.prank(caller);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "disable must move the timelock to the disabled state");
        lifecycleTransitions += 1;
    }

    /// @notice Re-enables within the grace window, or deliberately probes the closed window
    ///         and records a success there in a ghost flag.
    function reEnableTimelock(uint256) external {
        if (timelock.isEnabled() || timelock.lastTransitionAt() == 0) return;
        uint256 deadline = uint256(timelock.lastTransitionAt()) + timelock.gracePeriod();

        if (vm.getBlockTimestamp() <= deadline) {
            vm.prank(bridgeAdmin);
            timelock.reEnable();
            assertTrue(timelock.isEnabled(), "reEnable within the window must enable");
            lifecycleTransitions += 1;
        } else {
            vm.prank(bridgeAdmin);
            try timelock.reEnable() {
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
    }

    function setDelay(uint256 seed_) external {
        if (!timelock.isEnabled()) return;
        // casting to 'uint48' is safe because the bound keeps the value at or below 30 days
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 delay = uint48(bound(seed_, MIN_DELAY, MAX_DELAY));

        vm.prank(admin);
        timelock.setTimelockDelay(delay);

        assertEq(timelock.timelockDelay(), delay, "the delay must be written");
        delayWrites += 1;
    }

    function setGraceWindow(uint256 seed_) external {
        if (!timelock.isEnabled()) return;
        // casting to 'uint32' is safe because the bound keeps the value below one week
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 period = uint32(bound(seed_, MIN_GRACE, MAX_GRACE));

        vm.prank(admin);
        timelock.setGracePeriod(period);

        assertEq(timelock.gracePeriod(), period, "the grace window must be written");
        graceWindowWrites += 1;
    }

    /// @notice Disables the config policy when it is enabled and enables it back otherwise:
    ///         the queue and execution gates must close and reopen with it while every queued
    ///         action keeps its keys.
    function toggleConfigPolicy(uint256) external {
        if (config.isEnabled()) {
            vm.prank(admin);
            config.disable("");
            assertFalse(config.isEnabled(), "the config policy must disable");
        } else {
            vm.prank(admin);
            config.enable("");
            assertTrue(config.isEnabled(), "the config policy must enable");
        }
        configLifecycleToggles += 1;
    }

    /// @notice Rotates the config's operator seat between the timelock, a foreign candidate
    ///         and the zero address.
    function rotateOperatorSeat(uint256 seed_) external {
        if (!config.isEnabled()) return;
        address candidate = [address(timelock), seatCandidate, address(0)][seed_ % 3];

        vm.prank(admin);
        config.setConfigOperator(candidate);

        assertEq(config.configOperator(), candidate, "the seat rotation must land");
        seatRotations += 1;
    }

    // ========== TIME ACTIONS ========== //

    function skipTime(uint256 seed_) external {
        skip(bound(seed_, 1, MAX_SKIP));
    }

    /// @notice Lands exactly on the executableAt of a live action, so ready actions exist at
    ///         all despite the 1-day delay.
    function ripenAction(uint256 pickSeed_) external {
        uint256 index = _pickLiveAction(pickSeed_);
        if (index == NOT_FOUND) return;
        uint256 target = _ghostActions[index].executableAt;
        uint256 nowTs = vm.getBlockTimestamp();
        if (nowTs >= target) return;

        skip(target - nowTs);
        ripens += 1;
    }

    /// @notice Lands exactly one second past the expiresAt of a live action, producing the
    ///         expired-but-still-reserved state the retention properties feed on.
    function expireAction(uint256 pickSeed_) external {
        uint256 index = _pickLiveAction(pickSeed_);
        if (index == NOT_FOUND) return;
        uint256 target = uint256(_ghostActions[index].expiresAt) + 1;
        uint256 nowTs = vm.getBlockTimestamp();
        if (nowTs >= target) return;

        skip(target - nowTs);
        expiries += 1;
    }

    // ========== DIRECT CONFIG ACTIONS (DRIFT ACTORS) ========== //

    /// @notice The admin adds a route directly, bypassing the queue. A pending addChain action
    ///         for the same selector is deliberately left to drift.
    function directAddRoute(uint256 selectorSeed_, uint256 shapeSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || pool.isSupportedChain(selector)) return;

        vm.prank(admin);
        config.addChain(_buildChainUpdate(selector, shapeSeed_));

        assertTrue(pool.isSupportedChain(selector), "the direct route addition must land");
        directRouteChanges += 1;
    }

    /// @notice The admin removes a route directly; every queued action recorded against the
    ///         route drifts and must keep its keys until cancelled.
    function directRemoveRoute(uint256 selectorSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;

        vm.prank(admin);
        config.removeChain(selector);

        assertFalse(pool.isSupportedChain(selector), "the direct route removal must land");
        directRouteChanges += 1;
    }

    /// @notice The admin or the bridge rate limiter rewrites a route's buckets directly,
    ///         drifting any recorded rate limits hash of the route.
    function directRateLimits(uint256 selectorSeed_, uint256 shapeSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(shapeSeed_);
        address caller = shapeSeed_ % 2 == 0 ? admin : bridgeRateLimiter;

        vm.prank(caller);
        config.setChainRateLimits(selector, outbound, inbound);

        directRouteChanges += 1;
    }

    /// @notice A containment-role holder clamps a route to {enabled, 2, 1}; a queued rate
    ///         limit action for the route drifts and must never overwrite the containment.
    function containRoute(uint256 selectorSeed_, uint256 callerSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;
        address caller = [emergency, admin, bridgeAdmin, bridgeRateLimiter][callerSeed_ % 4];

        vm.prank(caller);
        config.disableChain(selector);

        assertTrue(config.isChainDisabled(selector), "the containment must land");
        containmentCalls += 1;
    }

    /// @notice The admin adds or removes a remote pool directly, drifting any recorded remote
    ///         pools hash of the route.
    function directPoolChange(uint256 selectorSeed_, uint256 seed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;

        if (seed_ % 2 == 0) {
            bytes memory candidate = _absentPoolCandidate(selector, seed_);
            if (candidate.length == 0) return;
            vm.prank(admin);
            config.addRemotePool(selector, candidate);
        } else {
            bytes[] memory members = pool.getRemotePools(selector);
            if (members.length < 2) return;
            bytes memory victim = members[seed_ % members.length];
            vm.prank(admin);
            config.removeRemotePool(selector, victim);
        }
        directRouteChanges += 1;
    }

    /// @notice The admin replaces a route's remote token directly, drifting any recorded
    ///         route identity hash.
    function directReplaceToken(uint256 selectorSeed_, uint256 tokenSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!config.isEnabled() || !pool.isSupportedChain(selector)) return;
        bytes memory candidate = tokenCandidates[tokenSeed_ % tokenCandidates.length];
        if (keccak256(candidate) == keccak256(pool.getRemoteToken(selector))) return;

        vm.prank(admin);
        config.setRemoteToken(selector, candidate);

        directRouteChanges += 1;
    }

    /// @notice Consumes the outbound bucket of a route through a real lockOrBurn: volatile
    ///         fill state that must never invalidate a queued action.
    function consumeOutbound(uint256 selectorSeed_, uint256 amountSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!pool.isSupportedChain(selector)) return;
        uint128 outTokens = pool.getCurrentOutboundRateLimiterState(selector).tokens;
        if (outTokens == 0) return;
        uint256 amount = bound(amountSeed_, 1, outTokens);
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

        consumptions += 1;
    }

    // ========== QUEUE ACTIONS ========== //

    function queueRateLimitChange(uint256 selectorSeed_, uint256 shapeSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || !pool.isSupportedChain(selector)) return;
        if (_ghostOwnerOf(_scopedKey(0, selector)) != 0) return;
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(shapeSeed_);
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetChainRateLimits(selector, outbound, inbound);

        _finishRegistration(index, actionId);
        _registerSub(
            index,
            ICCIPTokenPoolConfig.setChainRateLimits.selector,
            abi.encode(selector, outbound, inbound)
        );
        _registerState(index, 0, 0, selector);
        queuesSucceeded += 1;
    }

    function queueRouteAddition(uint256 selectorSeed_, uint256 shapeSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || pool.isSupportedChain(selector)) return;
        if (!_routeDomainsFree(selector)) return;
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _buildChainUpdate(selector, shapeSeed_);
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueAddChain(update);

        _finishRegistration(index, actionId);
        _registerSub(index, ICCIPTokenPoolConfig.addChain.selector, abi.encode(update));
        _registerRouteStates(index, 0, selector);
        queuesSucceeded += 1;
    }

    function queueRouteRemoval(uint256 selectorSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || !pool.isSupportedChain(selector)) return;
        if (!_routeDomainsFree(selector)) return;
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueRemoveChain(selector);

        _finishRegistration(index, actionId);
        _registerSub(index, ICCIPTokenPoolConfig.removeChain.selector, abi.encode(selector));
        _registerRouteStates(index, 0, selector);
        queuesSucceeded += 1;
    }

    function queueTokenChange(uint256 selectorSeed_, uint256 tokenSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || !pool.isSupportedChain(selector)) return;
        if (!_routeDomainsFree(selector)) return;
        bytes memory candidate = tokenCandidates[tokenSeed_ % tokenCandidates.length];
        if (keccak256(candidate) == keccak256(pool.getRemoteToken(selector))) return;
        // The mirror requires both buckets enabled; every route this handler produces
        // (validated additions and containment alike) keeps them enabled
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueSetRemoteToken(selector, candidate);

        _finishRegistration(index, actionId);
        _registerSub(
            index,
            ICCIPTokenPoolConfig.setRemoteToken.selector,
            abi.encode(selector, candidate)
        );
        _registerRouteStates(index, 0, selector);
        queuesSucceeded += 1;
    }

    function queuePoolAddition(uint256 selectorSeed_, uint256 poolSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || !pool.isSupportedChain(selector)) return;
        if (_ghostOwnerOf(_scopedKey(1, selector)) != 0) return;
        bytes memory candidate = _absentPoolCandidate(selector, poolSeed_);
        if (candidate.length == 0) return;
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueAddRemotePool(selector, candidate);

        _finishRegistration(index, actionId);
        _registerSub(
            index,
            ICCIPTokenPoolConfig.addRemotePool.selector,
            abi.encode(selector, candidate)
        );
        _registerState(index, 0, 1, selector);
        queuesSucceeded += 1;
    }

    function queuePoolRemoval(uint256 selectorSeed_, uint256 indexSeed_) external {
        uint64 selector = _pickSelector(selectorSeed_);
        if (!_queueGatesOpen() || !pool.isSupportedChain(selector)) return;
        if (_ghostOwnerOf(_scopedKey(1, selector)) != 0) return;
        bytes[] memory members = pool.getRemotePools(selector);
        if (members.length < 2) return;
        bytes memory victim = members[indexSeed_ % members.length];
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueRemoveRemotePool(selector, victim);

        _finishRegistration(index, actionId);
        _registerSub(
            index,
            ICCIPTokenPoolConfig.removeRemotePool.selector,
            abi.encode(selector, victim)
        );
        _registerState(index, 0, 1, selector);
        queuesSucceeded += 1;
    }

    /// @notice Queues a two-sub-action batch over disjoint free domains (a rate limit change
    ///         plus a remote pool addition), or a single-sub batch when only one slot is open.
    function queueBatchPair(uint256 seed_) external {
        if (!_queueGatesOpen()) return;
        (bool foundRl, uint64 rlSelector) = _findFreeRateLimitSlot(seed_);
        (bool foundRp, uint64 rpSelector, bytes memory rpCandidate) = _findFreePoolAdditionSlot(
            seed_
        );
        if (!foundRl && !foundRp) return;

        uint256 subCount = (foundRl ? 1 : 0) + (foundRp ? 1 : 0);
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](
            subCount
        );
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(seed_);
        uint256 cursor;
        if (foundRl) {
            batch[cursor] = ITimelockBatchQueue.BatchAction({
                target: address(config),
                selector: ICCIPTokenPoolConfig.setChainRateLimits.selector,
                payload: abi.encode(rlSelector, outbound, inbound)
            });
            cursor += 1;
        }
        if (foundRp) {
            batch[cursor] = ITimelockBatchQueue.BatchAction({
                target: address(config),
                selector: ICCIPTokenPoolConfig.addRemotePool.selector,
                payload: abi.encode(rpSelector, rpCandidate)
            });
        }
        uint256 index = _prepareRegistration();

        vm.prank(bridgeAdmin);
        uint64 actionId = timelock.queueBatch(batch);

        _finishRegistration(index, actionId);
        cursor = 0;
        if (foundRl) {
            _registerSub(index, ICCIPTokenPoolConfig.setChainRateLimits.selector, batch[0].payload);
            _registerState(index, cursor, 0, rlSelector);
            cursor += 1;
        }
        if (foundRp) {
            _registerSub(index, ICCIPTokenPoolConfig.addRemotePool.selector, batch[cursor].payload);
            _registerState(index, cursor, 1, rpSelector);
        }
        queuesSucceeded += 1;
        batchesQueued += 1;
    }

    // ========== RESOLUTION ACTIONS ========== //

    /// @notice Executes a live action whose window is open, whose gates are open and whose
    ///         recorded hashes all still match; execution must then succeed for any caller,
    ///         release every key and leave every tracked domain outside the action's own key
    ///         set untouched.
    function executeReadyAction(uint256 pickSeed_, uint256 executorSeed_) external {
        uint256 index = _pickLiveAction(pickSeed_);
        if (index == NOT_FOUND) return;
        if (!_isExecutableNow(index)) return;
        GhostAction storage ghost = _ghostActions[index];
        bytes32 offDigestBefore = _offDomainDigest(index);
        // casting to 'uint64' is safe because the registry index is the action id minus one
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 actionId = uint64(index + 1);
        address executor = _executor(executorSeed_);

        vm.prank(executor);
        timelock.executeQueuedAction(actionId);

        ghost.status = 1;
        liveActionCount -= 1;
        _assertKeysReleased(index, "execution");
        if (_offDomainDigest(index) != offDigestBefore) {
            ghost_dispatchWroteOutsideDomains = true;
        }
        dispatchDomainChecks += 1;
        executes += 1;
    }

    /// @notice Cancels a live action as one of the three permitted classes. The action is
    ///         guarded on liveness alone: cancellation must succeed in every product state the
    ///         sequence reaches, whatever the lifecycle, the seat or the recorded hashes say.
    function cancelLiveAction(uint256 pickSeed_, uint256 callerSeed_) external {
        uint256 index = _pickLiveAction(pickSeed_);
        if (index == NOT_FOUND) return;
        GhostAction storage ghost = _ghostActions[index];
        // The proposer of every handler action is the bridge admin
        address caller = [admin, emergency, bridgeAdmin][callerSeed_ % 3];
        bool wasExpired = vm.getBlockTimestamp() > ghost.expiresAt;
        bool timelockWasDisabled = !timelock.isEnabled();
        // casting to 'uint64' is safe because the registry index is the action id minus one
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 actionId = uint64(index + 1);

        vm.prank(caller);
        timelock.cancelQueuedAction(actionId);

        ghost.status = 2;
        liveActionCount -= 1;
        _assertKeysReleased(index, "cancellation");
        ITimelockBatchQueue.QueuedAction memory stored = timelock.getQueuedAction(actionId);
        assertTrue(stored.cancelled, "the cancelled flag must be set");
        assertFalse(stored.executed, "the executed flag must stay clear");
        cancels += 1;
        if (wasExpired) cancelsOfExpired += 1;
        if (timelockWasDisabled) cancelsWhileTimelockDisabled += 1;
    }

    // ========== NEGATIVE PROBES ========== //

    /// @notice Fires a queue attempt the registry and live state predict as invalid and
    ///         requires the exact predicted revert: a conflicting queue must name the first
    ///         reserved key in reservation order and its live owner, a closed gate must raise
    ///         its own error, and the allowlist entry point must always stop at the pool's
    ///         missing allowlist. Afterwards nothing may be reserved and no id consumed.
    function probeRejectedQueue(uint256 seed_) external {
        (bytes memory callData, bytes memory expectedRevert, uint8 mode) = _buildRejectedQueueProbe(
            seed_
        );
        if (callData.length == 0) return;
        uint64 nextIdBefore = timelock.nextActionId();

        bool succeeded = _callExpectingExactRevert(
            address(timelock),
            callData,
            expectedRevert,
            bridgeAdmin
        );

        if (succeeded) ghost_rejectedQueueSucceeded = true;
        assertEq(
            timelock.nextActionId(),
            nextIdBefore,
            "a rejected queue attempt must not consume an action id"
        );
        rejectedQueueProbes += 1;
        if (mode == 3) maskedMirrorProbes += 1;
    }

    /// @notice Fires an execution attempt the registry predicts as failing (a resolved id, a
    ///         closed window, a closed gate or a drifted state) and requires the exact
    ///         predicted revert in the contract's own check order. For a live action the probe
    ///         then asserts retention: the action is still live and still owns every reserved
    ///         key.
    function probeUntimelyExecute(uint256 pickSeed_) external {
        if (_ghostActions.length == 0) return;
        uint256 index = pickSeed_ % _ghostActions.length;
        GhostAction storage ghost = _ghostActions[index];
        // casting to 'uint64' is safe because the registry index is the action id minus one
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 actionId = uint64(index + 1);

        (bytes memory expectedRevert, uint8 probeClass) = _predictExecutionFailure(
            index,
            actionId,
            ghost
        );
        if (expectedRevert.length == 0) return;

        bool succeeded = _callExpectingExactRevert(
            address(timelock),
            abi.encodeCall(timelock.executeQueuedAction, (actionId)),
            expectedRevert,
            outsider
        );

        if (succeeded) ghost_untimelyExecuteSucceeded = true;
        if (ghost.status == 0) {
            // Retention: the failed attempt must leave the action live with every key held
            ITimelockBatchQueue.QueuedAction memory stored = timelock.getQueuedAction(actionId);
            assertFalse(stored.executed, "a failed execution must not mark the action executed");
            assertFalse(stored.cancelled, "a failed execution must not cancel the action");
            _assertKeysHeld(index);
        }
        untimelyExecuteProbes += 1;
        if (probeClass == 1) expiredRetentionChecks += 1;
        else if (probeClass == 2) gateRetentionChecks += 1;
        else if (probeClass == 3) driftRetentionChecks += 1;
        else if (probeClass == 4) resolvedReExecuteProbes += 1;
    }

    /// @notice Fires one gated state-changing entry point of the timelock as the roleless
    ///         outsider and records any success in a ghost flag: the authorization surface
    ///         must never expand, whatever state the sequence has reached. Some gates answer
    ///         before the caller check in some states, so the property this probe carries is
    ///         caller-independent non-success rather than a specific error; predicting the
    ///         per-state gate order would reimplement the production control flow without
    ///         strengthening the claim.
    ///
    ///         The two deliberately open entry points are outside the probe, since a success
    ///         there would be correct rather than a finding: execution is permissionless by
    ///         design, and the kernel dependency hook is unrestricted base behaviour.
    function probeUnauthorized(uint256 seed_) external {
        bytes memory payload = _unauthorizedProbePayload(seed_ % GATED_ENTRY_POINTS);

        vm.prank(outsider);
        // A low-level call so the expected revert does not bubble
        // forge-lint: disable-next-line(unchecked-call)
        (bool success, ) = address(timelock).call(payload);

        if (success) ghost_unauthorizedCallSucceeded = true;
        outsiderProbes += 1;
    }

    /// @notice Hands the pool ownership away, fires the execution of an otherwise fully
    ///         executable action, and hands the ownership back, all inside one action. The
    ///         dispatch must fail with the pool's own authority error and the action must
    ///         survive with every reserved key held: losing the pool freezes an action, it
    ///         never releases it. The round trip is atomic on purpose, because a persistent
    ///         loss would bench the whole guarded dispatch surface for the rest of a run.
    function probeDispatchWithoutPoolOwnership(uint256 pickSeed_) external {
        if (pool.owner() != address(config)) return;
        uint256 index = _pickExecutableAction(pickSeed_);
        if (index == NOT_FOUND) return;
        // The predicted rate limiter error assumes the config holds no rate limit admin seat
        // on the pool; this rig never grants one
        assertTrue(
            pool.getRateLimitAdmin() != address(config),
            "the config must not hold the pool rate limit admin seat"
        );
        // casting to 'uint64' is safe because the registry index is the action id minus one
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 actionId = uint64(index + 1);
        bool isRateLimitDispatch = _ghostSubs[index][0].selector ==
            ICCIPTokenPoolConfig.setChainRateLimits.selector;
        bytes memory expectedRevert = _predictOwnershipDispatchFailure(isRateLimitDispatch);

        vm.prank(admin);
        config.transferPoolOwnership(poolOwnerCandidate);
        vm.prank(poolOwnerCandidate);
        pool.acceptOwnership();
        assertEq(pool.owner(), poolOwnerCandidate, "the ownership hand-over must land");

        bool succeeded = _callExpectingExactRevert(
            address(timelock),
            abi.encodeCall(timelock.executeQueuedAction, (actionId)),
            expectedRevert,
            outsider
        );

        if (succeeded) ghost_dispatchWithoutOwnershipSucceeded = true;
        // Retention: the dispatch failure left the action live with every key still held
        ITimelockBatchQueue.QueuedAction memory stored = timelock.getQueuedAction(actionId);
        assertFalse(stored.executed, "a dispatch failure must not mark the action executed");
        assertFalse(stored.cancelled, "a dispatch failure must not cancel the action");
        _assertKeysHeld(index);

        vm.prank(poolOwnerCandidate);
        pool.transferOwnership(address(config));
        vm.prank(admin);
        config.acceptPoolOwnership();
        assertEq(pool.owner(), address(config), "the pool ownership must be restored");

        if (isRateLimitDispatch) ownershipRateLimitErrorProbes += 1;
        else ownershipOwnerErrorProbes += 1;
    }

    // ========== PROBE CONSTRUCTION ========== //

    /// @dev Builds a queue attempt that must fail together with the exact revert it must fail
    ///      with, and the mode tag of the shape it chose. The satisfiable modes are collected
    ///      from the live state and the seed picks one; empty calldata means no mode is
    ///      satisfiable. Mode 0 is a closed gate, 1 the unreachable allowlist domain, 2 a key
    ///      conflict and 3 the mirror failure that masks a held key.
    function _buildRejectedQueueProbe(
        uint256 seed_
    ) internal view returns (bytes memory callData, bytes memory expectedRevert, uint8 mode) {
        bytes memory attempt = _minimalRateLimitAttempt();

        if (!timelock.isEnabled() || !config.isEnabled()) {
            return (attempt, abi.encodeWithSelector(IEnabler.NotEnabled.selector), 0);
        }
        address seat = config.configOperator();
        if (seat != address(timelock)) {
            return (
                attempt,
                abi.encodeWithSelector(
                    ICCIPTokenPoolConfigTimelock
                        .CCIPTokenPoolConfigTimelock_NotConfigOperator
                        .selector,
                    seat
                ),
                0
            );
        }

        // Both gates are open: rotate between the unreachable allowlist entry point, a key
        // conflict predicted from the registry, and the mirror failure that masks a held key
        uint256 branch = seed_ % 3;
        if (branch == 0) {
            return (
                abi.encodeCall(
                    timelock.queueApplyAllowListUpdates,
                    (new address[](0), _singleAddress(outsider))
                ),
                abi.encodeWithSelector(ICCIPTokenPoolAdmin.AllowListNotEnabled.selector),
                1
            );
        }
        if (branch == 2) {
            (bytes memory maskedCall, bytes memory maskedRevert) = _buildMaskedMirrorProbe(seed_);
            if (maskedCall.length != 0) return (maskedCall, maskedRevert, 3);
        }
        (bytes memory conflictCall, bytes memory conflictRevert) = _buildConflictProbe(seed_);
        return (conflictCall, conflictRevert, 2);
    }

    /// @dev Builds a rate limit queue attempt against a selector whose route no longer exists
    ///      while a live action still holds its rate limits domain. The validation mirror
    ///      answers before the key walk, so the attempt reports a missing route rather than the
    ///      pending key: reconciliation tooling must not read that error as "the domain is
    ///      free". Empty calldata when no selector is in that state.
    function _buildMaskedMirrorProbe(
        uint256 seed_
    ) internal view returns (bytes memory callData, bytes memory expectedRevert) {
        uint256 count = trackedSelectors.length;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            uint64 candidate = trackedSelectors[(start + i) % count];
            if (pool.isSupportedChain(candidate)) continue;
            if (_ghostOwnerOf(_scopedKey(0, candidate)) == 0) continue;
            return (
                _minimalRateLimitAttemptFor(candidate),
                abi.encodeWithSelector(ICCIPTokenPoolAdmin.NonExistentChain.selector, candidate)
            );
        }
        return ("", "");
    }

    /// @dev The pool's own authority error for a dispatch that runs while the config no longer
    ///      owns the pool: the rate limiter setter also accepts the pool's rate limit admin and
    ///      raises its own error, every other route path is owner-only.
    function _predictOwnershipDispatchFailure(
        bool isRateLimitDispatch_
    ) internal view returns (bytes memory) {
        if (isRateLimitDispatch_) {
            return
                abi.encodeWithSelector(ICCIPTokenPoolAdmin.Unauthorized.selector, address(config));
        }
        return abi.encodeWithSelector(ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector);
    }

    /// @dev Builds a queue attempt that trips a key conflict against a live action, expecting
    ///      ConfigKeyPending for the first key of the attempt in reservation order that the
    ///      registry shows held.
    function _buildConflictProbe(
        uint256 seed_
    ) internal view returns (bytes memory callData, bytes memory expectedRevert) {
        uint256 index = _pickLiveAction(seed_);
        if (index == NOT_FOUND) return ("", "");
        GhostState memory state = _ghostStates[index][0][0];
        uint64 selector = state.chainSelector;

        if (state.domainKind == 1) {
            // The holder owns the remote pools domain alone; a pool addition walks straight
            // into it when the route exists, and an addChain reaches it after reserving the
            // free rate limits key when the route is gone
            if (pool.isSupportedChain(selector)) {
                bytes memory candidate = _absentPoolCandidate(selector, seed_);
                if (candidate.length == 0) return ("", "");
                return (
                    abi.encodeCall(timelock.queueAddRemotePool, (selector, candidate)),
                    _configKeyPendingRevert(index, state.scopedKey)
                );
            }
            if (_ghostOwnerOf(_scopedKey(0, selector)) != 0) return ("", "");
            return (
                abi.encodeCall(timelock.queueAddChain, (_buildChainUpdate(selector, seed_))),
                _configKeyPendingRevert(index, state.scopedKey)
            );
        }

        // The holder's first key is the rate limits domain (a rate limit action or any
        // three-key route action): a rate limit attempt conflicts on it when the route
        // exists, and an addChain attempt does when it does not
        if (pool.isSupportedChain(selector)) {
            return (
                _minimalRateLimitAttemptFor(selector),
                _configKeyPendingRevert(index, state.scopedKey)
            );
        }
        return (
            abi.encodeCall(timelock.queueAddChain, (_buildChainUpdate(selector, seed_))),
            _configKeyPendingRevert(index, state.scopedKey)
        );
    }

    function _configKeyPendingRevert(
        uint256 ownerIndex_,
        bytes32 scopedKey_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                scopedKey_,
                // casting to 'uint64' is safe because the registry index is the id minus one
                // forge-lint: disable-next-line(unsafe-typecast)
                uint64(ownerIndex_ + 1)
            );
    }

    /// @dev Predicts the exact failure of an execution attempt in the contract's own check
    ///      order: resolved flags, the time window, the lifecycle gates, the seat, then the
    ///      first drifted state in stored order. Returns empty bytes for a fully executable
    ///      action, which belongs to the guarded execute instead.
    function _predictExecutionFailure(
        uint256 index_,
        uint64 actionId_,
        GhostAction storage ghost_
    ) internal view returns (bytes memory expectedRevert, uint8 probeClass) {
        if (ghost_.status == 1) {
            return (
                abi.encodeWithSelector(
                    ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                    actionId_
                ),
                4
            );
        }
        if (ghost_.status == 2) {
            return (
                abi.encodeWithSelector(
                    ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                    actionId_
                ),
                4
            );
        }
        uint256 nowTs = vm.getBlockTimestamp();
        if (nowTs < ghost_.executableAt) {
            return (
                abi.encodeWithSelector(
                    ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                    actionId_,
                    ghost_.executableAt
                ),
                0
            );
        }
        if (nowTs > ghost_.expiresAt) {
            return (
                abi.encodeWithSelector(
                    ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                    actionId_,
                    ghost_.expiresAt
                ),
                1
            );
        }
        if (!timelock.isEnabled() || !config.isEnabled()) {
            return (abi.encodeWithSelector(IEnabler.NotEnabled.selector), 2);
        }
        address seat = config.configOperator();
        if (seat != address(timelock)) {
            return (
                abi.encodeWithSelector(
                    ICCIPTokenPoolConfigTimelock
                        .CCIPTokenPoolConfigTimelock_NotConfigOperator
                        .selector,
                    seat
                ),
                2
            );
        }
        uint256 drifted = _firstDriftedState(index_);
        if (drifted == NOT_FOUND) return ("", 0);
        (uint256 subIndex, uint256 stateIndex) = (drifted >> 128, drifted & type(uint128).max);
        GhostState memory state = _ghostStates[index_][subIndex][stateIndex];
        return (
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId_,
                subIndex,
                state.scopedKey,
                state.expectedHash,
                _currentDomainHash(state.domainKind, state.chainSelector)
            ),
            3
        );
    }

    /// @dev Fires the call as the caller and tolerates only the exact expected revert bytes:
    ///      an unpredicted revert bubbles so the run fails, and a success is reported back for
    ///      the ghost flags.
    function _callExpectingExactRevert(
        address target_,
        bytes memory callData_,
        bytes memory expectedRevert_,
        address caller_
    ) internal returns (bool succeeded) {
        vm.prank(caller_);
        // A low-level call so the expected revert does not bubble
        // forge-lint: disable-next-line(unchecked-call)
        (bool ok, bytes memory returnData) = target_.call(callData_);
        if (ok) return true;
        if (keccak256(returnData) != keccak256(expectedRevert_)) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
        return false;
    }

    // ========== GHOST REGISTRATION ========== //

    /// @dev Reads the id and timestamps the next queue call must produce; called immediately
    ///      before the queue so the recorded values are the handler's own prediction.
    function _prepareRegistration() internal returns (uint256 index) {
        index = _ghostActions.length;
        // casting to 'uint48' is safe for realistic test timestamps
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 queuedAt = uint48(vm.getBlockTimestamp());
        uint48 executableAt = queuedAt + timelock.timelockDelay();
        _ghostActions.push(
            GhostAction({
                proposer: bridgeAdmin,
                queuedAt: queuedAt,
                executableAt: executableAt,
                expiresAt: executableAt + EXECUTION_WINDOW,
                status: 0,
                subCount: 0
            })
        );
        liveActionCount += 1;
        return index;
    }

    /// @dev Verifies the contract handed out exactly the id the registry predicted.
    function _finishRegistration(uint256 index_, uint64 actionId_) internal {
        assertEq(
            uint256(actionId_),
            index_ + 1,
            "the queued action id must match the registry prediction"
        );
    }

    function _registerSub(uint256 index_, bytes4 selector_, bytes memory payload_) internal {
        _ghostSubs[index_].push(GhostSub({selector: selector_, payload: payload_}));
        _ghostActions[index_].subCount += 1;
    }

    /// @dev Records one reserved state, recomputing the hash from the live pool; must run in
    ///      the same block as the queue call and before any further state change.
    function _registerState(
        uint256 index_,
        uint256 subIndex_,
        uint8 domainKind_,
        uint64 chainSelector_
    ) internal {
        _ghostStates[index_][subIndex_].push(
            GhostState({
                scopedKey: _scopedKey(domainKind_, chainSelector_),
                expectedHash: _currentDomainHash(domainKind_, chainSelector_),
                domainKind: domainKind_,
                chainSelector: chainSelector_
            })
        );
    }

    /// @dev Records the three route states of a three-key action in the reservation order the
    ///      production code uses: rate limits, remote pools, route identity.
    function _registerRouteStates(
        uint256 index_,
        uint256 subIndex_,
        uint64 chainSelector_
    ) internal {
        _registerState(index_, subIndex_, 0, chainSelector_);
        _registerState(index_, subIndex_, 1, chainSelector_);
        _registerState(index_, subIndex_, 2, chainSelector_);
    }

    // ========== GUARD AND SELECTION HELPERS ========== //

    function _queueGatesOpen() internal view returns (bool) {
        return
            timelock.isEnabled() &&
            config.isEnabled() &&
            config.configOperator() == address(timelock);
    }

    function _pickSelector(uint256 seed_) internal view returns (uint64) {
        return trackedSelectors[seed_ % trackedSelectors.length];
    }

    /// @dev Scans the registry circularly from the seed for a live action; NOT_FOUND when the
    ///      registry holds none.
    function _pickLiveAction(uint256 seed_) internal view returns (uint256 index) {
        uint256 count = _ghostActions.length;
        if (count == 0) return NOT_FOUND;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            uint256 candidate = (start + i) % count;
            if (_ghostActions[candidate].status == 0) return candidate;
        }
        return NOT_FOUND;
    }

    /// @dev Whether the action is executable right now: live, inside its window, both
    ///      lifecycles open, the seat still on this timelock and no recorded state drifted.
    ///      The guarded execution and the ownership probe share this predicate, so the probe
    ///      can never pick an action that would fail for a reason other than the missing pool
    ///      ownership.
    function _isExecutableNow(uint256 index_) internal view returns (bool) {
        GhostAction storage ghost = _ghostActions[index_];
        if (ghost.status != 0) return false;
        uint256 nowTs = vm.getBlockTimestamp();
        if (nowTs < ghost.executableAt || nowTs > ghost.expiresAt) return false;
        if (!timelock.isEnabled() || !config.isEnabled()) return false;
        if (config.configOperator() != address(timelock)) return false;
        return _firstDriftedState(index_) == NOT_FOUND;
    }

    /// @dev Scans the registry circularly from the seed for an executable action; NOT_FOUND
    ///      when none is executable right now.
    function _pickExecutableAction(uint256 seed_) internal view returns (uint256 index) {
        uint256 count = _ghostActions.length;
        if (count == 0) return NOT_FOUND;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            uint256 candidate = (start + i) % count;
            if (_isExecutableNow(candidate)) return candidate;
        }
        return NOT_FOUND;
    }

    /// @dev The unique live owner of a scoped key per the registry, or zero.
    function _ghostOwnerOf(bytes32 scopedKey_) internal view returns (uint64 actionId) {
        for (uint256 i; i < _ghostActions.length; ++i) {
            if (_ghostActions[i].status != 0) continue;
            uint256 subCount = _ghostActions[i].subCount;
            for (uint256 s; s < subCount; ++s) {
                GhostState[] storage states = _ghostStates[i][s];
                for (uint256 k; k < states.length; ++k) {
                    if (states[k].scopedKey == scopedKey_) {
                        // casting to 'uint64' is safe: the index is the id minus one
                        // forge-lint: disable-next-line(unsafe-typecast)
                        return uint64(i + 1);
                    }
                }
            }
        }
        return 0;
    }

    function _routeDomainsFree(uint64 selector_) internal view returns (bool) {
        return
            _ghostOwnerOf(_scopedKey(0, selector_)) == 0 &&
            _ghostOwnerOf(_scopedKey(1, selector_)) == 0 &&
            _ghostOwnerOf(_scopedKey(2, selector_)) == 0;
    }

    /// @dev A pool candidate the route does not currently accept; empty bytes when every
    ///      candidate is already a member.
    function _absentPoolCandidate(
        uint64 selector_,
        uint256 seed_
    ) internal view returns (bytes memory candidate) {
        uint256 count = poolCandidates.length;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            bytes memory probe = poolCandidates[(start + i) % count];
            if (!pool.isRemotePool(selector_, probe)) return probe;
        }
        return "";
    }

    /// @dev A routed selector whose rate limits domain is free per the registry.
    function _findFreeRateLimitSlot(
        uint256 seed_
    ) internal view returns (bool found, uint64 selector) {
        uint256 count = trackedSelectors.length;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            uint64 candidate = trackedSelectors[(start + i) % count];
            if (!pool.isSupportedChain(candidate)) continue;
            if (_ghostOwnerOf(_scopedKey(0, candidate)) != 0) continue;
            return (true, candidate);
        }
        return (false, 0);
    }

    /// @dev A routed selector whose remote pools domain is free and that still has an absent
    ///      pool candidate to add.
    function _findFreePoolAdditionSlot(
        uint256 seed_
    ) internal view returns (bool found, uint64 selector, bytes memory candidate) {
        uint256 count = trackedSelectors.length;
        uint256 start = seed_ % count;
        for (uint256 i; i < count; ++i) {
            uint64 probe = trackedSelectors[(start + i) % count];
            if (!pool.isSupportedChain(probe)) continue;
            if (_ghostOwnerOf(_scopedKey(1, probe)) != 0) continue;
            bytes memory poolCandidate = _absentPoolCandidate(probe, seed_);
            if (poolCandidate.length == 0) continue;
            return (true, probe, poolCandidate);
        }
        return (false, 0, "");
    }

    /// @dev A rotating executor for the permissionless execution: a seed-derived fresh address
    ///      or one of the known actors.
    function _executor(uint256 seed_) internal view returns (address) {
        if (seed_ % 3 == 0) {
            address derived = address(uint160(uint256(keccak256(abi.encode("executor", seed_)))));
            return derived == address(0) ? outsider : derived;
        }
        return [outsider, admin, emergency, bridgeAdmin][seed_ % 4];
    }

    /// @dev One gated state-changing entry point per branch, in a fixed order: the five
    ///      lifecycle and configuration writers, the eight queue entry points, the
    ///      cancellation and the kernel migration hook. The arguments are minimal on purpose,
    ///      because the caller check of every one of them answers before any argument is
    ///      inspected.
    function _unauthorizedProbePayload(uint256 branch_) internal view returns (bytes memory) {
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
        if (branch_ == 4) return abi.encodeCall(timelock.setTimelockDelay, (uint48(2 days)));
        if (branch_ == 5) {
            return abi.encodeCall(timelock.queueAddChain, (_buildChainUpdate(selector, branch_)));
        }
        if (branch_ == 6) return abi.encodeCall(timelock.queueRemoveChain, (selector));
        if (branch_ == 7) {
            return abi.encodeCall(timelock.queueSetRemoteToken, (selector, tokenCandidates[0]));
        }
        if (branch_ == 8) {
            return abi.encodeCall(timelock.queueAddRemotePool, (selector, poolCandidates[0]));
        }
        if (branch_ == 9) {
            return abi.encodeCall(timelock.queueRemoveRemotePool, (selector, poolCandidates[0]));
        }
        if (branch_ == 10) {
            return
                abi.encodeCall(
                    timelock.queueApplyAllowListUpdates,
                    (new address[](0), _singleAddress(outsider))
                );
        }
        if (branch_ == 11) {
            return
                abi.encodeCall(
                    timelock.queueSetChainRateLimits,
                    (selector, someConfig, someConfig)
                );
        }
        if (branch_ == 12) {
            ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](
                1
            );
            batch[0] = ITimelockBatchQueue.BatchAction({
                target: address(config),
                selector: ICCIPTokenPoolConfig.setChainRateLimits.selector,
                payload: abi.encode(selector, someConfig, someConfig)
            });
            return abi.encodeCall(timelock.queueBatch, (batch));
        }
        if (branch_ == 13) {
            // A live id reaches the authorization check; with none live the queue state check
            // answers first and the call fails there instead
            uint256 index = _pickLiveAction(branch_);
            // casting to 'uint64' is safe because the registry index is the id minus one
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 actionId = index == NOT_FOUND ? 1 : uint64(index + 1);
            return abi.encodeCall(ITimelockBatchQueue.cancelQueuedAction, (actionId));
        }
        return abi.encodeCall(timelock.changeKernel, (Kernel(address(0))));
    }

    function _singleAddress(address entry_) internal pure returns (address[] memory entries) {
        entries = new address[](1);
        entries[0] = entry_;
        return entries;
    }

    /// @dev A minimal, mirror-valid rate limit queue attempt for the first tracked selector;
    ///      used by gate probes where the call never reaches the mirror.
    function _minimalRateLimitAttempt() internal view returns (bytes memory) {
        return _minimalRateLimitAttemptFor(trackedSelectors[0]);
    }

    function _minimalRateLimitAttemptFor(uint64 selector_) internal pure returns (bytes memory) {
        ICCIPRateLimiter.Config memory minimal = ICCIPRateLimiter.Config({
            isEnabled: true,
            capacity: 10,
            rate: 1
        });
        return
            abi.encodeCall(
                ICCIPTokenPoolConfigTimelock.queueSetChainRateLimits,
                (selector_, minimal, minimal)
            );
    }

    /// @dev Enabled rate limiter configurations bounded so the config accepts them: the
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

    /// @dev A validated chain update over the candidate space: one or two remote pools, a
    ///      token candidate and bounded enabled configurations.
    function _buildChainUpdate(
        uint64 selector_,
        uint256 seed_
    ) internal view returns (ICCIPTokenPoolAdmin.ChainUpdate memory update) {
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _boundedConfigs(seed_);
        bytes[] memory remotePools = new bytes[](1 + (seed_ % 2));
        uint256 firstIndex = seed_ % poolCandidates.length;
        remotePools[0] = poolCandidates[firstIndex];
        if (remotePools.length == 2) {
            remotePools[1] = poolCandidates[(firstIndex + 1) % poolCandidates.length];
        }
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: selector_,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: tokenCandidates[seed_ % tokenCandidates.length],
                outboundRateLimiterConfig: outbound,
                inboundRateLimiterConfig: inbound
            });
    }

    // ========== STATE OBSERVATION HELPERS ========== //

    /// @dev The destination-scoped key of a tracked domain, recomputed from the documented
    ///      shape: keccak256(abi.encode(config, localKey)) where the route local key is
    ///      keccak256(abi.encode(domain, selector)).
    function _scopedKey(uint8 domainKind_, uint64 chainSelector_) internal view returns (bytes32) {
        bytes32 domain = domainKind_ == 0 ? RATE_LIMITS_DOMAIN : domainKind_ == 1
            ? REMOTE_POOLS_DOMAIN
            : ROUTE_IDENTITY_DOMAIN;
        return
            keccak256(abi.encode(address(config), keccak256(abi.encode(domain, chainSelector_))));
    }

    /// @dev The current state hash of a tracked domain, recomputed from the live pool per the
    ///      documented preimages. Fill levels and refill timestamps are excluded on purpose.
    function _currentDomainHash(
        uint8 domainKind_,
        uint64 chainSelector_
    ) internal view returns (bytes32) {
        if (domainKind_ == 0) {
            ICCIPRateLimiter.TokenBucket memory outBucket = pool.getCurrentOutboundRateLimiterState(
                chainSelector_
            );
            ICCIPRateLimiter.TokenBucket memory inBucket = pool.getCurrentInboundRateLimiterState(
                chainSelector_
            );
            return
                keccak256(
                    abi.encode(
                        RATE_LIMITS_DOMAIN,
                        chainSelector_,
                        outBucket.isEnabled,
                        outBucket.capacity,
                        outBucket.rate,
                        inBucket.isEnabled,
                        inBucket.capacity,
                        inBucket.rate
                    )
                );
        }
        if (domainKind_ == 1) {
            bytes[] memory remotePools = pool.getRemotePools(chainSelector_);
            bytes32 aggregate;
            for (uint256 i; i < remotePools.length; ++i) {
                aggregate ^= keccak256(remotePools[i]);
            }
            return
                keccak256(
                    abi.encode(REMOTE_POOLS_DOMAIN, chainSelector_, remotePools.length, aggregate)
                );
        }
        return
            keccak256(
                abi.encode(
                    ROUTE_IDENTITY_DOMAIN,
                    chainSelector_,
                    pool.isSupportedChain(chainSelector_),
                    pool.getRemoteToken(chainSelector_)
                )
            );
    }

    /// @dev The current allowlist hash, part of the untouched-domain digest: on this rig no
    ///      action can ever reserve the domain, so no dispatch may move it either.
    function _currentAllowListHash() internal view returns (bytes32) {
        address[] memory allowList = pool.getAllowList();
        bytes32 aggregate;
        for (uint256 i; i < allowList.length; ++i) {
            aggregate ^= keccak256(abi.encode(allowList[i]));
        }
        return
            keccak256(
                abi.encode(
                    ALLOWLIST_DOMAIN,
                    pool.getAllowListEnabled(),
                    allowList.length,
                    aggregate
                )
            );
    }

    /// @dev The first recorded state of an action whose current hash no longer matches, in
    ///      stored (sub, state) order; packs the coordinates as (subIndex << 128 | stateIndex)
    ///      and returns NOT_FOUND when nothing drifted.
    function _firstDriftedState(uint256 index_) internal view returns (uint256 packed) {
        uint256 subCount = _ghostActions[index_].subCount;
        for (uint256 s; s < subCount; ++s) {
            GhostState[] storage states = _ghostStates[index_][s];
            for (uint256 k; k < states.length; ++k) {
                if (
                    _currentDomainHash(states[k].domainKind, states[k].chainSelector) !=
                    states[k].expectedHash
                ) {
                    return (s << 128) | k;
                }
            }
        }
        return NOT_FOUND;
    }

    /// @dev Whether an action's recorded key set contains a tracked domain.
    function _actionHoldsDomain(
        uint256 index_,
        uint8 domainKind_,
        uint64 chainSelector_
    ) internal view returns (bool) {
        bytes32 scopedKey = _scopedKey(domainKind_, chainSelector_);
        uint256 subCount = _ghostActions[index_].subCount;
        for (uint256 s; s < subCount; ++s) {
            GhostState[] storage states = _ghostStates[index_][s];
            for (uint256 k; k < states.length; ++k) {
                if (states[k].scopedKey == scopedKey) return true;
            }
        }
        return false;
    }

    /// @dev Digest over every tracked domain hash OUTSIDE the action's own reserved key set,
    ///      plus the allowlist domain. Compared around a dispatch, it pins that every state
    ///      write of a dispatched config call lies inside the domains its own action reserved.
    function _offDomainDigest(uint256 index_) internal view returns (bytes32) {
        bytes memory acc = abi.encode(_currentAllowListHash());
        for (uint256 s; s < trackedSelectors.length; ++s) {
            uint64 selector = trackedSelectors[s];
            for (uint8 kind; kind < 3; ++kind) {
                if (_actionHoldsDomain(index_, kind, selector)) continue;
                acc = bytes.concat(acc, abi.encode(_currentDomainHash(kind, selector)));
            }
        }
        return keccak256(acc);
    }

    /// @dev Every key recorded for the action reads as free after a resolution.
    function _assertKeysReleased(uint256 index_, string memory context_) internal view {
        uint256 subCount = _ghostActions[index_].subCount;
        for (uint256 s; s < subCount; ++s) {
            GhostState[] storage states = _ghostStates[index_][s];
            for (uint256 k; k < states.length; ++k) {
                assertEq(
                    timelock.pendingActionId(states[k].scopedKey),
                    0,
                    string.concat(context_, " must release every reserved key")
                );
            }
        }
    }

    /// @dev Every key recorded for the action is still owned by it.
    function _assertKeysHeld(uint256 index_) internal view {
        uint256 subCount = _ghostActions[index_].subCount;
        for (uint256 s; s < subCount; ++s) {
            GhostState[] storage states = _ghostStates[index_][s];
            for (uint256 k; k < states.length; ++k) {
                assertEq(
                    timelock.pendingActionId(states[k].scopedKey),
                    index_ + 1,
                    "a failed execution must retain every reserved key"
                );
            }
        }
    }
}
