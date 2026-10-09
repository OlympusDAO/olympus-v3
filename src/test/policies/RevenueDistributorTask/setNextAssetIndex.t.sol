// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetNextAssetIndexTest is RevenueDistributorTaskTest {
    uint8 internal constant MAX_FUZZ_ASSET_COUNT = 8;
    uint256 internal constant TRAVERSAL_RECEIPT = 10;

    // Scenarios: CUR-A01.
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

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setNextAssetIndex(index_);

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: CUR-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts(bool adminCalls_) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _configureAssets(2, 0);
        _deactivateTask();

        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("getActiveAssetCount()"),
            abi.encodeWithSignature("UnexpectedLookup()")
        );
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_PolicyInactive.selector);
        vm.prank(caller);
        task.setNextAssetIndex(1);

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: CUR-P02.
    function test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle(
        bool adminCalls_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _configureAssets(2, 0);
        _disableTask("");
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);

        _assertCursorUpdate(caller, 1);
        assertFalse(task.isEnabled(), "task remains disabled");
    }

    // Scenarios: CUR-I01.
    function test_whenCursorIsOutOfRange_reverts(
        bool adminCalls_,
        bool disabled_,
        bool assetsExist_,
        uint256 index_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        uint256 count = assetsExist_ ? 3 : 0;
        if (assetsExist_) {
            _configureAssets(count, 0);
            vm.prank(admin);
            task.setNextAssetIndex(1);
        }
        _setTaskDisabled(disabled_);
        uint256 minimumInvalid = count == 0 ? 1 : count;
        index_ = bound(index_, minimumInvalid, type(uint256).max);
        uint256 cursorBefore = task.nextAssetIndex();

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
    }

    // Scenarios: CUR-P01.
    function test_whenChangedCursorIsValid_storesExactInput(
        bool adminCalls_,
        bool disabled_,
        uint8 count_,
        uint256 currentIndex_,
        uint256 index_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        count_ = _boundUint8(count_, 2, MAX_FUZZ_ASSET_COUNT);
        _configureAssets(count_, 0);
        currentIndex_ = bound(currentIndex_, 0, count_ - 1);
        vm.prank(admin);
        task.setNextAssetIndex(currentIndex_);
        index_ = bound(index_, 0, count_ - 1);
        if (index_ == currentIndex_) index_ = (currentIndex_ + 1) % count_;
        _setTaskDisabled(disabled_);

        _assertCursorUpdate(caller, index_);
    }

    // Scenarios: CUR-P03.
    function test_whenCurrentCursorProvided_isNoOp(
        bool adminCalls_,
        bool disabled_,
        uint8 count_,
        uint256 currentIndex_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        count_ = _boundUint8(count_, 0, MAX_FUZZ_ASSET_COUNT);
        if (count_ != 0) {
            _configureAssets(count_, 0);
            currentIndex_ = bound(currentIndex_, 0, count_ - 1);
            vm.prank(admin);
            task.setNextAssetIndex(currentIndex_);
        } else {
            currentIndex_ = 0;
        }
        _setTaskDisabled(disabled_);

        vm.recordLogs();
        vm.prank(caller);
        task.setNextAssetIndex(currentIndex_);

        assertEq(vm.getRecordedLogs().length, 0, "same cursor emits no event");
        assertEq(task.nextAssetIndex(), currentIndex_, "cursor unchanged");
    }

    // Scenarios: CUR-P01.
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
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.NextAssetIndexSet(index_);
        vm.prank(caller_);
        task.setNextAssetIndex(index_);
        assertEq(task.nextAssetIndex(), index_, "cursor equals input");
    }
}
