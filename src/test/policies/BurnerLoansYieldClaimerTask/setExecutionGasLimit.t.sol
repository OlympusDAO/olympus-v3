// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskSetExecutionGasLimitTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-EXECUTION-GAS-A01.
    function test_givenUnauthorizedCaller_reverts(
        address caller_,
        uint32 gasLimit_,
        uint8 mode_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 limitBefore = claimer.executionGasLimit();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setExecutionGasLimit(gasLimit_);

        assertEq(claimer.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-EXECUTION-GAS-I01.
    function test_givenZeroLimit_reverts(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 limitBefore = claimer.executionGasLimit();

        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        vm.prank(caller_);
        claimer.setExecutionGasLimit(0);

        assertEq(claimer.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-EXECUTION-GAS-A02, BLYC-EXECUTION-GAS-A03, BLYC-EXECUTION-GAS-A04, BLYC-EXECUTION-GAS-P01.
    function test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration(
        uint32 gasLimit_,
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        uint32 currentLimit = claimer.executionGasLimit();
        vm.assume(gasLimit_ != currentLimit);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        uint32 gracePeriodBefore = claimer.gracePeriod();
        uint256 cursorBefore = claimer.nextAssetIndex();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionGasLimitSet(gasLimit_);
        vm.prank(caller_);
        claimer.setExecutionGasLimit(gasLimit_);

        assertEq(claimer.executionGasLimit(), gasLimit_, "execution limit equals input");
        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.gracePeriod(), gracePeriodBefore, "grace period unchanged");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "cursor unchanged");
    }

    // Scenarios: BLYC-EXECUTION-GAS-A02, BLYC-EXECUTION-GAS-A03, BLYC-EXECUTION-GAS-A04, BLYC-EXECUTION-GAS-P01.
    function test_whenExecutionGasLimitBoundaryUsed_storesExactLimit(
        bool maximum_,
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        uint32 gasLimit = maximum_ ? type(uint32).max : 1;
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionGasLimitSet(gasLimit);
        vm.prank(caller_);
        claimer.setExecutionGasLimit(gasLimit);

        assertEq(claimer.executionGasLimit(), gasLimit, "boundary execution limit stored");
    }

    // Scenarios: BLYC-EXECUTION-GAS-P02.
    function test_whenPermittedCallerSetsCurrentLimit_isNoOp(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        uint32 currentLimit = claimer.executionGasLimit();
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        uint32 gracePeriodBefore = claimer.gracePeriod();
        uint256 cursorBefore = claimer.nextAssetIndex();

        vm.recordLogs();
        vm.prank(caller_);
        claimer.setExecutionGasLimit(currentLimit);

        assertEq(vm.getRecordedLogs().length, 0, "same limit emits no event");
        assertEq(claimer.executionGasLimit(), currentLimit, "execution limit unchanged");
        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.gracePeriod(), gracePeriodBefore, "grace period unchanged");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "cursor unchanged");
    }

    // Scenarios: BLYC-EXECUTION-GAS-P03.
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
        claimer.setExecutionGasLimit(value_);
        assertEq(_settingsDigest(), settings, "Inactive setter preserves every field");
    }

    // Scenarios: BLYC-EXECUTION-GAS-A02, BLYC-EXECUTION-GAS-A03, BLYC-EXECUTION-GAS-A04.
    function test_whenAuthorizedRoleAndLocalStateSeeds() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            for (uint8 mode; mode < 3; ++mode) {
                test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration(
                    1,
                    address(0xBEEF),
                    roleClass,
                    mode,
                    true
                );
                vm.revertToState(snapshot);
            }
        }
    }
}
