// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Independent endpoint seeds and real-contract sequences.
// forge-lint: disable-start(literal-instead-of-constant, calls-loop)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";

contract BurnerLoansPayoutReEnableTest is BurnerLoansPayoutTest {
    modifier givenLifecycleClaims() {
        _seedBuckets(10, 20, 30, _keeper);
        _token.setTransferReverts(_secondKeeper, true);
        _creditReferral(_token, 0, _secondKeeper, 7);
        _deferFee(_otherToken, 11);
        _bindDistributor();
        _payout.setSendFeesToDistributor(true);
        _payout.setSendYieldToDistributor(true);
        _;
    }

    modifier givenDisabled() {
        _payout.disable("");
        _;
    }

    // Scenarios: BLCU-REENABLE-A02.
    function test_givenPermittedRole_whenReEnabled(
        address caller_,
        bool loanAdminOnly_,
        bool overlap_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenLifecycleClaims {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(loanAdminOnly_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_)
            _rolesAdmin.grantRole(loanAdminOnly_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
        _payout.disable("");
        // A previous Payout can still manage its local lifecycle and retained claims.
        _core.setPayout(address(_otherPayout));
        _setState(_core, coreActive_, coreEnabled_);
        vm.warp(2);
        _transition(caller_);
    }

    // Scenarios: BLCU-REENABLE-A02.
    function test_whenExclusiveRolesAndOverlapSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedRole_whenReEnabled(address(0x111), false, false, false, false);
        _restore(checkpoint);
        test_givenPermittedRole_whenReEnabled(address(0x112), true, false, false, true);
        _restore(checkpoint);
        test_givenPermittedRole_whenReEnabled(address(0x113), false, true, true, false);
        _restore(checkpoint);
        test_givenPermittedRole_whenReEnabled(address(0x114), true, true, true, true);
    }

    // Scenarios: BLCU-REENABLE-A01.
    function test_givenUnauthorized_whenReEnabled_reverts(
        address caller_
    ) public givenPendingBuckets givenDisabled {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.warp(uint256(_payout.lastTransitionAt()) + _payout.gracePeriod() + 1);
        _expectRejected(caller_, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCU-REENABLE-A01.
    function test_whenUnauthorizedClassesSeeded_reverts() public {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(0x111));
        uint256 checkpoint = vm.snapshotState();
        test_givenUnauthorized_whenReEnabled_reverts(address(0));
        _restore(checkpoint);
        test_givenUnauthorized_whenReEnabled_reverts(_controller);
        _restore(checkpoint);
        test_givenUnauthorized_whenReEnabled_reverts(address(0x111));
    }

    // Scenarios: BLCU-REENABLE-L01.
    function test_givenEnabled_whenReEnabled_reverts(
        address caller_,
        bool active_
    ) public givenPendingBuckets {
        _setState(_payout, active_, true);
        _expectRejected(caller_, abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    // Scenarios: BLCU-REENABLE-L02.
    function test_givenPolicyInactive_whenReEnabled_revertsThenRestored()
        public
        givenPendingBuckets
        givenDisabled
    {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _expectRejected(
            address(this),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            )
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _transition(address(this));
    }

    // Scenarios: BLCU-REENABLE-L03.
    function test_givenNeverInitialized_whenReEnabled_reverts(
        address caller_,
        bool active_
    ) public {
        BurnerLoansPayout fresh = new BurnerLoansPayout(_kernel, address(_core));
        if (active_) _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Fresh Payout stays disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh history remains unset");
    }

    // Scenarios: BLCU-REENABLE-N01.
    function test_whenWithinGrace(
        uint32 grace_,
        uint48 last_,
        uint48 now_
    ) public givenPendingBuckets {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 last = uint48(bound(last_, 1, type(uint48).max - grace));
        _payout.setGracePeriod(grace);
        vm.warp(last);
        _payout.disable("");
        vm.warp(bound(now_, last, uint256(last) + grace));
        _transition(address(this));
    }

    // Scenarios: BLCU-REENABLE-N01.
    function test_whenInclusiveBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenWithinGrace(1, 1, 1);
        _restore(checkpoint);
        test_whenWithinGrace(1, 1, 2);
        _restore(checkpoint);
        test_whenWithinGrace(type(uint32).max, 1, type(uint32).max);
        _restore(checkpoint);
        test_whenWithinGrace(
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max
        );
    }

    // Scenarios: BLCU-REENABLE-N02.
    function test_whenGraceExpired_reverts(
        uint32 grace_,
        uint48 last_,
        uint48 now_
    ) public givenPendingBuckets {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 last = uint48(bound(last_, 1, uint256(type(uint48).max) - grace - 1));
        _payout.setGracePeriod(grace);
        vm.warp(last);
        _payout.disable("");
        uint48 deadline = last + grace;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        // Grace precedes activation: own inactivity cannot mask expiry.
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _expectRejected(
            address(this),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "ADMIN retains ordinary enable after grace expires");
    }

    // Scenarios: BLCU-REENABLE-N02.
    function test_whenExpiredBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenGraceExpired_reverts(1, 1, 3);
        _restore(checkpoint);
        test_whenGraceExpired_reverts(type(uint32).max, 1, type(uint48).max);
    }

    // Scenarios: BLCU-REENABLE-N03.
    function test_whenDeadlineOverflows_reverts(
        uint32 grace_,
        uint48 last_
    ) public givenPendingBuckets {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 last = uint48(bound(last_, uint256(type(uint48).max) - grace + 1, type(uint48).max));
        _payout.setGracePeriod(grace);
        vm.warp(last);
        _payout.disable("");
        _expectRejected(
            address(this),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last) + grace
            )
        );
    }

    // Scenarios: BLCU-REENABLE-N03.
    function test_whenOverflowBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenDeadlineOverflows_reverts(
            type(uint32).max,
            type(uint48).max - type(uint32).max + 1
        );
        _restore(checkpoint);
        test_whenDeadlineOverflows_reverts(1, type(uint48).max);
    }

    // Scenarios: BLCU-REENABLE-L04.
    function test_givenReEnabled_whenPausedAgain_thenWindowRestarts()
        public
        givenPendingBuckets
        givenDisabled
    {
        vm.warp(uint256(_payout.lastTransitionAt()) + _payout.gracePeriod());
        _transition(address(this));
        vm.warp(vm.getBlockTimestamp() + 1);
        _payout.disable("");
        vm.warp(vm.getBlockTimestamp() + _payout.gracePeriod());
        _transition(address(this));
    }

    // Scenarios: BLCU-REENABLE-C05.
    function test_givenCoreBusyAndPolicyInactive_whenReEnabled_revertsThenRestored()
        public
        givenPendingBuckets
        givenDisabled
    {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        _expectRejected(
            address(this),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        vm.clearMockedCalls();
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _transition(address(this));
    }

    // Scenarios: BLCU-REENABLE-L01, BLCU-REENABLE-L03.
    function test_whenLifecycleStateSeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenReEnabled_reverts(address(0), true);
        _restore(checkpoint);
        test_givenEnabled_whenReEnabled_reverts(address(0), false);
        _restore(checkpoint);
        test_givenNeverInitialized_whenReEnabled_reverts(address(0), true);
        _restore(checkpoint);
        test_givenNeverInitialized_whenReEnabled_reverts(address(0), false);
    }

    function _configurationDigest() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _payout.gracePeriod(),
                    _payout.core(),
                    _payout.configOperator(),
                    _payout.revenueDistributor(),
                    _payout.sendFeesToDistributor(),
                    _payout.sendYieldToDistributor(),
                    _core.payout()
                )
            );
    }

    function _transition(address caller_) private {
        bytes32 ledger = _ledgerDigest();
        bytes32 configuration = _configurationDigest();
        vm.expectEmit(address(_payout));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payout));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.recordLogs();
        vm.prank(caller_);
        _payout.reEnable();
        assertEq(vm.getRecordedLogs().length, 2, "Exactly two lifecycle events");
        assertTrue(_payout.isEnabled(), "Re-enabled");
        assertEq(_payout.lastTransitionAt(), vm.getBlockTimestamp(), "Exact transition timestamp");
        assertEq(_ledgerDigest(), ledger, "Re-enable preserves custody, buckets and indexes");
        assertEq(
            _configurationDigest(),
            configuration,
            "Re-enable preserves routing, authority and grace"
        );
    }

    function _expectRejected(address caller_, bytes memory reason_) private {
        bytes32 ledger = _ledgerDigest();
        bytes32 configuration = _configurationDigest();
        bool enabled = _payout.isEnabled();
        uint48 last = _payout.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.reEnable();
        assertEq(vm.getRecordedLogs().length, 0, "Rejected transition emits no logs");
        assertEq(_payout.isEnabled(), enabled, "Rejected transition preserves flag");
        assertEq(_payout.lastTransitionAt(), last, "Rejected transition preserves history");
        assertEq(_ledgerDigest(), ledger, "Rejected transition preserves custody and indexes");
        assertEq(
            _configurationDigest(),
            configuration,
            "Rejected transition preserves configuration"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, calls-loop)
