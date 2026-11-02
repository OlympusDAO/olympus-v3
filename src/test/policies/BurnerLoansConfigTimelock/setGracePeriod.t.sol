// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockSetGracePeriodTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCTLGR-A01.
    function test_givenUnauthorizedCaller_whenPeriodOne_thenRoleError(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(1))),
            caller_,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCTLGR-A02.
    function test_givenUnauthorizedCaller_whenPeriodZero_thenRoleError(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(0))),
            caller_,
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCTLGR-L01.
    function test_givenDisabled_whenPeriodOne_thenStateError(address caller_) public {
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(1))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCTLGR-L02.
    function test_givenDisabled_whenPeriodZero_thenStateError(address caller_) public {
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(0))),
            caller_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCTLGR-I01.
    function test_givenAdmin_whenPeriodZero_reverts(address caller_) public {
        _admin(caller_);
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(0))),
            caller_,
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector)
        );
    }

    // Scenarios: BLCTLGR-L03.
    function test_givenOwnPolicyInactive_whenPeriodSet_reverts(address caller_) public {
        _admin(caller_);
        _setState(_timelock, false, true);
        _transitionReverts(
            abi.encodeCall(_timelock.setGracePeriod, (uint32(1))),
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCTLGR-N01.
    function test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent(
        address caller_,
        uint32 period_
    ) public {
        _admin(caller_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        uint48 last = _timelock.lastTransitionAt();
        bytes32 funds = _economicDigest();
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), period_, "Exact grace");
        assertEq(_timelock.lastTransitionAt(), last, "No lifecycle transition");
        assertEq(_economicDigest(), funds, "No economic changes");
    }

    // Scenarios: BLCTLGR-P01.
    function test_givenAdmin_whenSamePeriodSet_thenOneEvent(
        address caller_,
        uint32 period_
    ) public {
        _admin(caller_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _timelock.setGracePeriod(period_);
        uint48 last = _timelock.lastTransitionAt();
        bytes32 funds = _economicDigest();
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), period_, "Exact grace");
        assertEq(_timelock.lastTransitionAt(), last, "No lifecycle transition");
        assertEq(_economicDigest(), funds, "No economic changes");
    }

    // Scenarios: BLCTLGR-N01.
    function test_givenGraceN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent(address(0xabc1), uint32(1));
        _restore(checkpoint);
        test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent(address(0xabc1), uint32(7 days));
        _restore(checkpoint);
        test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent(address(0xabc1), type(uint32).max);
        _restore(checkpoint);
    }

    // Scenarios: BLCTLGR-P01.
    function test_givenGraceP01Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAdmin_whenSamePeriodSet_thenOneEvent(address(0xabc1), uint32(1));
        _restore(checkpoint);
        test_givenAdmin_whenSamePeriodSet_thenOneEvent(address(0xabc1), uint32(7 days));
        _restore(checkpoint);
        test_givenAdmin_whenSamePeriodSet_thenOneEvent(address(0xabc1), type(uint32).max);
        _restore(checkpoint);
    }

    // Scenarios: BLCTLGR-L04.
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
