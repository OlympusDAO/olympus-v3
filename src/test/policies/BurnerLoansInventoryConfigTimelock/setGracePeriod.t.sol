// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansInventoryConfigTimelockSetGracePeriodTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-GRACE-A01, BLINCT-GRACE-N01, BLINCT-GRACE-P01.
    function test_whenPeriodSet_thenExactStorageAndRepeatedEvent(
        uint32 period_,
        address caller_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        period_ = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        bytes32 state = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), period_, "Full-width period stored");
        assertEq(_timelock.lastTransitionAt(), last, "Setter is not a lifecycle transition");
        assertTrue(_timelock.isEnabled(), "Setter leaves enabled state intact");
        assertEq(_queueDigest(_pendingId), state, "Setter preserves queued recovery");
    }

    // Scenarios: BLINCT-GRACE-A02.
    function test_whenUnauthorizedSetter_reverts(
        address caller_,
        bool zero_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _expectGraceRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_,
            zero_ ? 0 : 1
        );
    }

    // Scenarios: BLINCT-GRACE-L01.
    function test_givenActiveDisabledTimelock_whenGraceSet_reverts(
        address caller_
    ) public givenPendingRecovery {
        _setState(_timelock, true, false);
        _expectGraceRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, 1);
    }

    // Scenarios: BLINCT-GRACE-L03.
    function test_givenInactiveDisabledTimelock_whenGraceSet_reverts(
        address caller_
    ) public givenPendingRecovery {
        _setState(_timelock, false, false);
        _expectGraceRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            caller_,
            1
        );
    }

    // Scenarios: BLINCT-GRACE-L02.
    function test_givenInactiveTimelock_whenGraceSet_reverts() public givenPendingRecovery {
        _setState(_timelock, false, true);
        _expectGraceRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            address(this),
            1
        );
    }

    // Scenarios: BLINCT-GRACE-I01.
    function test_whenPeriodZero_reverts() public givenPendingRecovery {
        _expectGraceRejected(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector),
            address(this),
            0
        );
    }

    function _expectGraceRejected(bytes memory reason_, address caller_, uint32 period_) internal {
        bytes32 state = _queueDigest(_pendingId);
        uint32 beforePeriod = _timelock.gracePeriod();
        uint48 last = _timelock.lastTransitionAt();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), beforePeriod, "Failed setter preserves period");
        assertEq(_timelock.lastTransitionAt(), last, "Failed setter preserves history");
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Failed setter preserves pending recovery and balances"
        );
    }

    // Scenarios: BLINCT-GRACE-A01, BLINCT-GRACE-N01, BLINCT-GRACE-P01.
    function test_whenPeriodAtTypeBounds_thenExactStorageAndEvents() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenPeriodSet_thenExactStorageAndRepeatedEvent(1, address(0xabc1));
        _restore(checkpoint);
        test_whenPeriodSet_thenExactStorageAndRepeatedEvent(type(uint32).max, address(0xabc1));
    }

    // Scenarios: BLINCT-GRACE-A02.
    function test_givenBurnerLoansAdminOnly_whenPeriodSet_reverts() public {
        test_whenUnauthorizedSetter_reverts(_recipient, false);
    }

    // Scenarios: BLINCT-GRACE-L04.
    function test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts(
        address caller_,
        bool enabled_,
        uint32 period_
    ) public {
        _setState(_timelock, false, enabled_);
        vm.etch(address(_timelock.ROLES()), hex"fe");
        uint32 beforePeriod = _timelock.gracePeriod();
        uint48 beforeAt = _timelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), beforePeriod, "Rejected setter preserves period");
        assertEq(_timelock.lastTransitionAt(), beforeAt, "Rejected setter preserves history");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected setter commits no logs");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth)
