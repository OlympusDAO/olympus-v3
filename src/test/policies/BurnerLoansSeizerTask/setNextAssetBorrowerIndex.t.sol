// SPDX-License-Identifier: AGPL-3.0
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
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

// Fixed role/state partitions and loan quantities seed the recovery boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskSetNextAssetBorrowerIndexTest is BurnerLoansSeizerTaskTest {
    error CursorReadFailed();

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
        _mockCount(3);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P01.
    function test_givenPermittedCaller_whenNonzeroBorrowerCursorSet(
        address caller_,
        uint8 roleClass_,
        uint8 state_,
        uint256 population_,
        uint256 index_
    ) public {
        _assertPermittedNonzeroCursorSet(caller_, roleClass_, state_, population_, index_);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P02.
    function test_givenPermittedCaller_whenBorrowerCursorReset_thenNoDownstreamReads(
        address caller_,
        uint8 roleClass_,
        uint8 state_
    ) public {
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        state_ = uint8(bound(state_, 0, 2));
        _grantTaskAdmin(caller_, roleClass_);
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        if (state_ != 0) _task.disable("");
        if (state_ == 2) _task.reEnable();
        uint48 transition = _task.lastTransitionAt();
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
        emit IBurnerLoansSeizerTask.AssetCursorSet(address(_asset), 0);
        vm.prank(caller_);
        _task.setNextAssetBorrowerIndex(address(_asset), 0);
        assertEq(_task.assetCursor(address(_asset)), 0, "Recovery resets only the selected cursor");
        assertEq(_task.lastTransitionAt(), transition, "Reset preserves transition timestamp");
        assertEq(_task.isEnabled(), state_ != 1, "Reset preserves local lifecycle");
        _assertOtherStateUnchanged();
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P01, BLSEIZ-BORROWER-CURSOR-P02.
    function test_whenRoleLifecycleAndNumericBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass)
            for (uint8 state; state < 3; ++state) {
                assertTrue(vm.revertToState(checkpoint), "Restore lower cursor boundary");
                vm.clearMockedCalls();
                _assertPermittedNonzeroCursorSet(_DAVE, roleClass, state, 2, 1);
                assertTrue(vm.revertToState(checkpoint), "Restore upper cursor boundary");
                vm.clearMockedCalls();
                _assertPermittedNonzeroCursorSet(
                    _DAVE,
                    roleClass,
                    state,
                    type(uint256).max,
                    type(uint256).max - 1
                );
                assertTrue(vm.revertToState(checkpoint), "Restore reset boundary");
                vm.clearMockedCalls();
                test_givenPermittedCaller_whenBorrowerCursorReset_thenNoDownstreamReads(
                    _DAVE,
                    roleClass,
                    state
                );
            }
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-A01.
    function test_whenCallerHasNeitherRole_whenBorrowerCursorSet_reverts(
        address caller_,
        address asset_,
        uint256 index_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(IBurnerLoansLens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _task.setNextAssetBorrowerIndex(asset_, index_);
        assertEq(_task.assetCursor(address(_asset)), 0, "Unauthorized recovery preserves cursor");
        _assertOtherStateUnchanged();
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I01.
    function test_whenAssetUnmanaged_whenBorrowerCursorSet_reverts(
        address asset_,
        uint256 index_
    ) public {
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(IBurnerLoansLens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
        _assertUnmanagedCursorRejected(asset_, index_);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I01.
    function test_whenUnmanagedAssetBoundaries_whenBorrowerCursorSet_reverts() public {
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(IBurnerLoansLens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
        _assertUnmanagedCursorRejected(address(0), 0);
        _assertUnmanagedCursorRejected(address(type(uint160).max), type(uint256).max);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I02.
    function test_whenBorrowerCursorOutsidePopulation_reverts(
        uint256 population_,
        uint256 index_
    ) public {
        _assertInvalidBorrowerCursor(population_, index_);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I02.
    function test_whenInvalidBorrowerCursorBoundariesSeeded_reverts() public {
        _assertInvalidBorrowerCursor(0, 1);
        _assertInvalidBorrowerCursor(0, type(uint256).max);
        _assertInvalidBorrowerCursor(1, 1);
        _assertInvalidBorrowerCursor(3, 3);
        _assertInvalidBorrowerCursor(type(uint256).max, type(uint256).max);
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-P03.
    function test_whenBorrowerCursorUnchanged_thenValidateAndNoEvent() public {
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        vm.expectCall(address(_lens), _validation(1), uint64(1));
        vm.recordLogs();
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged valid offset emits no event");
        assertEq(_task.assetCursor(address(_asset)), 1, "Unchanged offset retained");
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I03.
    function test_givenSavedCursorStale_whenSameBorrowerCursorSet_reverts() public {
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        _mockCount(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                uint256(1),
                uint256(1)
            )
        );
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        assertEq(
            _task.assetCursor(address(_asset)),
            1,
            "Invalid same value does not bypass validation"
        );
        _task.setNextAssetBorrowerIndex(address(_asset), 0);
        assertEq(_task.assetCursor(address(_asset)), 0, "Explicit zero reset repairs stale offset");
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-I04.
    function test_givenLensReadFails_whenNonzeroBorrowerCursorSet_reverts() public {
        vm.mockCallRevert(
            address(_lens),
            _validation(1),
            abi.encodeWithSelector(CursorReadFailed.selector)
        );
        vm.expectRevert(CursorReadFailed.selector);
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        assertEq(_task.assetCursor(address(_asset)), 0, "Failed validation preserves cursor");
        _assertOtherStateUnchanged();
    }

    // Scenarios: BLSEIZ-BORROWER-CURSOR-L01.
    function test_givenInactiveTask_whenBorrowerCursorSet_reverts(
        bool disabled_,
        bool zero_
    ) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.setNextAssetBorrowerIndex(address(_asset), zero_ ? 0 : 1);
        assertEq(_task.assetCursor(address(_asset)), 0, "Inactive recovery preserves cursor");
        _setPolicyActive(address(_task), true);
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        assertEq(_task.assetCursor(address(_asset)), 1, "Recovery works after reactivation");
    }

    function _assertPermittedNonzeroCursorSet(
        address caller_,
        uint8 roleClass_,
        uint8 state_,
        uint256 population_,
        uint256 index_
    ) private {
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        state_ = uint8(bound(state_, 0, 2));
        population_ = bound(population_, 2, type(uint256).max);
        index_ = bound(index_, 1, population_ - 1);
        _grantTaskAdmin(caller_, roleClass_);
        _mockCount(population_);
        if (state_ != 0) _task.disable("");
        if (state_ == 2) _task.reEnable();
        uint48 transition = _task.lastTransitionAt();
        vm.expectCall(address(_lens), _validation(index_));
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.AssetCursorSet(address(_asset), index_);
        vm.prank(caller_);
        _task.setNextAssetBorrowerIndex(address(_asset), index_);
        assertEq(
            _task.assetCursor(address(_asset)),
            index_,
            "Exact requested borrower cursor stored"
        );
        assertEq(_task.lastTransitionAt(), transition, "Recovery preserves transition timestamp");
        assertEq(_task.isEnabled(), state_ != 1, "Recovery preserves local lifecycle");
        _assertOtherStateUnchanged();
    }

    function _assertUnmanagedCursorRejected(address asset_, uint256 index_) private {
        vm.assume(!_task.isAssetManaged(asset_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_AssetNotManaged.selector,
                asset_
            )
        );
        _task.setNextAssetBorrowerIndex(asset_, index_);
        assertEq(_task.assetCursor(asset_), 0, "Unmanaged cursor is not created");
    }

    function _assertInvalidBorrowerCursor(uint256 population_, uint256 index_) private {
        index_ = bound(index_, population_ == 0 ? 1 : population_, type(uint256).max);
        _mockCount(population_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                index_,
                population_
            )
        );
        _task.setNextAssetBorrowerIndex(address(_asset), index_);
        assertEq(_task.assetCursor(address(_asset)), 0, "Invalid offset preserves cursor");
        _assertOtherStateUnchanged();
    }

    function _validation(uint256 index_) private view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansLens.getSeizableBorrowersBoundedFor,
                (address(_task), address(_asset), index_, uint256(0), uint256(0))
            );
    }

    function _assertOtherStateUnchanged() private view {
        assertEq(_task.assetCursor(address(_otherAsset)), 0, "Other borrower cursor unchanged");
        assertEq(_task.nextAssetIndex(), 0, "Borrower recovery preserves asset traversal");
        assertEq(
            _task.getAssets(),
            _two(address(_asset), address(_otherAsset)),
            "Managed assets unchanged"
        );
        assertEq(_task.maxBorrowersToCheck(), 500, "Scan limit unchanged");
        assertEq(_task.maxBorrowersToSeize(), 25, "Seizure limit unchanged");
        assertEq(_task.executionGasLimit(), 10_000_000, "Gas limit unchanged");
        assertEq(_asset.balanceOf(address(_task)), 0, "Task custody remains empty");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
