// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Independent endpoint seeds.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";

contract BurnerLoansPayoutSetGracePeriodTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-GRACE-P01.
    function test_whenPeriodSet_thenExactStorageAndSameValueEvent(
        address caller_,
        uint32 period_,
        bool overlap_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (overlap_) _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint32 period = uint32(bound(period_, 1, type(uint32).max));
        bytes32 ledger = _ledgerDigest();
        bytes32 configuration = _configurationDigest();
        uint48 last = _payout.lastTransitionAt();
        vm.expectEmit(address(_payout));
        emit IGracePeriod.GracePeriodSet(period);
        vm.recordLogs();
        vm.prank(caller_);
        _payout.setGracePeriod(period);
        assertEq(vm.getRecordedLogs().length, 1, "One event for setter call");
        vm.expectEmit(address(_payout));
        emit IGracePeriod.GracePeriodSet(period);
        // Discard the test's own expected-event emission before recording the second call.
        vm.getRecordedLogs();
        vm.recordLogs();
        vm.prank(caller_);
        _payout.setGracePeriod(period);
        assertEq(vm.getRecordedLogs().length, 1, "One event for same-value setter call");
        assertEq(_payout.gracePeriod(), period, "Full-width grace getter agrees");
        assertEq(_payout.lastTransitionAt(), last, "Setter preserves history");
        assertTrue(_payout.isEnabled(), "Setter preserves enablement");
        assertEq(_ledgerDigest(), ledger, "Setter preserves custody and liabilities");
        assertEq(_configurationDigest(), configuration, "Setter preserves routes and authority");
    }

    // Scenarios: BLCU-GRACE-P01.
    function test_whenPeriodBoundarySeeds() public {
        assertEq(_payout.gracePeriod(), 7 days, "Existing LoanParameters default");
        uint256 checkpoint = vm.snapshotState();
        test_whenPeriodSet_thenExactStorageAndSameValueEvent(address(0x111), 1, false);
        _restore(checkpoint);
        test_whenPeriodSet_thenExactStorageAndSameValueEvent(
            address(0x112),
            type(uint32).max,
            true
        );
        _restore(checkpoint);
        test_whenPeriodSet_thenExactStorageAndSameValueEvent(address(0x113), 7 days, false);
    }

    // Scenarios: BLCU-GRACE-A01.
    function test_givenUnauthorized_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectRejected(
            caller_,
            period_,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCU-GRACE-A01.
    function test_whenUnauthorizedClassesSeeded_reverts() public {
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, address(0x111));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(0x112));
        uint256 checkpoint = vm.snapshotState();
        test_givenUnauthorized_whenPeriodSet_reverts(address(0), 0);
        _restore(checkpoint);
        test_givenUnauthorized_whenPeriodSet_reverts(address(0x111), 1);
        _restore(checkpoint);
        test_givenUnauthorized_whenPeriodSet_reverts(address(0x112), type(uint32).max);
        _restore(checkpoint);
        test_givenUnauthorized_whenPeriodSet_reverts(_controller, 1);
    }

    // Scenarios: BLCU-GRACE-N01.
    function test_whenPeriodZero_reverts() public givenPendingBuckets {
        _expectRejected(
            address(this),
            0,
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector)
        );
    }

    // Scenarios: BLCU-GRACE-L01.
    function test_givenDisabled_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingBuckets {
        _payout.disable("");
        _expectRejected(caller_, period_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCU-GRACE-L02.
    function test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts(
        address caller_,
        uint32 period_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, false, enabled_);
        vm.mockCallRevert(address(_roles), bytes(""), hex"deadbeef");
        _expectRejected(
            caller_,
            period_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            )
        );
    }

    // Scenarios: BLCU-GRACE-L03.
    function test_givenPolicyReactivated_givenReEnabled_whenPeriodSet() public givenPendingBuckets {
        _payout.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.reEnable();
        uint48 last = _payout.lastTransitionAt();
        _payout.setGracePeriod(type(uint32).max);
        assertEq(_payout.lastTransitionAt(), last, "Changing grace is not a transition");
        _payout.disable("");
        vm.warp(uint256(_payout.lastTransitionAt()) + type(uint32).max);
        _payout.reEnable();
        assertTrue(_payout.isEnabled(), "New period governs future disable");
    }

    // Scenarios: BLCU-GRACE-L01, BLCU-GRACE-L02.
    function test_whenLifecycleStateSeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDisabled_whenPeriodSet_reverts(address(0), 0);
        _restore(checkpoint);
        test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts(address(0), 0, true);
        _restore(checkpoint);
        test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts(
            address(0),
            type(uint32).max,
            false
        );
    }

    function _configurationDigest() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _payout.configOperator(),
                    _payout.revenueDistributor(),
                    _payout.sendFeesToDistributor(),
                    _payout.sendYieldToDistributor(),
                    _core.payout()
                )
            );
    }

    function _expectRejected(address caller_, uint32 period_, bytes memory reason_) private {
        uint32 grace = _payout.gracePeriod();
        uint48 last = _payout.lastTransitionAt();
        bool enabled = _payout.isEnabled();
        bytes32 ledger = _ledgerDigest();
        bytes32 configuration = _configurationDigest();
        vm.recordLogs();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.setGracePeriod(period_);
        assertEq(vm.getRecordedLogs().length, 0, "Rejected setter emits no logs");
        assertEq(_payout.gracePeriod(), grace, "Rejected setter preserves grace");
        assertEq(_payout.lastTransitionAt(), last, "Rejected setter preserves history");
        assertEq(_payout.isEnabled(), enabled, "Rejected setter preserves flag");
        assertEq(_ledgerDigest(), ledger, "Rejected setter preserves custody and liabilities");
        assertEq(_configurationDigest(), configuration, "Rejected setter preserves configuration");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
