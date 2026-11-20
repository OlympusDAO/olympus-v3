// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutConfigTimelockSetGracePeriodTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-GRACE-L01, BLCUCT-GRACE-N02.
    function test_whenPeriodSet_thenExactStorageAndSameValueEvent(
        address caller_,
        uint32 period_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        bytes32 queue = _queueDigest(_pendingId);
        uint48 last = _payoutTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectEmit(address(_payoutTimelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _payoutTimelock.setGracePeriod(period_);
        vm.expectEmit(address(_payoutTimelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _payoutTimelock.setGracePeriod(period_);
        assertEq(
            _timelockLogCount(),
            2,
            "One exact event for each setter call including same value"
        );
        assertEq(_payoutTimelock.gracePeriod(), period_, "Full-width period");
        assertEq(_payoutTimelock.lastTransitionAt(), last, "No transition");
        assertTrue(_payoutTimelock.isEnabled(), "Enabled unchanged");
        assertEq(_queueDigest(_pendingId), queue, "Queue unchanged");
    }

    // Scenarios: BLCUCT-GRACE-A01.
    function test_givenUnauthorizedCaller_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.setGracePeriod, (period_)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_
        );
    }

    // Scenarios: BLCUCT-GRACE-N01.
    function test_whenPeriodZero_reverts(address caller_) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-GRACE-L02.
    function test_givenActiveDisabled_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, true, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.setGracePeriod, (period_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-GRACE-L04.
    function test_givenInactiveDisabled_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, false, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.setGracePeriod, (period_)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-GRACE-L03.
    function test_givenInactiveEnabled_whenPeriodSet_reverts(
        address caller_,
        uint32 period_
    ) public givenPendingRecovery {
        _grantProposer(caller_, false, false);
        _setState(_payoutTimelock, false, true);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.setGracePeriod, (period_)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-GRACE-L01, BLCUCT-GRACE-L03, BLCUCT-GRACE-N02.
    function test_whenPeriodBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenPeriodSet_thenExactStorageAndSameValueEvent(address(0x111), 1);
        _restore(checkpoint);
        test_whenPeriodSet_thenExactStorageAndSameValueEvent(address(0x112), type(uint32).max);
        _restore(checkpoint);
        test_givenInactiveEnabled_whenPeriodSet_reverts(address(0x111), 0);
        _restore(checkpoint);
        test_givenInactiveEnabled_whenPeriodSet_reverts(address(0x112), type(uint32).max);
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-GRACE-L05.
    function test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts(
        address caller_,
        bool enabled_,
        uint32 period_
    ) public {
        _setState(_payoutTimelock, false, enabled_);
        vm.etch(address(_payoutTimelock.ROLES()), hex"fe");
        uint32 beforePeriod = _payoutTimelock.gracePeriod();
        uint48 beforeAt = _payoutTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            )
        );
        vm.prank(caller_);
        _payoutTimelock.setGracePeriod(period_);
        assertEq(_payoutTimelock.gracePeriod(), beforePeriod, "Rejected setter preserves period");
        assertEq(_payoutTimelock.lastTransitionAt(), beforeAt, "Rejected setter preserves history");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected setter commits no logs");
    }
}
