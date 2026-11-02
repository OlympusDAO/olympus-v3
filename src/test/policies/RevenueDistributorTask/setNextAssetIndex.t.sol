// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetNextAssetIndexTest is RevenueDistributorTaskTest {
    uint256 internal constant TRAVERSAL_RECEIPT = 10;

    // Scenarios: CUR-A01, CUR-A02.
    function test_whenUnauthorizedCallerSetsCursor_reverts(
        address caller_,
        uint256 index_,
        bool disabled_,
        bool assetsExist_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        if (assetsExist_) _configureAssets(2, 0);
        _setTaskDisabled(disabled_);

        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSignature("UnexpectedCountRead()")
        );
        bytes32 context = _cursorContextDigest();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setNextAssetIndex(index_);

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
        assertEq(
            _cursorContextDigest(),
            context,
            "Unauthorized cursor request preserves all configuration and custody"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Unauthorized cursor request emits no event");
    }

    // Scenarios: CUR-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        address caller = caller_;
        _configureAssets(2, 0);
        _deactivateTask();

        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("getActiveAssetCount()"),
            abi.encodeWithSignature("UnexpectedLookup()")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller);
        task.setNextAssetIndex(1);

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: CUR-P02, CUR-P04, CUR-P05, CUR-P06.
    function test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        address caller = caller_;
        _configureAssets(2, 0);
        _disableTask("");
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);

        _assertCursorUpdate(caller, 1);
        assertFalse(task.isEnabled(), "task remains disabled");
    }

    // Scenarios: CUR-I01, CUR-I02.
    function test_whenCursorIsOutOfRange_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint256 count_,
        uint256 index_
    ) public {
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        address caller = caller_;
        uint256 count = count_;
        vm.mockCall(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encode(count)
        );
        if (count > 1) {
            vm.prank(admin);
            task.setNextAssetIndex(1);
        }
        _setTaskDisabled(disabled_);
        uint256 minimumInvalid = count == 0 ? 1 : count;
        index_ = bound(index_, minimumInvalid, type(uint256).max);
        uint256 cursorBefore = task.nextAssetIndex();

        bytes32 context = _cursorContextDigest();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_InvalidAssetIndex.selector,
                index_,
                count
            )
        );
        vm.prank(caller);
        task.setNextAssetIndex(index_);

        assertEq(task.nextAssetIndex(), cursorBefore, "invalid update preserves cursor");
        assertEq(_cursorContextDigest(), context, "Invalid cursor request preserves full context");
        assertEq(vm.getRecordedLogs().length, 0, "Invalid cursor request emits no events");
    }

    // Scenarios: CUR-P01, CUR-P07.
    function test_whenChangedCursorIsValid_storesExactInput(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint256 count_,
        uint256 currentIndex_,
        uint256 index_
    ) public {
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        address caller = caller_;
        count_ = bound(count_, 2, type(uint256).max);
        vm.mockCall(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encode(count_)
        );
        currentIndex_ = bound(currentIndex_, 0, count_ - 1);
        vm.prank(admin);
        task.setNextAssetIndex(currentIndex_);
        index_ = bound(index_, 0, count_ - 1);
        vm.assume(index_ != currentIndex_);
        _setTaskDisabled(disabled_);

        _assertCursorUpdate(caller, index_);
    }

    // Scenarios: CUR-P03, CUR-P08.
    function test_whenCurrentCursorProvided_isNoOp(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint256 count_,
        uint256 currentIndex_
    ) public {
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        address caller = caller_;

        if (count_ != 0) {
            vm.mockCall(
                address(distributor),
                abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
                abi.encode(count_)
            );
            currentIndex_ = bound(currentIndex_, 0, count_ - 1);
            vm.prank(admin);
            task.setNextAssetIndex(currentIndex_);
        } else {
            currentIndex_ = 0;
        }
        _setTaskDisabled(disabled_);

        bytes32 context = _cursorContextDigest();
        vm.recordLogs();
        vm.prank(caller);
        task.setNextAssetIndex(currentIndex_);

        assertEq(vm.getRecordedLogs().length, 0, "same cursor emits no event");
        assertEq(task.nextAssetIndex(), currentIndex_, "cursor unchanged");
        assertEq(_cursorContextDigest(), context, "Repeated cursor preserves full context");
    }

    // Scenarios: CUR-P01, CUR-P07.
    function test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere() public {
        MockERC20[] memory assets = _configureAssets(13, TRAVERSAL_RECEIPT);
        vm.startPrank(admin);
        task.setExecutionGasLimit(900_000);
        task.setNextAssetIndex(6);
        vm.stopPrank();

        vm.prank(alice);
        task.execute();

        assertEq(
            assets[6].balanceOf(address(treasury)),
            TRAVERSAL_RECEIPT,
            "selected asset settles first"
        );
        assertEq(assets[0].balanceOf(address(treasury)), 0, "earlier asset remains unattempted");
    }

    function _assertCursorUpdate(address caller_, uint256 index_) internal {
        bytes32 context = _cursorContextDigest();
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.NextAssetIndexSet(index_);
        vm.recordLogs();
        vm.prank(caller_);
        task.setNextAssetIndex(index_);
        assertEq(task.nextAssetIndex(), index_, "cursor equals input");
        assertEq(vm.getRecordedLogs().length, 1, "Exactly one cursor event");
        assertEq(
            _cursorContextDigest(),
            context,
            "Cursor change preserves other settings, custody and lifecycle"
        );
    }

    // Scenarios: CUR-P09.
    function test_givenUnavailableRegistry_whenCursorReset_succeeds() public {
        _configureAssets(2, 0);
        vm.prank(admin);
        task.setNextAssetIndex(1);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSignature("RegistryUnavailable()")
        );
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.NextAssetIndexSet(0);
        vm.prank(admin);
        task.setNextAssetIndex(0);
        assertEq(task.nextAssetIndex(), 0, "Reset does not need the live registry");
    }

    // Scenarios: CUR-P10.
    function test_givenUnavailableRegistry_whenZeroCursorSetAgain_succeeds() public {
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSignature("RegistryUnavailable()")
        );
        vm.recordLogs();
        vm.prank(admin);
        task.setNextAssetIndex(0);
        assertEq(task.nextAssetIndex(), 0, "Zero cursor remains selected");
        assertEq(vm.getRecordedLogs().length, 0, "Repeated reset emits no event");
    }

    // Scenarios: CUR-A01, CUR-A02, CUR-I01, CUR-I02, CUR-L01, CUR-P01, CUR-P02, CUR-P03, CUR-P04, CUR-P05, CUR-P06, CUR-P07, CUR-P08.
    function test_givenCursorAndRoleBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            false,
            2,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            false,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, false, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, false, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            false,
            false,
            false,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, false, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, false, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, false, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            false,
            false,
            2,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            false,
            false,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, false, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, false, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            false,
            false,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, false, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, false, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, false, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, true, false, 2, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            true,
            false,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, false, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, false, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            true,
            false,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, false, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, false, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, false, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            true,
            2,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            true,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, true, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, true, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            false,
            false,
            true,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, true, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, true, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), false, false, true, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, false, true, 2, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            false,
            true,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, true, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, true, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            false,
            true,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, true, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, true, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, false, true, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, true, true, 2, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            true,
            true,
            type(uint256).max,
            0,
            type(uint256).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, true, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, true, 3, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            true,
            true,
            3,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, true, 0, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, true, 1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_whenCurrentCursorProvided_isNoOp(address(0x1234), true, true, true, 3, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(address(0x1234), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            false,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            false,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            false,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();
        test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
            address(0x1234),
            true,
            true,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore cursor seed");
        vm.clearMockedCalls();

        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, false, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, false, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            false,
            false,
            false,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            false,
            2,
            0,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, false, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, false, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            false,
            false,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            true,
            false,
            false,
            2,
            0,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, false, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, false, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            true,
            false,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, true, false, 2, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 0, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 1, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), type(uint256).max, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 0, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 1, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), type(uint256).max, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, true, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), false, false, true, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            false,
            false,
            true,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(
            address(0x1234),
            false,
            false,
            true,
            2,
            0,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, true, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, false, true, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            false,
            true,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, false, true, 2, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, true, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(address(0x1234), true, true, true, 3, 4);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenCursorIsOutOfRange_reverts(
            address(0x1234),
            true,
            true,
            true,
            type(uint256).max,
            type(uint256).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenChangedCursorIsValid_storesExactInput(address(0x1234), true, true, true, 2, 0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 0, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 1, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), type(uint256).max, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 0, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), 1, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
        test_whenUnauthorizedCallerSetsCursor_reverts(address(0), type(uint256).max, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic cursor boundary");
        vm.clearMockedCalls();
    }

    function _cursorContextDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _revenueAccountingDigest(),
                    task.executionGasLimit(),
                    task.minimumGasToAttempt(),
                    task.gasReserve(),
                    task.distributor(),
                    task.isActive(),
                    task.isEnabled(),
                    task.lastTransitionAt(),
                    distributor.isActive(),
                    distributor.isEnabled(),
                    distributor.lastTransitionAt()
                )
            );
    }

    // Scenarios: CUR-L02.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst(
        address caller_,
        uint256 value_
    ) public {
        _setTaskDisabled(true);
        _deactivateTask();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setNextAssetIndex(value_);
    }
}
