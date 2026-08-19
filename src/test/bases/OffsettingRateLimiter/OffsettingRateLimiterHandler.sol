// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {Test} from "@forge-std-1.16.2/Test.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Contracts
import {OffsettingRateLimiterHarness} from "src/test/bases/OffsettingRateLimiter/OffsettingRateLimiterHarness.sol";

/// @notice Invariant-test handler that wraps `OffsettingRateLimiterHarness` and
///         exposes a constrained set of mutating actions over a small fixed
///         eid space. Tracks ghost variables that observers can read after the
///         run to verify all interesting code paths were exercised.
/// @dev    Two key properties are enforced *inside the handler*, at the action
///         boundary, since contamination can only be detected there:
///           1. Direction-independence per eid: a setter / clear on one
///              direction must not mutate the counterpart's `(limit, window)`
///              (and a `clear*` must not touch any counterpart field at all).
///           2. Cross-eid independence: an action on one eid must not mutate
///              any other tracked eid's four-tuple.
///         The corresponding invariants in `OffsettingRateLimiter_Invariants.t.sol`
///         only assert that the handler-side checks ran, as a coverage signal.
contract OffsettingRateLimiterHandler is Test {
    // ========== TRACKED EIDS ========== //

    uint32 internal constant EID_A = 101;
    uint32 internal constant EID_B = 202;
    uint32 internal constant EID_C = 303;
    uint32 internal constant EID_D = 404;

    uint32[4] public trackedEids;

    // ========== HARNESS REFERENCE ========== //

    OffsettingRateLimiterHarness public immutable harness;

    // ========== ACTION BOUNDS ========== //

    uint256 internal constant MIN_LIMIT = 1;
    uint256 internal constant MAX_LIMIT = 1_000_000 ether;
    uint32 internal constant MIN_WINDOW = 1;
    uint32 internal constant MAX_WINDOW = 1 days;
    uint64 internal constant MAX_WARP = 1 days;
    uint32 internal constant DEFAULT_PRECONFIG_WINDOW = 1 hours;

    // ========== GHOST VARIABLES ========== //

    mapping(uint32 => uint256) public totalSuccessfulOutflow;
    mapping(uint32 => uint256) public totalSuccessfulInflow;
    uint256 public rateLimitExceededReverts;
    uint256 public counterpartFloorHits;
    uint256 public linearDecayPathTaken;
    uint256 public elapsedGreaterEqualWindowPathTaken;

    /// @dev Coverage counters for handler-side property checks. Read by
    ///      `invariant_handler_*` to verify the protocol ran.
    uint256 public directionIndependenceChecked;
    uint256 public crossEidIndependenceChecked;

    // ========== CONSTRUCTOR ========== //

    constructor(OffsettingRateLimiterHarness harness_) {
        harness = harness_;
        trackedEids[0] = EID_A;
        trackedEids[1] = EID_B;
        trackedEids[2] = EID_C;
        trackedEids[3] = EID_D;

        // Pre-configure each tracked eid on both directions so the action
        // surface is well-defined from the very first invariant call. Sample
        // the path counters here so the coverage-signal invariants do not
        // observe a zero counter at the very start of a run.
        for (uint256 i = 0; i < trackedEids.length; i++) {
            IOffsettingRateLimiter.RateLimitConfig[]
                memory configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
            configs[0] = IOffsettingRateLimiter.RateLimitConfig({
                eid: trackedEids[i],
                limit: MAX_LIMIT,
                window: DEFAULT_PRECONFIG_WINDOW
            });
            harness.setOutRateLimits(configs);
            harness.setInRateLimits(configs);
            _samplePathFlags(trackedEids[i]);
        }
    }

    // ========== HELPERS ========== //

    function _pickEid(uint256 seed_) internal view returns (uint32) {
        return trackedEids[seed_ % trackedEids.length];
    }

    /// @dev Sibling eid used to verify cross-eid independence. Picks a
    ///      different slot in the `trackedEids` array so reads never alias the
    ///      action's target.
    function _pickSiblingEid(uint32 targetEid_) internal view returns (uint32) {
        for (uint256 i = 0; i < trackedEids.length; i++) {
            if (trackedEids[i] != targetEid_) return trackedEids[i];
        }
        // Unreachable as long as the array length is > 1.
        return targetEid_;
    }

    function _samplePathFlags(uint32 eid_) internal {
        _samplePath(eid_, true);
        _samplePath(eid_, false);
    }

    function _samplePath(uint32 eid_, bool out_) internal {
        (, , uint32 window, uint48 lastUpdated) = out_
            ? harness.outRateLimits(eid_)
            : harness.inRateLimits(eid_);
        if (window == 0 || vm.getBlockTimestamp() - uint256(lastUpdated) >= window) {
            elapsedGreaterEqualWindowPathTaken += 1;
        } else {
            linearDecayPathTaken += 1;
        }
    }

    /// @dev Returns `(outLimit, outWindow, inLimit, inWindow)` for the given
    ///      eid. Used by the direction-independence checks.
    function _limitWindowPair(
        uint32 eid_
    ) internal view returns (uint256 outLimit, uint32 outWindow, uint256 inLimit, uint32 inWindow) {
        (, outLimit, outWindow, ) = harness.outRateLimits(eid_);
        (, inLimit, inWindow, ) = harness.inRateLimits(eid_);
    }

    /// @dev Returns the full `(inFlight, limit, window, lastUpdated)` for both
    ///      directions of `eid_`. Used by the cross-eid and clear-counterpart
    ///      checks.
    function _fullSnapshot(uint32 eid_) internal view returns (bytes32) {
        (uint256 outIn, uint256 outLim, uint32 outWin, uint48 outLu) = harness.outRateLimits(eid_);
        (uint256 inIn, uint256 inLim, uint32 inWin, uint48 inLu) = harness.inRateLimits(eid_);
        return keccak256(abi.encode(outIn, outLim, outWin, outLu, inIn, inLim, inWin, inLu));
    }

    // ========== ACTIONS ========== //

    function outflow(uint256 eidSeed_, uint256 amount_) external {
        uint32 eid = _pickEid(eidSeed_);
        // Sample the counterpart's path *before* the call so the ghost picks
        // up which decay branch this action triggers.
        _samplePathFlags(eid);

        // Bounded to MAX_LIMIT (not MAX_LIMIT * 2) so that `amount` is more
        // often comparable to the typical decayed counterpart in-flight, which
        // is what raises the probability of the floor branch firing.
        uint256 amount = bound(amount_, 0, MAX_LIMIT);

        // Snapshot for cross-eid independence.
        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        (uint256 inDecayedBefore, ) = harness.receivable(eid);

        try harness.outflow(eid, amount) {
            totalSuccessfulOutflow[eid] += amount;
            (uint256 inAfter, , , ) = harness.inRateLimits(eid);
            if (inDecayedBefore > 0 && inAfter == 0 && amount >= inDecayedBefore) {
                counterpartFloorHits += 1;
            }
        } catch (bytes memory err) {
            // Only count `RateLimitExceeded`; bubble panics and any other
            // unexpected reverts so the invariant run actually fails.
            if (bytes4(err) != IOffsettingRateLimiter.RateLimitExceeded.selector) {
                assembly {
                    revert(add(err, 0x20), mload(err))
                }
            }
            rateLimitExceededReverts += 1;
        }

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by outflow");
        crossEidIndependenceChecked += 1;
    }

    function inflow(uint256 srcEidSeed_, uint256 amount_) external {
        uint32 eid = _pickEid(srcEidSeed_);
        _samplePathFlags(eid);

        uint256 amount = bound(amount_, 0, MAX_LIMIT);

        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        (uint256 outDecayedBefore, ) = harness.sendable(eid);

        try harness.inflow(eid, amount) {
            totalSuccessfulInflow[eid] += amount;
            (uint256 outAfter, , , ) = harness.outRateLimits(eid);
            if (outDecayedBefore > 0 && outAfter == 0 && amount >= outDecayedBefore) {
                counterpartFloorHits += 1;
            }
        } catch (bytes memory err) {
            // Only count `RateLimitExceeded`; bubble panics and any other
            // unexpected reverts so the invariant run actually fails.
            if (bytes4(err) != IOffsettingRateLimiter.RateLimitExceeded.selector) {
                assembly {
                    revert(add(err, 0x20), mload(err))
                }
            }
            rateLimitExceededReverts += 1;
        }

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by inflow");
        crossEidIndependenceChecked += 1;
    }

    function setOut(uint256 eidSeed_, uint256 limit_, uint32 window_) external {
        uint32 eid = _pickEid(eidSeed_);
        uint256 limit = bound(limit_, 0, MAX_LIMIT);
        window_ = uint32(bound(uint256(window_), 0, MAX_WINDOW));

        // Direction-independence: setOut must not change the inbound
        // (limit, window) for the same eid.
        (, , uint256 inLimitBefore, uint32 inWindowBefore) = _limitWindowPair(eid);
        // Cross-eid independence: setOut must not change any other eid.
        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: eid,
            limit: limit,
            window: window_
        });
        harness.setOutRateLimits(configs);

        (, , uint256 inLimitAfter, uint32 inWindowAfter) = _limitWindowPair(eid);
        assertEq(inLimitAfter, inLimitBefore, "setOut changed in.limit");
        assertEq(inWindowAfter, inWindowBefore, "setOut changed in.window");
        directionIndependenceChecked += 1;

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by setOut");
        crossEidIndependenceChecked += 1;
    }

    function setIn(uint256 srcEidSeed_, uint256 limit_, uint32 window_) external {
        uint32 eid = _pickEid(srcEidSeed_);
        uint256 limit = bound(limit_, 0, MAX_LIMIT);
        window_ = uint32(bound(uint256(window_), 0, MAX_WINDOW));

        (uint256 outLimitBefore, uint32 outWindowBefore, , ) = _limitWindowPair(eid);
        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: eid,
            limit: limit,
            window: window_
        });
        harness.setInRateLimits(configs);

        (uint256 outLimitAfter, uint32 outWindowAfter, , ) = _limitWindowPair(eid);
        assertEq(outLimitAfter, outLimitBefore, "setIn changed out.limit");
        assertEq(outWindowAfter, outWindowBefore, "setIn changed out.window");
        directionIndependenceChecked += 1;

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by setIn");
        crossEidIndependenceChecked += 1;
    }

    function clearOut(uint256 eidsSeed_) external {
        uint32 eid = _pickEid(eidsSeed_);
        // For clear, the stronger property holds: the counterpart's *full
        // four-tuple* must remain unchanged (not just its (limit, window)).
        bytes32 inBefore = _inSnapshot(eid);
        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        uint32[] memory eids = new uint32[](1);
        eids[0] = eid;
        harness.clearOutboundInFlight(eids);

        assertEq(_inSnapshot(eid), inBefore, "clearOut touched in side");
        directionIndependenceChecked += 1;

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by clearOut");
        crossEidIndependenceChecked += 1;
    }

    function clearIn(uint256 eidsSeed_) external {
        uint32 eid = _pickEid(eidsSeed_);
        bytes32 outBefore = _outSnapshot(eid);
        uint32 sibling = _pickSiblingEid(eid);
        bytes32 siblingBefore = _fullSnapshot(sibling);

        uint32[] memory eids = new uint32[](1);
        eids[0] = eid;
        harness.clearInboundInFlight(eids);

        assertEq(_outSnapshot(eid), outBefore, "clearIn touched out side");
        directionIndependenceChecked += 1;

        assertEq(_fullSnapshot(sibling), siblingBefore, "sibling eid mutated by clearIn");
        crossEidIndependenceChecked += 1;
    }

    function warp(uint64 secs_) external {
        uint64 secs = uint64(bound(uint256(secs_), 1, MAX_WARP));
        vm.warp(vm.getBlockTimestamp() + secs);
    }

    // ========== READ-ONLY VIEWS ========== //

    function trackedEidsLength() external pure returns (uint256) {
        return 4;
    }

    function _outSnapshot(uint32 eid_) private view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.outRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }

    function _inSnapshot(uint32 eid_) private view returns (bytes32) {
        (uint256 inFlight, uint256 limit, uint32 window, uint48 lu) = harness.inRateLimits(eid_);
        return keccak256(abi.encode(inFlight, limit, window, lu));
    }
}
