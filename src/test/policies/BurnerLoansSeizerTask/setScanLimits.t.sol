// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

// Bounds prove all narrowing fits the public uint16/uint8 input types.
// forge-lint: disable-start(unsafe-typecast,literal-instead-of-constant)
contract BurnerLoansSeizerTaskSetScanLimitsTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-SCAN-LIMITS-A02, BLSEIZ-SCAN-LIMITS-A03, BLSEIZ-SCAN-LIMITS-A04, BLSEIZ-SCAN-LIMITS-P01, BLSEIZ-SCAN-LIMITS-N03, BLSEIZ-SCAN-LIMITS-N05.
    function test_givenPermittedCaller_whenLimitsSet(
        address caller_,
        uint8 roleClass_,
        uint16 checks_,
        uint8 seize_,
        bool disabled_
    ) public {
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        _grantTaskAdmin(caller_, roleClass_);
        checks_ = uint16(bound(checks_, 1, type(uint16).max));
        seize_ = uint8(bound(seize_, 1, checks_ < type(uint8).max ? checks_ : type(uint8).max));
        vm.assume(checks_ != _task.maxBorrowersToCheck() || seize_ != _task.maxBorrowersToSeize());
        _setTaskEnabled(!disabled_);
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanLimitsSet(checks_, seize_);
        vm.prank(caller_);
        _task.setScanLimits(checks_, seize_);
        assertEq(_task.maxBorrowersToCheck(), checks_, "Exact scan limit stored");
        assertEq(_task.maxBorrowersToSeize(), seize_, "Exact seizure limit stored");
        assertEq(_task.isEnabled(), !disabled_, "Configuration preserves local lifecycle");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-A02, BLSEIZ-SCAN-LIMITS-A03, BLSEIZ-SCAN-LIMITS-A04, BLSEIZ-SCAN-LIMITS-N03, BLSEIZ-SCAN-LIMITS-N05.
    function test_whenRolesAndFullWidthBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            assertTrue(vm.revertToState(checkpoint), "Restore caller role partition");
            test_givenPermittedCaller_whenLimitsSet(
                _ALICE,
                roleClass,
                type(uint16).max,
                type(uint8).max,
                false
            );
            assertTrue(vm.revertToState(checkpoint), "Restore lower endpoint fixture");
            test_givenPermittedCaller_whenLimitsSet(_ALICE, roleClass, 1, 1, true);
            assertTrue(vm.revertToState(checkpoint), "Restore old ceiling fixture");
            test_givenPermittedCaller_whenLimitsSet(_ALICE, roleClass, 501, 51, false);
        }
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-A01.
    function test_whenCallerHasNeitherRole_whenScanLimitsSet_reverts(
        address caller_,
        uint16 checks_,
        uint8 seize_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _task.setScanLimits(checks_, seize_);
        assertEq(_task.maxBorrowersToCheck(), 500, "Unauthorized call preserves scan limit");
        assertEq(_task.maxBorrowersToSeize(), 25, "Unauthorized call preserves batch limit");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-N02.
    function test_whenCheckLimitZero_reverts(uint8 seize_) public {
        seize_ = uint8(bound(seize_, 1, type(uint8).max));
        _expectInvalid(0, seize_);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-N04.
    function test_whenSeizureLimitZero_reverts(uint16 checks_) public {
        checks_ = uint16(bound(checks_, 1, type(uint16).max));
        _expectInvalid(checks_, 0);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-N06.
    function test_whenSeizureLimitExceedsCheckLimit_reverts(uint16 checks_, uint8 seize_) public {
        checks_ = uint16(bound(checks_, 1, type(uint8).max - 1));
        seize_ = uint8(bound(seize_, checks_ + 1, type(uint8).max));
        _expectInvalid(checks_, seize_);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-N02, BLSEIZ-SCAN-LIMITS-N04, BLSEIZ-SCAN-LIMITS-N06.
    function test_whenInvalidBoundariesSeeded_reverts() public {
        _expectInvalid(0, 0);
        _expectInvalid(0, type(uint8).max);
        _expectInvalid(1, 0);
        _expectInvalid(type(uint16).max, 0);
        _expectInvalid(1, type(uint8).max);
        _expectInvalid(type(uint8).max - 1, type(uint8).max);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-P03.
    function test_whenLimitsUnchanged_thenNoEvent() public {
        vm.recordLogs();
        _task.setScanLimits(_task.maxBorrowersToCheck(), _task.maxBorrowersToSeize());
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged limits are an event-free no-op");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-P02.
    function test_givenInactiveTask_whenLimitsSet_reverts(bool disabled_) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.setScanLimits(1, 1);
    }

    function _expectInvalid(uint16 checks_, uint8 seize_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidScanLimits.selector,
                checks_,
                seize_
            )
        );
        _task.setScanLimits(checks_, seize_);
        assertEq(_task.maxBorrowersToCheck(), 500, "Invalid input preserves scan limit");
        assertEq(_task.maxBorrowersToSeize(), 25, "Invalid input preserves batch limit");
    }
}
// forge-lint: disable-end(unsafe-typecast,literal-instead-of-constant)
