// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskSetMinimumGasToAttemptTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-MINIMUM-GAS-A01.
    function test_whenUnauthorizedCallerSetsMinimumGas_reverts(
        address caller_,
        uint32 gasLimit_,
        uint8 mode_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 thresholdBefore = claimer.minimumGasToAttempt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: BLYC-MINIMUM-GAS-I01.
    function test_whenMinimumGasDoesNotExceedReserve_reverts(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, 0, claimer.gasReserve());
        uint32 thresholdBefore = claimer.minimumGasToAttempt();

        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: BLYC-MINIMUM-GAS-I01.
    function test_whenMinimumGasBoundaryIsInvalid_reverts(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        uint32 reserve = claimer.gasReserve();
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        _assertInvalidMinimumGasBoundary(caller_, 0, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller_, 1, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller_, reserve - 1, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller_, reserve, thresholdBefore);
    }

    function _assertInvalidMinimumGasBoundary(
        address caller_,
        uint32 invalid_,
        uint32 thresholdBefore_
    ) internal {
        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(invalid_);
        assertEq(
            claimer.minimumGasToAttempt(),
            thresholdBefore_,
            "invalid boundary preserves threshold"
        );
    }

    // Scenarios: BLYC-MINIMUM-GAS-A02, BLYC-MINIMUM-GAS-A03, BLYC-MINIMUM-GAS-A04, BLYC-MINIMUM-GAS-P01.
    function test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, claimer.gasReserve() + 1, type(uint32).max);
        uint32 current = claimer.minimumGasToAttempt();
        vm.assume(gasLimit_ != current);
        uint32 reserveBefore = claimer.gasReserve();
        uint32 executionBefore = claimer.executionGasLimit();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.MinimumGasToAttemptSet(gasLimit_);
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), gasLimit_, "threshold equals input");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.executionGasLimit(), executionBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-MINIMUM-GAS-P01.
    function test_whenMinimumGasBoundariesSet_updatesValue(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        uint32 minimum = claimer.gasReserve() + 1;

        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(minimum);
        assertEq(claimer.minimumGasToAttempt(), minimum, "minimum threshold stored");

        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(type(uint32).max);
        assertEq(claimer.minimumGasToAttempt(), type(uint32).max, "maximum threshold stored");
    }

    // Scenarios: BLYC-MINIMUM-GAS-P02.
    function test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 current = claimer.minimumGasToAttempt();

        vm.recordLogs();
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(current);

        assertEq(vm.getRecordedLogs().length, 0, "same threshold emits no event");
        assertEq(claimer.minimumGasToAttempt(), current, "threshold unchanged");
    }

    // Scenarios: BLYC-MINIMUM-GAS-P03.
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
        claimer.setMinimumGasToAttempt(value_);
        assertEq(_settingsDigest(), settings, "Inactive setter preserves every field");
    }

    // Scenarios: BLYC-MINIMUM-GAS-A02, BLYC-MINIMUM-GAS-A03, BLYC-MINIMUM-GAS-A04.
    function test_whenAuthorizedRoleAndLocalStateSeeds() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            for (uint8 mode; mode < 3; ++mode) {
                test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
                    address(0xBEEF),
                    roleClass,
                    mode,
                    true,
                    100_001
                );
                vm.revertToState(snapshot);
            }
        }
    }
}
