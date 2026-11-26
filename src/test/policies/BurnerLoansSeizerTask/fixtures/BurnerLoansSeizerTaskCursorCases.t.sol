// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "../BurnerLoansSeizerTaskTest.sol";

// Shared mechanics run independently in each action's concrete test contract.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
abstract contract BurnerLoansSeizerTaskCursorCases is BurnerLoansSeizerTaskTest {
    error CursorReadFailed();

    function _isExpired() internal pure virtual returns (bool);

    function setUp() public virtual override {
        super.setUp();
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_otherAsset));
        _mockCount(3);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P01, BLSEIZ-UNHEALTHY-CURSOR-P01.
    function test_givenPermittedCaller_whenNonzeroCursorSet(
        address caller_,
        uint8 role_,
        uint8 state_,
        uint256 population_,
        uint256 index_
    ) public {
        _assertNonzero(caller_, role_, state_, population_, index_);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P02, BLSEIZ-UNHEALTHY-CURSOR-P02.
    function test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads(
        address caller_,
        uint8 role_,
        uint8 state_
    ) public {
        role_ = uint8(bound(role_, 0, 2));
        state_ = uint8(bound(state_, 0, 2));
        _grantTaskAdmin(caller_, role_);
        _setBothBorrowerCursors(address(_asset), 1);
        _lifecycle(state_);
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_lens),
            _validation(0),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.AssetCursorSet(address(_asset), 0, _selection());
        _setCursor(caller_, address(_asset), 0);
        assertEq(_cursor(address(_asset)), 0, "Selected cursor resets without economic reads");
        assertEq(_otherCursor(address(_asset)), 1, "Unselected lane retains its nonzero offset");
        assertEq(_task.isEnabled(), state_ != 1, "Recovery preserves local lifecycle");
        _assertOtherState();
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P01, BLSEIZ-UNHEALTHY-CURSOR-P01.
    function test_whenNonzeroCursorRoleLifecycleAndNumericBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role)
            for (uint8 state; state < 3; ++state) {
                assertTrue(vm.revertToState(checkpoint), "Restore minimum cursor boundary");
                vm.clearMockedCalls();
                _assertNonzero(_DAVE, role, state, 2, 1);
                assertTrue(vm.revertToState(checkpoint), "Restore maximum cursor boundary");
                vm.clearMockedCalls();
                _assertNonzero(_DAVE, role, state, type(uint256).max, type(uint256).max - 1);
            }
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P02, BLSEIZ-UNHEALTHY-CURSOR-P02.
    function test_whenCursorResetRoleAndLifecycleBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role)
            for (uint8 state; state < 3; ++state) {
                assertTrue(vm.revertToState(checkpoint), "Restore reset boundary");
                vm.clearMockedCalls();
                test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads(_DAVE, role, state);
            }
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P07, BLSEIZ-UNHEALTHY-CURSOR-P07.
    function test_whenZeroUnchangedRoleAndLifecycleBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role)
            for (uint8 state; state < 3; ++state) {
                assertTrue(vm.revertToState(checkpoint), "Restore zero no-op boundary");
                vm.clearMockedCalls();
                test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads(
                    _DAVE,
                    role,
                    state
                );
            }
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P02, BLSEIZ-UNHEALTHY-CURSOR-P02.
    function test_givenUnequalCursors_whenZeroSelected_thenNoDownstreamReads() public {
        _mockCount(10);
        vm.prank(_seizerAdmin);
        _task.setExpiredAssetCursor(address(_asset), 2);
        vm.prank(_seizerAdmin);
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Independent expiry setup offset");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Independent unhealthy setup offset"
        );
        uint256 otherBefore = _otherCursor(address(_asset));
        vm.expectCall(address(_lens), bytes(""), uint64(0));
        _setCursor(_seizerAdmin, address(_asset), 0);
        assertEq(_cursor(address(_asset)), 0, "Zero resets the selected traversal");
        assertEq(_otherCursor(address(_asset)), otherBefore, "Zero preserves the other traversal");
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P10, BLSEIZ-UNHEALTHY-CURSOR-P10.
    function test_givenUnequalCursors_whenSelectedLaneUnchanged_thenEventFreeNoOp() public {
        _mockCount(10);
        vm.prank(_seizerAdmin);
        _task.setExpiredAssetCursor(address(_asset), 2);
        vm.prank(_seizerAdmin);
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Independent expiry setup offset");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Independent unhealthy setup offset"
        );
        uint256 selected = _cursor(address(_asset));
        vm.recordLogs();
        _setCursor(_seizerAdmin, address(_asset), selected);
        assertEq(vm.getRecordedLogs().length, 0, "Equality checks only the selected lane");
        assertEq(_task.expiredAssetCursor(address(_asset)), 2, "Expiry offset remains exact");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            8,
            "Unhealthy offset remains independently exact"
        );
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-A01, BLSEIZ-UNHEALTHY-CURSOR-A01.
    function test_whenCallerHasNeitherRole_reverts(
        address caller_,
        address asset_,
        uint256 index_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        _setCursor(caller_, asset_, index_);
        _assertInitialCursors();
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I01, BLSEIZ-UNHEALTHY-CURSOR-I01.
    function test_whenAssetUnmanaged_reverts(address asset_, uint256 index_) public {
        vm.assume(!_task.isAssetManaged(asset_));
        _assertUnmanaged(asset_, index_);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I01, BLSEIZ-UNHEALTHY-CURSOR-I01.
    function test_whenUnmanagedAddressBoundariesSeeded_reverts() public {
        _assertUnmanaged(address(0), 0);
        _assertUnmanaged(address(0), type(uint256).max);
        _assertUnmanaged(address(type(uint160).max), 1);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I02, BLSEIZ-UNHEALTHY-CURSOR-I02.
    function test_whenCursorOutsidePopulation_reverts(uint256 population_, uint256 index_) public {
        index_ = bound(index_, population_ == 0 ? 1 : population_, type(uint256).max);
        _assertInvalid(population_, index_);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I02, BLSEIZ-UNHEALTHY-CURSOR-I02.
    function test_whenInvalidNumericBoundariesSeeded_reverts() public {
        _assertInvalid(0, 1);
        _assertInvalid(0, type(uint256).max);
        _assertInvalid(1, 1);
        _assertInvalid(3, 3);
        _assertInvalid(type(uint256).max, type(uint256).max);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P03, BLSEIZ-UNHEALTHY-CURSOR-P03.
    function test_whenCursorUnchanged_thenValidateAndNoEvent() public {
        _setCursor(_seizerAdmin, address(_asset), 1);
        vm.expectCall(address(_lens), _validation(1), uint64(1));
        vm.recordLogs();
        _setCursor(_seizerAdmin, address(_asset), 1);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged selected cursor emits no event");
        assertEq(_cursor(address(_asset)), 1, "Selected offset stays exact");
        assertEq(_otherCursor(address(_asset)), 0, "Other lane stays independent");
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I03, BLSEIZ-UNHEALTHY-CURSOR-I03.
    function test_givenSavedCursorStale_whenSameValueSelected_reverts() public {
        _setCursor(_seizerAdmin, address(_asset), 1);
        _mockCount(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                uint256(1),
                uint256(1)
            )
        );
        _setCursor(_seizerAdmin, address(_asset), 1);
        assertEq(_cursor(address(_asset)), 1, "Bounds validation precedes equality");
        assertEq(_otherCursor(address(_asset)), 0, "Failed validation preserves the other lane");
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I04, BLSEIZ-UNHEALTHY-CURSOR-I04.
    function test_givenLensReadFailure_whenNonzeroCursorSelected_reverts() public {
        vm.mockCallRevert(
            address(_lens),
            _validation(1),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.expectRevert(CursorReadFailed.selector);
        _setCursor(_seizerAdmin, address(_asset), 1);
        _assertInitialCursors();
        _assertOtherState();
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-L01, BLSEIZ-UNHEALTHY-CURSOR-L01.
    function test_givenInactiveTask_whenCursorSelected_reverts(bool disabled_, bool zero_) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _setCursor(_seizerAdmin, address(_asset), zero_ ? 0 : 1);
        _assertInitialCursors();
        _setPolicyActive(address(_task), true);
        _setCursor(_seizerAdmin, address(_asset), 1);
        assertEq(_cursor(address(_asset)), 1, "Selected recovery works after reactivation");
        assertEq(_otherCursor(address(_asset)), 0, "Reactivation does not select the other lane");
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-P07, BLSEIZ-UNHEALTHY-CURSOR-P07.
    function test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads(
        address caller_,
        uint8 role_,
        uint8 state_
    ) public {
        role_ = uint8(bound(role_, 0, 2));
        state_ = uint8(bound(state_, 0, 2));
        _grantTaskAdmin(caller_, role_);
        _lifecycle(state_);
        vm.mockCallRevert(
            address(_lens),
            _validation(0),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.recordLogs();
        _setCursor(caller_, address(_asset), 0);
        assertEq(vm.getRecordedLogs().length, 0, "Zero equality requires no Lens read or event");
        _assertInitialCursors();
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-L02, BLSEIZ-UNHEALTHY-CURSOR-L02.
    function test_givenInactiveTask_givenRolesBroken_whenUnauthorized_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _setTaskEnabled(enabled_);
        _setPolicyActive(address(_task), false);
        vm.mockCallRevert(
            address(_roles),
            abi.encodeWithSelector(_roles.hasRole.selector),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _setCursor(caller_, address(0), type(uint256).max);
        _assertInitialCursors();
    }

    function _assertNonzero(
        address caller_,
        uint8 role_,
        uint8 state_,
        uint256 population_,
        uint256 index_
    ) private {
        role_ = uint8(bound(role_, 0, 2));
        state_ = uint8(bound(state_, 0, 2));
        population_ = bound(population_, 2, type(uint256).max);
        index_ = bound(index_, 1, population_ - 1);
        _grantTaskAdmin(caller_, role_);
        _mockCount(population_);
        _setOtherCursor(address(_asset), 1);
        _lifecycle(state_);
        uint48 transition = _task.lastTransitionAt();
        vm.expectCall(address(_lens), _validation(index_));
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.AssetCursorSet(address(_asset), index_, _selection());
        _setCursor(caller_, address(_asset), index_);
        assertEq(
            _cursor(address(_asset)),
            index_,
            "Exact requested offset stored in selected lane"
        );
        assertEq(_otherCursor(address(_asset)), 1, "Other lane preserves its nonzero progress");
        assertEq(_task.lastTransitionAt(), transition, "Recovery preserves transition timestamp");
        assertEq(_task.isEnabled(), state_ != 1, "Recovery preserves lifecycle");
        _assertOtherState();
    }

    function _assertUnmanaged(address asset_, uint256 index_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_AssetNotManaged.selector,
                asset_
            )
        );
        _setCursor(_seizerAdmin, asset_, index_);
        assertEq(_cursor(asset_), 0, "Unmanaged selected cursor is not created");
        assertEq(_otherCursor(asset_), 0, "Unmanaged other cursor is not created");
    }

    function _assertInvalid(uint256 population_, uint256 index_) private {
        _mockCount(population_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                index_,
                population_
            )
        );
        _setCursor(_seizerAdmin, address(_asset), index_);
        _assertInitialCursors();
    }

    function _validation(uint256 index_) private view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(_task), address(_asset), index_, uint256(0), uint256(0))
            );
    }

    function _selection() private pure returns (IBurnerLoansLens.Selection) {
        return
            _isExpired()
                ? IBurnerLoansLens.Selection.Expired
                : IBurnerLoansLens.Selection.Unhealthy;
    }

    function _setCursor(address caller_, address asset_, uint256 index_) internal {
        vm.prank(caller_);
        if (_isExpired()) {
            _task.setExpiredAssetCursor(asset_, index_);
        } else {
            _task.setUnhealthyAssetCursor(asset_, index_);
        }
    }

    function _setOtherCursor(address asset_, uint256 index_) private {
        if (_isExpired()) {
            vm.prank(_seizerAdmin);
            _task.setUnhealthyAssetCursor(asset_, index_);
        } else {
            vm.prank(_seizerAdmin);
            _task.setExpiredAssetCursor(asset_, index_);
        }
    }

    function _cursor(address asset_) private view returns (uint256) {
        return _isExpired() ? _task.expiredAssetCursor(asset_) : _task.unhealthyAssetCursor(asset_);
    }

    function _otherCursor(address asset_) private view returns (uint256) {
        return _isExpired() ? _task.unhealthyAssetCursor(asset_) : _task.expiredAssetCursor(asset_);
    }

    function _assertInitialCursors() private view {
        assertEq(_task.expiredAssetCursor(address(_asset)), 0, "Expiry cursor unchanged at zero");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Unhealthy cursor unchanged at zero"
        );
    }

    function _lifecycle(uint8 state_) private {
        if (state_ != 0) {
            vm.prank(_seizerAdmin);
            _task.disable("");
        }
        if (state_ == 2) {
            vm.prank(_seizerAdmin);
            _task.reEnable();
        }
    }

    function _assertOtherState() private view {
        assertEq(
            _task.expiredAssetCursor(address(_otherAsset)),
            0,
            "Other asset expiry offset unchanged"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_otherAsset)),
            0,
            "Other asset unhealthy offset unchanged"
        );
        assertEq(_task.nextAssetIndex(), 0, "Asset traversal unchanged");
        assertEq(
            _task.getAssets(),
            _two(address(_asset), address(_otherAsset)),
            "Managed registry unchanged"
        );
        assertEq(_task.maxBorrowersToCheck(), 500, "Scan limit unchanged");
        assertEq(_task.maxBorrowersToSeize(), 25, "Seizure limit unchanged");
        assertEq(_task.executionGasLimit(), 10_000_000, "Gas budget unchanged");
        assertEq(_asset.balanceOf(address(_task)), 0, "Task custody unchanged");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
