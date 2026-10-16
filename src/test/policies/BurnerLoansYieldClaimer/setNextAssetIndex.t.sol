// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetNextAssetIndexTest is BurnerLoansYieldClaimerTest {
    uint8 internal constant _MAX_FUZZ_ASSET_COUNT = 8;
    uint8 internal constant _MULTI_ASSET_COUNT = 3;

    // Scenarios: CUR-A01.
    function test_whenUnauthorizedCallerSetsCursor_reverts(
        address caller_,
        uint256 index_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        target.setAssetViewReverts(true);
        _setClaimerLifecycle(active_, enabled_);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: CUR-I01.
    function test_whenCursorIsOutOfRange_reverts(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        bool assetsExist_,
        uint256 index_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint256 count = assetsExist_ ? _MULTI_ASSET_COUNT : 0;
        if (assetsExist_) {
            address[] memory assets = new address[](count);
            for (uint256 i; i < count; ++i) {
                assets[i] = _assetAddress(i);
            }
            target.setAssets(assets);
        } else {
            target.setAssets(new address[](0));
        }
        _setClaimerLifecycle(active_, enabled_);
        index_ = bound(index_, count == 0 ? 1 : count, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidAssetIndex.selector,
                index_,
                count
            )
        );
        vm.prank(caller);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), 0, "invalid input preserves cursor");
    }

    // Scenarios: CUR-I01.
    function test_whenCursorBoundaryIsInvalid_reverts(bool adminCalls_, bool assetsExist_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint256 count = assetsExist_ ? _MULTI_ASSET_COUNT : 0;
        address[] memory assets = new address[](count);
        for (uint256 i; i < count; ++i) {
            assets[i] = _assetAddress(i);
        }
        target.setAssets(assets);
        uint256 minimumInvalid = count == 0 ? 1 : count;
        _assertInvalidCursorBoundary(caller, minimumInvalid, count);
        _assertInvalidCursorBoundary(caller, minimumInvalid + 1, count);
        _assertInvalidCursorBoundary(caller, type(uint256).max, count);
    }

    function _assertInvalidCursorBoundary(
        address caller_,
        uint256 invalid_,
        uint256 count_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidAssetIndex.selector,
                invalid_,
                count_
            )
        );
        vm.prank(caller_);
        claimer.setNextAssetIndex(invalid_);
        assertEq(claimer.nextAssetIndex(), 0, "invalid boundary preserves cursor");
    }

    // Scenarios: CUR-P01.
    function test_whenChangedCursorIsValid_storesExactInput(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint8 count_,
        uint256 index_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        count_ = _boundUint8(count_, 2, _MAX_FUZZ_ASSET_COUNT);
        address[] memory assets = new address[](count_);
        for (uint256 i; i < count_; ++i) {
            assets[i] = _assetAddress(i);
        }
        target.setAssets(assets);
        index_ = bound(index_, 1, count_ - 1);
        _setClaimerLifecycle(active_, enabled_);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.NextAssetIndexSet(index_);
        vm.prank(caller);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), index_, "cursor equals input");
    }

    // Scenarios: CUR-P01.
    function test_whenCursorResetToZero_storesExactInput(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("resetFirst");
        assets[1] = makeAddr("resetSecond");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.NextAssetIndexSet(0);
        vm.prank(caller);
        claimer.setNextAssetIndex(0);

        assertEq(claimer.nextAssetIndex(), 0, "cursor resets to zero");
    }

    // Scenarios: CUR-P05.
    function test_whenRegistryCountReverts_zeroStillResetsCursor(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("recoveryFirst");
        assets[1] = makeAddr("recoverySecond");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        target.setAssetViewReverts(true);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.NextAssetIndexSet(0);
        vm.prank(caller);
        claimer.setNextAssetIndex(0);

        assertEq(claimer.nextAssetIndex(), 0, "cursor resets without registry access");
    }

    // Scenarios: CUR-P02, CUR-P03.
    function test_whenCurrentCursorProvided_isNoOp(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        bool assetsExist_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        if (assetsExist_) {
            address[] memory assets = new address[](2);
            assets[0] = makeAddr("sameCursorFirst");
            assets[1] = makeAddr("sameCursorSecond");
            target.setAssets(assets);
            vm.prank(admin);
            claimer.setNextAssetIndex(1);
        } else {
            target.setAssets(new address[](0));
        }
        _setClaimerLifecycle(active_, enabled_);

        vm.recordLogs();
        vm.prank(caller);
        claimer.setNextAssetIndex(assetsExist_ ? 1 : 0);

        assertEq(vm.getRecordedLogs().length, 0, "same cursor emits no event");
        assertEq(claimer.nextAssetIndex(), assetsExist_ ? 1 : 0, "cursor unchanged");
    }

    // Scenarios: CUR-P04.
    function test_givenRegisteredAssets_whenCursorSelected_nextBeatStartsThere() public {
        address[] memory assets = new address[](_MULTI_ASSET_COUNT);
        assets[0] = makeAddr("selectedFirst");
        assets[1] = makeAddr("selectedSecond");
        assets[2] = makeAddr("selectedThird");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);

        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimedAssets(0), assets[1], "selected asset claimed first");
        assertEq(target.claimedAssets(1), assets[2], "following asset claimed second");
        assertEq(target.claimedAssets(2), assets[0], "traversal wraps to first asset");
    }

    function _assetAddress(uint256 index_) internal pure returns (address) {
        // Test asset counts are capped at eight, so index + 1 always fits in uint160.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(index_ + 1));
    }
}
