// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";

// Contracts
import {CCIPBridgeConfigHandler} from "./CCIPBridgeConfigHandler.sol";
import {CCIPBridgeConfigTest} from "../CCIPBridgeConfigTest.sol";

/// @notice Stateful invariant suite for CCIPBridgeConfig. The fuzzer drives the handler's
///         guarded action surface (lifecycle and the re-enable window, operator rotation,
///         routes, remote pools, remote token replacement, rate limits, containment, the
///         pool's router, rebalancer and rate limit admin, liquidity transfers from a funded
///         source pool, an ownership round trip, time skips, real bucket consumption through
///         the mock ramps, an unauthorized-caller probe and a direct-path bypass probe); the
///         invariants read the live pool state and the handler's ghost flags.
/// @dev    The run starts from the operational baseline: the policy enabled and owning the
///         pool. Every route of this suite is created through the config, so the
///         route-shape invariants describe what the config's validated paths can produce.
///         Action-boundary postconditions (lifecycle calls leave the pool untouched, the
///         token replacement preserves everything but the token, containment clamps without
///         refilling, consumption decrements exactly) are asserted inside the handler, where
///         the pre-state of the same call is observable; the invariant_handler_* functions
///         assert those checks ran, as a coverage signal, following the bootstrap pattern of
///         the OffsettingRateLimiter invariant suite.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CCIPBridgeConfigTests_Invariants is CCIPBridgeConfigTest {
    CCIPBridgeConfigHandler internal handler;

    function setUp() public override {
        super.setUp();

        // Operational baseline: the enabled policy owns the pool for the whole run
        vm.prank(admin);
        config.enable("");
        vm.prank(admin);
        config.acceptPoolOwnership();

        // The funded liquidity source of the transfer action; its rebalancer is the managed
        // pool, so the config's transfer path is the only way its tokens can move
        _deployLiquiditySource(true);

        handler = new CCIPBridgeConfigHandler(
            config,
            ohm,
            ccipRouter,
            rmnProxy,
            admin,
            emergency,
            bridgeAdmin,
            bridgeRateLimiter,
            operator,
            address(sourcePool)
        );
        vm.label(address(handler), "handler");

        // Bootstrap the coverage-signal counters by running real handler actions, so the
        // verification code paths are exercised by the bootstrap itself and the first
        // invariant call of every run observes non-zero counters:
        //   - addRoute + consumeOutbound + containChain: route, consumption, containment and
        //     fill-transition checks;
        //   - probeUnauthorized: the outsider surface;
        //   - disable, two two-day skips, reEnable, enable: lifecycle transitions plus the
        //     deliberate reEnable probe past the three-day grace deadline;
        //   - the admin infrastructure surface: an accepted and a rejected router candidate,
        //     the rebalancer, the rate limit grant with a probe on each side of it, one
        //     liquidity transfer, one grace window write and one ownership round trip.
        handler.addRoute(0, 0);
        handler.consumeOutbound(0, 5);
        handler.containChain(0, 0);
        handler.probeUnauthorized(0);
        handler.disablePolicy(0);
        handler.skipTime(2 days);
        handler.skipTime(2 days);
        handler.reEnablePolicy(0);
        handler.enablePolicy(0);
        handler.setPoolRouter(0);
        handler.setPoolRouter(3);
        handler.setPoolRebalancer(1);
        handler.setPoolRateLimitAdmin(1);
        handler.probeRateLimitAdminBypass(0);
        handler.setPoolRateLimitAdmin(0);
        handler.probeRateLimitAdminBypass(0);
        handler.transferSourceLiquidity(1);
        handler.setGraceWindow(GRACE_PERIOD);
        handler.ownershipRoundTrip(0);
        require(handler.routesAdded() > 0, "bootstrap: no route was added");
        require(handler.bucketConsumptions() > 0, "bootstrap: no consumption ran");
        require(handler.containmentCalls() > 0, "bootstrap: no containment ran");
        require(handler.fillTransitionsChecked() > 0, "bootstrap: no fill check ran");
        require(handler.outsiderProbes() > 0, "bootstrap: no outsider probe ran");
        require(handler.lifecycleTransitions() > 1, "bootstrap: lifecycle did not cycle");
        require(
            handler.reEnableProbesPastDeadline() > 0,
            "bootstrap: the closed-window reEnable probe did not run"
        );
        require(handler.poolDigestChecks() > 0, "bootstrap: no pool digest check ran");
        require(handler.routerChanges() > 0, "bootstrap: no router change ran");
        require(handler.routerRejections() > 0, "bootstrap: no router rejection ran");
        require(handler.rebalancerChanges() > 0, "bootstrap: no rebalancer change ran");
        require(
            handler.rateLimitAdminChanges() > 1,
            "bootstrap: the rate limit grant did not cycle"
        );
        require(
            handler.rateLimitBypassProbes() > 1,
            "bootstrap: the bypass probe did not run twice"
        );
        require(handler.liquidityTransfers() > 0, "bootstrap: no liquidity transfer ran");
        require(handler.graceWindowUpdates() > 0, "bootstrap: no grace window update ran");
        require(handler.ownershipRoundTrips() > 0, "bootstrap: no ownership round trip ran");

        targetContract(address(handler));
    }

    // ========== LIFECYCLE ========== //

    /// @notice An enabled policy always carries a non-zero transition timestamp: both
    ///         writers of the flag stamp the clock in the same slot write.
    function invariant_enabledImpliesTransitionTimestamp() public view {
        if (config.isEnabled()) {
            assertGt(
                uint256(config.lastTransitionAt()),
                0,
                "the enabled policy must carry a transition timestamp"
            );
        }
    }

    /// @notice A reEnable call never succeeds once the grace deadline of the latest
    ///         transition has passed; past the window only the admin enable path restarts
    ///         the policy. The handler probes the closed window deliberately.
    function invariant_reEnableNeverSucceedsPastGraceDeadline() public view {
        assertFalse(
            handler.ghost_reEnabledPastGraceDeadline(),
            "a reEnable succeeded past the grace deadline"
        );
    }

    // ========== ROUTE SHAPE ========== //

    /// @notice Every route reachable through the config carries enabled rate limiters in
    ///         both directions and at least one accepted remote pool, whatever sequence of
    ///         additions, removals, replacements, rate limit writes and containments
    ///         produced it.
    function invariant_routesCarryEnabledLimitersAndRemotePools() public view {
        uint64[] memory selectors = pool.getSupportedChains();
        for (uint256 i; i < selectors.length; ++i) {
            assertTrue(
                _outboundBucket(selectors[i]).isEnabled,
                "a configured route lost its enabled outbound limiter"
            );
            assertTrue(
                _inboundBucket(selectors[i]).isEnabled,
                "a configured route lost its enabled inbound limiter"
            );
            assertGt(
                pool.getRemotePools(selectors[i]).length,
                0,
                "a configured route lost its last remote pool"
            );
        }
    }

    // ========== DERIVED STATE ========== //

    /// @notice The containment view is a pure derivation of the pool state: for every
    ///         configured route it equals the recomputation of "both buckets hold
    ///         {enabled, capacity 2, rate 1}" from the projected buckets, and can never
    ///         drift from it.
    function invariant_isChainDisabledMatchesBucketState() public view {
        uint64[] memory selectors = pool.getSupportedChains();
        for (uint256 i; i < selectors.length; ++i) {
            bool expected = _isContainmentShape(_outboundBucket(selectors[i])) &&
                _isContainmentShape(_inboundBucket(selectors[i]));
            assertEq(
                config.isChainDisabled(selectors[i]),
                expected,
                "isChainDisabled drifted from the recomputation over the buckets"
            );
        }
    }

    // ========== GHOST STATE ========== //

    /// @notice No config-mediated call ever raises a bucket fill above both its pre-call
    ///         projected level and the two-unit floor: rate limit writes and containment
    ///         clamp downward, and the token replacement restores the projected fill with
    ///         the floor of two. The handler compares fills at every action boundary.
    function invariant_bucketFillNeverRaisedBeyondContainmentFloor() public view {
        assertFalse(
            handler.ghost_fillRaisedBeyondFloor(),
            "a config-mediated call raised a bucket fill beyond the floor"
        );
    }

    /// @notice The authorization surface never expands: an account holding no role and no
    ///         operator grant fails every state-changing function of the config in every
    ///         reachable state.
    function invariant_unauthorizedCallerNeverSucceeds() public view {
        assertFalse(
            handler.ghost_unauthorizedCallSucceeded(),
            "an unauthorized caller succeeded on a state-changing function"
        );
    }

    /// @notice Pool rate limits are never written by an account that holds neither the pool
    ///         ownership nor its rate limit admin grant. The handler grants and revokes the
    ///         grant across a sequence and probes the direct pool path from both sides, so a
    ///         revoked grant really closes the bypass.
    function invariant_poolRateLimitsRequireGrantedAuthority() public view {
        assertFalse(
            handler.ghost_rateLimitBypassWithoutGrant(),
            "an account without the rate limit grant wrote pool limits directly"
        );
    }

    // ========== POOL INFRASTRUCTURE ========== //

    /// @notice The pool's router always points at an account holding code: the config installs
    ///         a candidate only after its probe succeeds, and a rejected candidate never
    ///         replaces the current router.
    function invariant_poolRouterNeverCodeless() public view {
        assertGt(pool.getRouter().code.length, 0, "the pool router must always hold code");
    }

    /// @notice The pool ownership rests with the config at every action boundary: a proposal
    ///         alone never moves it, and the migration the suite drives hands it back within
    ///         the same call, so no sequence can strand the pool without its owner policy.
    function invariant_poolOwnershipRestsWithTheConfig() public view {
        assertEq(pool.owner(), address(config), "the pool ownership must rest with the config");
    }

    // ========== CUSTODY ========== //

    /// @notice The config policy never holds pool tokens: every flow it mediates moves
    ///         tokens between the pools and the ramps directly.
    function invariant_configPolicyHoldsNoTokens() public view {
        assertEq(
            ohm.balanceOf(address(config)),
            0,
            "the config policy must never hold pool tokens"
        );
    }

    /// @notice Every token that ever left the liquidity source left through the config's
    ///         transfer path: the source balance plus the recorded transfers equals the
    ///         funding it started with, whatever the sequence did in between.
    function invariant_liquiditySourceAccountingIsConserved() public view {
        assertEq(
            ohm.balanceOf(address(sourcePool)) + handler.ghost_liquidityMovedFromSource(),
            SOURCE_POOL_FUNDING,
            "the liquidity source accounting drifted from its funding"
        );
    }

    // ========== COVERAGE SIGNALS ========== //
    //
    // The properties these five signals stand for are enforced inside the handler at the
    // action boundary; the invariants only assert the checks actually ran. The counters are
    // bootstrapped in setUp by running real handler actions, so no run starts at zero.

    /// @notice The route lifecycle was exercised at least once.
    function invariant_handler_routeLifecycleExercised() public view {
        assertGt(handler.routesAdded(), 0, "no route addition ran");
    }

    /// @notice The containment surface was exercised at least once.
    function invariant_handler_containmentExercised() public view {
        assertGt(handler.containmentCalls(), 0, "no containment ran");
    }

    /// @notice The fill-transition ghost check ran at least once.
    function invariant_handler_fillTransitionsChecked() public view {
        assertGt(handler.fillTransitionsChecked(), 0, "the fill-transition check never ran");
    }

    /// @notice The outsider probe ran at least once.
    function invariant_handler_outsiderProbed() public view {
        assertGt(handler.outsiderProbes(), 0, "the outsider probe never ran");
    }

    /// @notice The lifecycle transitions and their pool-untouched digest checks ran.
    function invariant_handler_lifecycleExercised() public view {
        assertGt(handler.lifecycleTransitions(), 0, "no lifecycle transition ran");
        assertGt(handler.poolDigestChecks(), 0, "the pool digest check never ran");
    }

    /// @notice The admin infrastructure surface was exercised on both sides: an accepted and
    ///         a rejected router candidate, the rebalancer, the rate limit grant and the
    ///         re-enable window.
    function invariant_handler_adminInfrastructureExercised() public view {
        assertGt(handler.routerChanges(), 0, "no router installation ran");
        assertGt(handler.routerRejections(), 0, "no router rejection ran");
        assertGt(handler.rebalancerChanges(), 0, "no rebalancer write ran");
        assertGt(handler.rateLimitAdminChanges(), 0, "no rate limit admin write ran");
        assertGt(handler.graceWindowUpdates(), 0, "no grace window write ran");
    }

    /// @notice The liquidity transfer, the ownership migration and the direct-path bypass
    ///         probe ran.
    function invariant_handler_liquidityAndAuthorityExercised() public view {
        assertGt(handler.liquidityTransfers(), 0, "no liquidity transfer ran");
        assertGt(handler.ownershipRoundTrips(), 0, "no ownership round trip ran");
        assertGt(handler.rateLimitBypassProbes(), 0, "the rate limit bypass probe never ran");
    }

    // ========== INTERNAL ========== //

    function _isContainmentShape(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (bool) {
        return bucket_.isEnabled && bucket_.capacity == 2 && bucket_.rate == 1;
    }
}
