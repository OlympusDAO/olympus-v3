// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskSetGasReserveTest is BurnerLoansYieldClaimerTaskTest {
    uint32 internal constant _MINIMUM_GAS_RESERVE = 100_000;

    // Scenarios: BLYC-GAS-RESERVE-A01.
    function test_whenUnauthorizedCallerSetsReserve_reverts(
        address caller_,
        uint32 gasLimit_,
        uint8 mode_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: BLYC-GAS-RESERVE-I01.
    function test_whenPermittedCallerSetsReserveBelowMinimum_reverts(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, 0, _MINIMUM_GAS_RESERVE - 1);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller_);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: BLYC-GAS-RESERVE-I01.
    function test_whenReserveReachesThreshold_reverts(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, claimer.minimumGasToAttempt(), type(uint32).max);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller_);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: BLYC-GAS-RESERVE-I01.
    function test_whenReserveBoundaryIsInvalid_reverts(address caller_, uint8 roleClass_) public {
        _grantClaimerAdmin(caller_, roleClass_);
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        _assertInvalidReserveBoundary(caller_, 0, reserveBefore);
        _assertInvalidReserveBoundary(caller_, 1, reserveBefore);
        _assertInvalidReserveBoundary(caller_, _MINIMUM_GAS_RESERVE - 1, reserveBefore);
        _assertInvalidReserveBoundary(caller_, threshold, reserveBefore);
        _assertInvalidReserveBoundary(caller_, threshold + 1, reserveBefore);
        _assertInvalidReserveBoundary(caller_, type(uint32).max, reserveBefore);
    }

    function _assertInvalidReserveBoundary(
        address caller_,
        uint32 invalid_,
        uint32 reserveBefore_
    ) internal {
        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller_);
        claimer.setGasReserve(invalid_);
        assertEq(claimer.gasReserve(), reserveBefore_, "invalid boundary preserves reserve");
    }

    // Scenarios: BLYC-GAS-RESERVE-A02, BLYC-GAS-RESERVE-A03, BLYC-GAS-RESERVE-A04, BLYC-GAS-RESERVE-P01.
    function test_whenPermittedCallerSetsValidReserve_updatesValue(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        threshold_ = _boundUint32(threshold_, _MINIMUM_GAS_RESERVE + 2, type(uint32).max);
        vm.prank(admin);
        claimer.setMinimumGasToAttempt(threshold_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, _MINIMUM_GAS_RESERVE + 1, threshold_ - 1);
        uint32 executionBefore = claimer.executionGasLimit();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.GasReserveSet(gasLimit_);
        vm.prank(caller_);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), gasLimit_, "reserve equals input");
        assertEq(claimer.minimumGasToAttempt(), threshold_, "threshold unchanged");
        assertEq(claimer.executionGasLimit(), executionBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-GAS-RESERVE-P01.
    function test_whenReserveBoundariesSet_updatesValue(address caller_, uint8 roleClass_) public {
        _grantClaimerAdmin(caller_, roleClass_);
        vm.prank(admin);
        claimer.setMinimumGasToAttempt(type(uint32).max);

        vm.prank(caller_);
        claimer.setGasReserve(_MINIMUM_GAS_RESERVE);
        assertEq(claimer.gasReserve(), _MINIMUM_GAS_RESERVE, "minimum reserve stored");

        vm.prank(caller_);
        claimer.setGasReserve(type(uint32).max - 1);
        assertEq(claimer.gasReserve(), type(uint32).max - 1, "maximum reserve stored");
    }

    // Scenarios: BLYC-GAS-RESERVE-P02.
    function test_whenPermittedCallerSetsCurrentReserve_isNoOp(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 current = claimer.gasReserve();

        vm.recordLogs();
        vm.prank(caller_);
        claimer.setGasReserve(current);

        assertEq(vm.getRecordedLogs().length, 0, "same reserve emits no event");
        assertEq(claimer.gasReserve(), current, "reserve unchanged");
    }

    // Scenarios: BLYC-GAS-RESERVE-P03.
    function test_givenInactivePolicy_whenSetting_reverts(
        address caller_,
        uint8 roleClass_,
        bool enabled_,
        uint32 value_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setClaimerLifecycle(false, enabled_);
        bytes32 settings = _settingsDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(caller_);
        claimer.setGasReserve(value_);
        assertEq(_settingsDigest(), settings, "Inactive setter preserves every field");
    }

    // Scenarios: BLYC-GAS-RESERVE-A02, BLYC-GAS-RESERVE-A03, BLYC-GAS-RESERVE-A04.
    function test_whenAuthorizedRoleAndLocalStateSeeds() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            for (uint8 mode; mode < 3; ++mode) {
                test_whenPermittedCallerSetsValidReserve_updatesValue(
                    address(0xBEEF),
                    roleClass,
                    mode,
                    true,
                    250_000,
                    249_999
                );
                vm.revertToState(snapshot);
            }
        }
    }

    // Scenarios: BLYC-GAS-RESERVE-P01.
    function test_givenHigherReserve_whenMinimumIsRestored(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        vm.prank(caller_);
        claimer.setGasReserve(100_001);
        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.GasReserveSet(100_000);
        vm.prank(caller_);
        claimer.setGasReserve(100_000);
        assertEq(claimer.gasReserve(), 100_000, "Changed lower endpoint is accepted");
    }
}
