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

// Fixed registry sizes and role/lifecycle partitions are deliberate boundary fixtures.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskSetNextAssetIndexTest is BurnerLoansSeizerTaskTest {
    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
    }

    modifier givenBorrowerProgress() {
        _mockCount(2);
        _task.setNextAssetBorrowerIndex(address(_asset), 1);
        _;
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenEnabled_whenPermittedCallerChangesAssetIndex(
        address caller_,
        uint8 roleClass_,
        uint256 index_
    ) public givenBorrowerProgress {
        _assertAssetIndexChanged(caller_, roleClass_, index_, true);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenEnabled_whenRoleAndIndexBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass)
            for (uint256 index; index < 2; ++index) {
                assertTrue(vm.revertToState(checkpoint), "Restore enabled asset-index fixture");
                test_givenEnabled_whenPermittedCallerChangesAssetIndex(_ALICE, roleClass, index);
            }
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenDisabled_whenPermittedCallerChangesAssetIndex(
        address caller_,
        uint8 roleClass_,
        uint256 index_
    ) public givenBorrowerProgress givenTaskDisabled {
        _assertAssetIndexChanged(caller_, roleClass_, index_, false);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenDisabled_whenRoleAndIndexBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass)
            for (uint256 index; index < 2; ++index) {
                assertTrue(vm.revertToState(checkpoint), "Restore disabled asset-index fixture");
                test_givenDisabled_whenPermittedCallerChangesAssetIndex(_ALICE, roleClass, index);
            }
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenReEnabled_whenPermittedCallerChangesAssetIndex(
        address caller_,
        uint8 roleClass_,
        uint256 index_
    ) public givenBorrowerProgress givenTaskReEnabled {
        _assertAssetIndexChanged(caller_, roleClass_, index_, true);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P01.
    function test_givenReEnabled_whenRoleAndIndexBoundariesSeeded() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass)
            for (uint256 index; index < 2; ++index) {
                assertTrue(vm.revertToState(checkpoint), "Restore reenabled asset-index fixture");
                test_givenReEnabled_whenPermittedCallerChangesAssetIndex(_ALICE, roleClass, index);
            }
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-A01.
    function test_whenCallerHasNeitherRole_reverts(address caller_, uint256 index_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _task.setNextAssetIndex(index_);
        assertEq(_task.nextAssetIndex(), 0, "Unauthorized call preserves traversal");
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-I01.
    function test_whenIndexOutsideManagedSet_reverts(uint256 index_) public {
        index_ = bound(index_, 2, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidAssetIndex.selector,
                index_,
                uint256(2)
            )
        );
        _task.setNextAssetIndex(index_);
        assertEq(_task.nextAssetIndex(), 0, "Rejected index preserves traversal");
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-I02.
    function test_givenEmptyRegistry_whenNonzeroIndexSet_reverts(uint256 index_) public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        index_ = bound(index_, 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidAssetIndex.selector,
                index_,
                uint256(0)
            )
        );
        _task.setNextAssetIndex(index_);
        assertEq(_task.nextAssetIndex(), 0, "Empty registry preserves zero traversal");
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-I01, BLSEIZ-ASSET-INDEX-I02.
    function test_whenInvalidIndexBoundariesSeeded_reverts() public {
        test_whenIndexOutsideManagedSet_reverts(2);
        test_whenIndexOutsideManagedSet_reverts(type(uint256).max);
        uint256 checkpoint = vm.snapshotState();
        test_givenEmptyRegistry_whenNonzeroIndexSet_reverts(1);
        assertTrue(vm.revertToState(checkpoint), "Restore empty-registry boundary setup");
        test_givenEmptyRegistry_whenNonzeroIndexSet_reverts(type(uint256).max);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-I03.
    function test_givenSingleAsset_whenIndexEqualsCount_reverts() public {
        _task.removeAsset(address(_otherAsset));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidAssetIndex.selector,
                uint256(1),
                uint256(1)
            )
        );
        _task.setNextAssetIndex(1);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P02.
    function test_givenEmptyRegistry_whenReset_thenEventFreeNoOp() public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        vm.recordLogs();
        _task.setNextAssetIndex(0);
        assertEq(vm.getRecordedLogs().length, 0, "Empty reset is an event-free no-op");
        assertEq(_task.nextAssetIndex(), 0, "Empty registry remains at zero");
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P03.
    function test_whenIndexUnchanged_thenEventFreeNoOp() public {
        _task.setNextAssetIndex(1);
        vm.recordLogs();
        _task.setNextAssetIndex(1);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged cursor emits no setter event");
        assertEq(_task.nextAssetIndex(), 1, "Unchanged cursor remains exact");
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P04.
    function test_givenDownstreamUnavailable_whenReset_thenNoDownstreamReads() public {
        _task.setNextAssetIndex(1);
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            hex"aabbccdd"
        );
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(IBurnerLoansLens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.NextAssetIndexSet(0);
        _task.setNextAssetIndex(0);
        assertEq(
            _task.nextAssetIndex(),
            0,
            "Zero reset works with unavailable downstream metadata"
        );
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-L01.
    function test_givenInactiveEnabledTask_whenAssetIndexSet_reverts(uint256 index_) public {
        _assertInactiveAssetIndexRejected(index_);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-L01.
    function test_givenInactiveDisabledTask_whenAssetIndexSet_reverts(
        uint256 index_
    ) public givenTaskDisabled {
        _assertInactiveAssetIndexRejected(index_);
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-L01.
    function test_whenInactiveLifecycleAndIndexBoundariesSeeded_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 index; index < 2; ++index) {
            assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled fixture");
            test_givenInactiveEnabledTask_whenAssetIndexSet_reverts(index);
            assertTrue(vm.revertToState(checkpoint), "Restore inactive disabled fixture");
            test_givenInactiveDisabledTask_whenAssetIndexSet_reverts(index);
        }
    }

    // Scenarios: BLSEIZ-ASSET-INDEX-P05.
    function test_whenSecondAssetSelected_thenNextExecutionScansIt() public {
        _task.setNextAssetIndex(1);
        vm.expectCall(address(_lens), _boundedScan(address(_otherAsset), 0), uint64(1));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Selected last asset wraps to first");
    }

    function _assertAssetIndexChanged(
        address caller_,
        uint8 roleClass_,
        uint256 index_,
        bool enabled_
    ) private {
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        index_ = bound(index_, 0, 1);
        _grantTaskAdmin(caller_, roleClass_);
        _task.setNextAssetIndex(1 - index_);
        uint48 transition = _task.lastTransitionAt();
        address[] memory assets = _task.getAssets();
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.NextAssetIndexSet(index_);
        vm.prank(caller_);
        _task.setNextAssetIndex(index_);
        assertEq(_task.nextAssetIndex(), index_, "Exact requested asset index stored");
        assertEq(_task.getAssets(), assets, "Recovery preserves asset membership/order");
        assertEq(_task.assetCursor(address(_asset)), 1, "A nonzero borrower cursor unchanged");
        assertEq(_task.assetCursor(address(_otherAsset)), 0, "B borrower cursor unchanged");
        assertEq(_task.lastTransitionAt(), transition, "Recovery preserves transition timestamp");
        assertEq(_task.isEnabled(), enabled_, "Recovery preserves local lifecycle");
        assertEq(_task.maxBorrowersToCheck(), 500, "Recovery preserves scan limit");
        assertEq(_task.maxBorrowersToSeize(), 25, "Recovery preserves batch limit");
        assertEq(_task.executionGasLimit(), 10_000_000, "Recovery preserves gas limit");
    }

    function _assertInactiveAssetIndexRejected(uint256 index_) private {
        index_ = bound(index_, 0, 1);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.setNextAssetIndex(index_);
        assertEq(_task.nextAssetIndex(), 0, "Inactive recovery preserves traversal");
        _setPolicyActive(address(_task), true);
        _task.setNextAssetIndex(1);
        assertEq(_task.nextAssetIndex(), 1, "Recovery works after Kernel reactivation");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
