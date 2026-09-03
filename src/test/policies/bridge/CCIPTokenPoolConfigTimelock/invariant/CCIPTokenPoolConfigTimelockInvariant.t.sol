// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {CCIPTokenPoolConfigTimelockHandler} from "./CCIPTokenPoolConfigTimelockHandler.sol";
import {CCIPTokenPoolConfigTimelockTest} from "../CCIPTokenPoolConfigTimelockTest.sol";

/// @notice Stateful invariant suite for CCIPTokenPoolConfigTimelock. The fuzzer drives the
///         handler's guarded action surface (the typed queue entry points and the batch,
///         permissionless execution, cancellation by every permitted class, both lifecycles,
///         operator-seat rotation, delay and grace-window writes, the direct config paths
///         that drift recorded state, containment, bucket consumption, and bounded plus
///         targeted time skips); the invariants reconcile the contract's queue views against
///         the handler's ghost registry and read its ghost flags.
/// @dev    The run starts from the operational baseline: the config enabled, owning the pool
///         and naming the enabled timelock as its config operator. The registry is the
///         independent oracle: ids, timestamps, canonical payloads, scoped keys and state
///         hashes are all recorded from the handler's own recomputation at queue time, never
///         read back from the contract, so a divergence between the two is always a finding
///         against the production bookkeeping. Negative probes (a conflicting or gated queue
///         attempt, an untimely or drifted execution) predict their exact revert bytes and
///         assert afterwards that nothing was reserved, resolved or released; the
///         invariant_handler_* functions assert those checks actually ran, following the
///         bootstrap pattern of the two existing invariant suites.
///
///         Two further probes cover authority rather than bookkeeping: a roleless outsider
///         sweeps every gated state-changing entry point and must fail on all of them, and an
///         atomic hand-over of the pool ownership proves that a dispatch failing inside the
///         pool freezes its action instead of releasing its domains.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CCIPTokenPoolConfigTimelockTests_Invariants is CCIPTokenPoolConfigTimelockTest {
    CCIPTokenPoolConfigTimelockHandler internal handler;

    function setUp() public override {
        super.setUp();

        // Operational baseline: the timelock is enabled over the enabled config that already
        // owns the pool and names it as config operator
        vm.prank(admin);
        timelock.enable("");

        handler = new CCIPTokenPoolConfigTimelockHandler(
            timelock,
            config,
            ohm,
            ccipRouter,
            rmnProxy,
            admin,
            emergency,
            bridgeAdmin,
            bridgeRateLimiter
        );
        vm.label(address(handler), "handler");

        // Bootstrap the coverage counters by running real handler actions, so every
        // verification path is exercised deterministically and no run starts at zero:
        // routes, queues of every width, a batch, both rejected-queue probe families, a
        // ripened execution with its dispatch-domain check, a re-queue of the freed domain,
        // drift plus the drifted-execution probe, expiry plus the expired-execution probe, a
        // resolved-id probe, cancellations by all three classes (one of an expired action,
        // one while the timelock is disabled), the closed-window reEnable probe, the config
        // lifecycle toggle, the seat rotation with its gate probe, consumption, the delay and
        // grace writes, containment and the direct drift actors, the outsider sweep over
        // the whole gated surface, and both authority errors of the ownership probe.
        handler.directAddRoute(0, 10);
        handler.directAddRoute(1, 11);
        handler.queueRateLimitChange(0, 20);
        handler.queueRouteAddition(2, 21);
        handler.queuePoolAddition(1, 22);
        handler.probeRejectedQueue(0);
        handler.probeRejectedQueue(1);
        handler.queueBatchPair(30);
        // A pending addChain leaves its route absent while holding its rate limits key, the
        // state the masked-mirror probe needs
        handler.probeRejectedQueue(5);
        for (uint256 i; i < 15; ++i) {
            handler.probeUnauthorized(i);
        }
        handler.ripenAction(0);
        // Seed zero picks the ready rate limit action (the pool's rate limiter authority
        // error), seed two the ready remote pool addition (the owner-only error)
        handler.probeDispatchWithoutPoolOwnership(0);
        handler.probeDispatchWithoutPoolOwnership(2);
        handler.executeReadyAction(0, 1);
        handler.queueRateLimitChange(0, 23);
        handler.directRateLimits(0, 24);
        handler.directRateLimits(1, 25);
        handler.probeUntimelyExecute(3);
        handler.expireAction(1);
        handler.probeUntimelyExecute(1);
        handler.probeUntimelyExecute(0);
        handler.cancelLiveAction(1, 0);
        handler.disableTimelock(0);
        handler.probeRejectedQueue(2);
        handler.probeUntimelyExecute(4);
        handler.cancelLiveAction(4, 1);
        for (uint256 i; i < 7; ++i) {
            handler.skipTime(12 hours);
        }
        handler.reEnableTimelock(0);
        handler.enableTimelock(0);
        handler.cancelLiveAction(2, 2);
        handler.toggleConfigPolicy(0);
        handler.probeRejectedQueue(4);
        handler.toggleConfigPolicy(0);
        handler.rotateOperatorSeat(1);
        handler.probeRejectedQueue(6);
        handler.rotateOperatorSeat(0);
        handler.consumeOutbound(0, 500);
        handler.setDelay(2 days);
        handler.setGraceWindow(3 days);
        handler.containRoute(0, 0);
        handler.directPoolChange(0, 2);
        handler.directReplaceToken(1, 1);
        handler.directRemoveRoute(1);
        handler.queueRouteAddition(2, 40);

        require(handler.ghostActionCount() >= 6, "bootstrap: too few actions queued");
        require(handler.liveActionCount() >= 2, "bootstrap: no live actions remain");
        require(handler.batchesQueued() > 0, "bootstrap: no batch was queued");
        require(handler.executes() > 0, "bootstrap: no execution ran");
        require(handler.dispatchDomainChecks() > 0, "bootstrap: no dispatch-domain check ran");
        require(handler.cancels() > 2, "bootstrap: not every canceller class ran");
        require(handler.cancelsOfExpired() > 0, "bootstrap: no expired action was cancelled");
        require(
            handler.cancelsWhileTimelockDisabled() > 0,
            "bootstrap: no cancellation ran while disabled"
        );
        require(handler.rejectedQueueProbes() > 4, "bootstrap: rejected-queue probes missing");
        require(handler.expiredRetentionChecks() > 0, "bootstrap: no expired retention check");
        require(handler.driftRetentionChecks() > 0, "bootstrap: no drift retention check");
        require(handler.gateRetentionChecks() > 0, "bootstrap: no gate retention check");
        require(handler.resolvedReExecuteProbes() > 0, "bootstrap: no resolved-id probe ran");
        require(handler.lifecycleTransitions() > 1, "bootstrap: the lifecycle did not cycle");
        require(
            handler.reEnableProbesPastDeadline() > 0,
            "bootstrap: the closed-window reEnable probe did not run"
        );
        require(handler.configLifecycleToggles() > 1, "bootstrap: the config did not cycle");
        require(handler.seatRotations() > 1, "bootstrap: the seat did not rotate");
        require(handler.consumptions() > 0, "bootstrap: no bucket consumption ran");
        require(handler.delayWrites() > 0, "bootstrap: no delay write ran");
        require(handler.graceWindowWrites() > 0, "bootstrap: no grace window write ran");
        require(handler.containmentCalls() > 0, "bootstrap: no containment ran");
        require(handler.directRouteChanges() > 4, "bootstrap: the drift actors did not run");
        require(handler.ripens() > 0, "bootstrap: no ripening skip ran");
        require(handler.expiries() > 0, "bootstrap: no expiry skip ran");
        require(
            handler.outsiderProbes() >= 15,
            "bootstrap: the outsider sweep did not cover the gated surface"
        );
        require(handler.maskedMirrorProbes() > 0, "bootstrap: no masked-mirror probe ran");
        require(
            handler.ownershipOwnerErrorProbes() > 0,
            "bootstrap: no owner-only ownership probe ran"
        );
        require(
            handler.ownershipRateLimitErrorProbes() > 0,
            "bootstrap: no rate limiter ownership probe ran"
        );

        targetContract(address(handler));
    }

    // ========== REGISTRY RECONCILIATION ========== //

    /// @notice The contract's stored queue never diverges from the ghost registry: for every
    ///         action the handler ever queued, the stored proposer and timestamps equal the
    ///         handler's own queue-time prediction (so no sequence of delay changes or
    ///         lifecycle transitions ever moves them), a resolved action carries exactly its
    ///         resolution flag with the sub-actions cleared, and a live action still stores
    ///         the canonical payloads, the destination, the scoped keys and the reservation
    ///         hashes recorded at queue time, holds every one of its keys through
    ///         pendingActionId, and never exceeds the 24-key budget.
    function invariant_registryMatchesStoredActions() public view {
        uint256 count = handler.ghostActionCount();
        for (uint256 i; i < count; ++i) {
            CCIPTokenPoolConfigTimelockHandler.GhostAction memory ghost = handler.ghostActionAt(i);
            // casting to 'uint64' is safe because the registry index is the id minus one
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 actionId = uint64(i + 1);
            ITimelockBatchQueue.QueuedAction memory stored = timelock.getQueuedAction(actionId);
            assertEq(stored.proposer, ghost.proposer, "stored proposer diverged");
            assertEq(stored.queuedAt, ghost.queuedAt, "stored queuedAt diverged");
            assertEq(stored.executableAt, ghost.executableAt, "stored executableAt diverged");
            assertEq(stored.expiresAt, ghost.expiresAt, "stored expiresAt diverged");

            if (ghost.status != 0) {
                assertEq(
                    stored.executed,
                    ghost.status == 1,
                    "the resolution flag diverged from the registry"
                );
                assertEq(
                    stored.cancelled,
                    ghost.status == 2,
                    "the cancellation flag diverged from the registry"
                );
                assertEq(stored.actions.length, 0, "a resolved action must clear its sub-actions");
                continue;
            }

            assertFalse(stored.executed, "a live action must not be marked executed");
            assertFalse(stored.cancelled, "a live action must not be marked cancelled");
            _reconcileLiveAction(i, actionId, ghost.subCount);
        }
    }

    /// @dev The stored sub-actions, destinations, keys and hashes of one live action against
    ///      the registry, plus the key budget.
    function _reconcileLiveAction(
        uint256 index_,
        uint64 actionId_,
        uint256 subCount_
    ) internal view {
        assertEq(
            timelock.getQueuedActionLength(actionId_),
            subCount_,
            "the stored sub-action count diverged"
        );
        uint256 totalKeys;
        for (uint256 s; s < subCount_; ++s) {
            CCIPTokenPoolConfigTimelockHandler.GhostSub memory sub = handler.ghostSubAt(index_, s);
            (address target, bytes4 storedSelector, bytes memory storedPayload) = timelock
                .getQueuedSubAction(actionId_, s);
            assertEq(target, address(config), "the stored target diverged");
            assertEq(storedSelector, sub.selector, "the stored selector diverged");
            assertEq(
                storedPayload,
                sub.payload,
                "the stored payload diverged from the canonical encoding"
            );
            assertEq(
                timelock.getQueuedConfigDestination(actionId_, s),
                address(config),
                "the stored destination diverged"
            );

            uint256 stateCount = handler.ghostStateCount(index_, s);
            assertEq(
                timelock.getQueuedConfigStateCount(actionId_, s),
                stateCount,
                "the stored config state count diverged"
            );
            totalKeys += stateCount;
            for (uint256 k; k < stateCount; ++k) {
                CCIPTokenPoolConfigTimelockHandler.GhostState memory state = handler.ghostStateAt(
                    index_,
                    s,
                    k
                );
                (bytes32 storedKey, bytes32 storedHash) = timelock.getQueuedConfigState(
                    actionId_,
                    s,
                    k
                );
                assertEq(storedKey, state.scopedKey, "the stored key diverged");
                assertEq(
                    storedHash,
                    state.expectedHash,
                    "the stored hash diverged from the queue-time recomputation"
                );
                assertEq(
                    timelock.pendingActionId(state.scopedKey),
                    actionId_,
                    "a live action lost the reservation of one of its keys"
                );
            }
        }
        assertLe(totalKeys, 24, "a live action exceeds the configuration key budget");
    }

    /// @notice Over the whole tracked key universe, the reservation bookkeeping and the ghost
    ///         registry agree: a key is reserved exactly when exactly one live ghost action
    ///         recorded it, and it names that action; the allowlist key stays free forever on
    ///         this rig, whose pool carries no allowlist.
    function invariant_keyOwnershipMatchesLiveGhostActions() public view {
        for (uint256 s; s < 5; ++s) {
            uint64 selector = handler.trackedSelectors(s);
            for (uint8 kind; kind < 3; ++kind) {
                bytes32 scopedKey = handler.scopedKeyOf(kind, selector);
                assertEq(
                    timelock.pendingActionId(scopedKey),
                    handler.ghostKeyOwner(scopedKey),
                    "a tracked key's owner diverged from the registry"
                );
            }
        }
        assertEq(
            timelock.pendingActionId(timelock.getAllowListKey()),
            0,
            "the allowlist key must never be reserved on the primary rig"
        );
    }

    /// @notice The contract hands out sequential ids starting at one and never recycles: the
    ///         next id always equals one plus the number of actions the handler ever queued,
    ///         so no queued action can ever carry id zero, the free-key sentinel of
    ///         pendingActionId.
    function invariant_nextActionIdMatchesGhostCount() public view {
        assertEq(
            timelock.nextActionId(),
            handler.ghostActionCount() + 1,
            "nextActionId diverged from the number of queued actions"
        );
    }

    // ========== LIFECYCLE ========== //

    /// @notice An enabled timelock always carries a non-zero transition timestamp: both
    ///         writers of the flag stamp the clock in the same slot write.
    function invariant_enabledImpliesTransitionTimestamp() public view {
        if (timelock.isEnabled()) {
            assertGt(
                uint256(timelock.lastTransitionAt()),
                0,
                "the enabled timelock must carry a transition timestamp"
            );
        }
    }

    /// @notice A reEnable call never succeeds once the grace deadline of the latest
    ///         transition has passed; past the window only the admin enable path restarts the
    ///         timelock. The handler probes the closed window deliberately.
    function invariant_reEnableNeverSucceedsPastGraceDeadline() public view {
        assertFalse(
            handler.ghost_reEnabledPastGraceDeadline(),
            "a reEnable succeeded past the grace deadline"
        );
    }

    // ========== NEGATIVE-PROBE GHOSTS ========== //

    /// @notice A queue attempt that must fail (a closed lifecycle or seat gate, the
    ///         unreachable allowlist domain, or a conflict on a reserved key) never succeeds
    ///         and never consumes an action id; validation and conflict checks precede every
    ///         reservation, so the failed attempt reserves nothing.
    function invariant_rejectedQueueAttemptsReserveNothing() public view {
        assertFalse(
            handler.ghost_rejectedQueueSucceeded(),
            "a queue attempt predicted invalid succeeded"
        );
    }

    /// @notice An execution attempt that must fail (a resolved id, a closed window, a closed
    ///         gate or a drifted state) never succeeds, and for a live action it retains the
    ///         action and every reserved key: expiry, lifecycle transitions, seat rotations
    ///         and drift hold keys hostage until an explicit cancellation releases them.
    function invariant_untimelyExecutionNeverLandsAndRetainsKeys() public view {
        assertFalse(
            handler.ghost_untimelyExecuteSucceeded(),
            "an execution attempt predicted invalid succeeded"
        );
    }

    /// @notice The authorization surface never expands: an account holding no role, no
    ///         operator grant and no proposership fails every gated state-changing entry point
    ///         of the timelock in every reachable state. The handler sweeps the five lifecycle
    ///         and configuration writers, the eight queue entry points, the cancellation and
    ///         the kernel migration hook. The two deliberately open entry points are outside
    ///         the sweep: permissionless execution and the unrestricted dependency hook are
    ///         documented behaviour, so a success there would not be a finding.
    function invariant_unauthorizedCallerNeverSucceeds() public view {
        assertFalse(
            handler.ghost_unauthorizedCallSucceeded(),
            "an unauthorized caller succeeded on a gated entry point"
        );
    }

    /// @notice An action never executes while the config policy has lost the ownership of the
    ///         pool it configures: the dispatch fails inside the pool with the pool's own
    ///         authority error, and the action keeps every reserved key. Losing the pool
    ///         freezes an action until someone cancels it; it never releases its domains. The
    ///         handler asserts the retention at the failure boundary and restores the
    ///         ownership inside the same action.
    function invariant_dispatchWithoutPoolOwnershipNeverLands() public view {
        assertFalse(
            handler.ghost_dispatchWithoutOwnershipSucceeded(),
            "an execution landed while the config did not own the pool"
        );
    }

    /// @notice A successful dispatch writes only inside the domains its own action reserved:
    ///         the recomputed hash of every tracked domain outside the executed action's key
    ///         set, and of the allowlist domain, is identical before and after the execution.
    ///         This is the foundation that keeps intra-batch reservations exclusive.
    function invariant_dispatchStaysInsideReservedDomains() public view {
        assertFalse(
            handler.ghost_dispatchWroteOutsideDomains(),
            "a dispatch wrote outside its action's reserved domains"
        );
    }

    // ========== COVERAGE SIGNALS ========== //
    //
    // The properties these signals stand for are enforced inside the handler at the action
    // boundary; the invariants only assert the checks actually ran. The counters are
    // bootstrapped in setUp by running real handler actions, so no run starts at zero.

    /// @notice The queue surface, the batch path, execution and every canceller class ran.
    function invariant_handler_queueSurfaceExercised() public view {
        assertGt(handler.queuesSucceeded(), 0, "no queue action ran");
        assertGt(handler.batchesQueued(), 0, "no batch was queued");
        assertGt(handler.executes(), 0, "no execution ran");
        assertGt(handler.dispatchDomainChecks(), 0, "no dispatch-domain check ran");
        assertGt(handler.cancels(), 0, "no cancellation ran");
    }

    /// @notice The retention states were exercised: probes against expired, drifted and gated
    ///         live actions, re-execution probes against resolved ids, rejected-queue probes,
    ///         and cancellations of an expired action and under a disabled timelock.
    function invariant_handler_retentionStatesExercised() public view {
        assertGt(handler.rejectedQueueProbes(), 0, "the rejected-queue probe never ran");
        assertGt(handler.untimelyExecuteProbes(), 0, "the untimely-execution probe never ran");
        assertGt(handler.expiredRetentionChecks(), 0, "no expired retention check ran");
        assertGt(handler.driftRetentionChecks(), 0, "no drift retention check ran");
        assertGt(handler.gateRetentionChecks(), 0, "no gate retention check ran");
        assertGt(handler.resolvedReExecuteProbes(), 0, "no resolved-id probe ran");
        assertGt(handler.cancelsOfExpired(), 0, "no expired action was cancelled");
        assertGt(
            handler.cancelsWhileTimelockDisabled(),
            0,
            "no cancellation ran while the timelock was disabled"
        );
    }

    /// @notice The authority probes ran: the outsider sweep over the gated surface, the
    ///         atomic ownership-loss probe on both of the pool's authority errors, and the
    ///         mirror failure that masks a held key.
    function invariant_handler_authorizationAndOwnershipProbed() public view {
        assertGt(handler.outsiderProbes(), 0, "the outsider probe never ran");
        assertGt(handler.ownershipOwnerErrorProbes(), 0, "no owner-only ownership probe ran");
        assertGt(handler.ownershipRateLimitErrorProbes(), 0, "no rate limiter ownership probe ran");
        assertGt(handler.maskedMirrorProbes(), 0, "the masked-mirror probe never ran");
    }

    /// @notice The lifecycle, the drift actors and the time design ran: transitions on both
    ///         policies, the closed-window probe, seat rotations, direct config changes,
    ///         containment, consumption, delay and grace writes, and the targeted skips.
    function invariant_handler_lifecycleAndDriftExercised() public view {
        assertGt(handler.lifecycleTransitions(), 0, "no lifecycle transition ran");
        assertGt(handler.reEnableProbesPastDeadline(), 0, "the closed-window probe never ran");
        assertGt(handler.configLifecycleToggles(), 0, "the config lifecycle never toggled");
        assertGt(handler.seatRotations(), 0, "the operator seat never rotated");
        assertGt(handler.directRouteChanges(), 0, "no direct drift action ran");
        assertGt(handler.containmentCalls(), 0, "no containment ran");
        assertGt(handler.consumptions(), 0, "no bucket consumption ran");
        assertGt(handler.delayWrites(), 0, "no delay write ran");
        assertGt(handler.graceWindowWrites(), 0, "no grace window write ran");
        assertGt(handler.ripens(), 0, "no ripening skip ran");
        assertGt(handler.expiries(), 0, "no expiry skip ran");
    }
}
