// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskSetNextAssetIndexTest is BurnerLoansYieldClaimerTaskTest {
    uint8 internal constant _MAX_FUZZ_ASSET_COUNT = 8;
    uint8 internal constant _MULTI_ASSET_COUNT = 3;

    // Scenarios: BLYC-CURSOR-A01.
    function test_whenUnauthorizedCallerSetsCursor_reverts(
        address caller_,
        uint256 index_,
        uint8 mode_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        target.setAssetViewReverts(true);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: BLYC-CURSOR-P03.
    function test_whenCursorIsOutOfRange_reverts(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        bool assetsExist_,
        uint256 index_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
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
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);
        index_ = bound(index_, count == 0 ? 1 : count, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidAssetIndex.selector,
                index_,
                count
            )
        );
        vm.prank(caller_);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), 0, "invalid input preserves cursor");
    }

    // Scenarios: BLYC-CURSOR-P03.
    function test_whenCursorBoundaryIsInvalid_reverts(
        address caller_,
        uint8 roleClass_,
        bool assetsExist_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        uint256 count = assetsExist_ ? _MULTI_ASSET_COUNT : 0;
        address[] memory assets = new address[](count);
        for (uint256 i; i < count; ++i) {
            assets[i] = _assetAddress(i);
        }
        target.setAssets(assets);
        uint256 minimumInvalid = count == 0 ? 1 : count;
        _assertInvalidCursorBoundary(caller_, minimumInvalid, count);
        _assertInvalidCursorBoundary(caller_, minimumInvalid + 1, count);
        _assertInvalidCursorBoundary(caller_, type(uint256).max, count);
    }

    function _assertInvalidCursorBoundary(
        address caller_,
        uint256 invalid_,
        uint256 count_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidAssetIndex.selector,
                invalid_,
                count_
            )
        );
        vm.prank(caller_);
        claimer.setNextAssetIndex(invalid_);
        assertEq(claimer.nextAssetIndex(), 0, "invalid boundary preserves cursor");
    }

    // Scenarios: BLYC-CURSOR-A02, BLYC-CURSOR-A03, BLYC-CURSOR-A04, BLYC-CURSOR-P01.
    function test_whenChangedCursorIsValid_storesExactInput(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        uint8 count_,
        uint256 index_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        count_ = _boundUint8(count_, 2, _MAX_FUZZ_ASSET_COUNT);
        address[] memory assets = new address[](count_);
        for (uint256 i; i < count_; ++i) {
            assets[i] = _assetAddress(i);
        }
        target.setAssets(assets);
        index_ = bound(index_, 1, count_ - 1);
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.NextAssetIndexSet(index_);
        vm.prank(caller_);
        claimer.setNextAssetIndex(index_);

        assertEq(claimer.nextAssetIndex(), index_, "cursor equals input");
    }

    // Scenarios: BLYC-CURSOR-A02, BLYC-CURSOR-A03, BLYC-CURSOR-A04, BLYC-CURSOR-P02.
    function test_whenCursorResetToZero_storesExactInput(
        address caller_,
        uint8 roleClass_,
        uint8 mode_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("resetFirst");
        assets[1] = makeAddr("resetSecond");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        _setLocalMode(mode_);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.NextAssetIndexSet(0);
        vm.prank(caller_);
        claimer.setNextAssetIndex(0);

        assertEq(claimer.nextAssetIndex(), 0, "cursor resets to zero");
    }

    // Scenarios: BLYC-CURSOR-P02.
    function test_whenRegistryCountReverts_zeroStillResetsCursor(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("recoveryFirst");
        assets[1] = makeAddr("recoverySecond");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        target.setAssetViewReverts(true);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.NextAssetIndexSet(0);
        vm.prank(caller_);
        claimer.setNextAssetIndex(0);

        assertEq(claimer.nextAssetIndex(), 0, "cursor resets without registry access");
    }

    // Scenarios: BLYC-CURSOR-P01, BLYC-CURSOR-P02.
    function test_whenCurrentCursorProvided_isNoOp(
        address caller_,
        uint8 roleClass_,
        uint8 mode_,
        bool enabled_,
        bool assetsExist_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
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
        _setLocalMode(mode_);
        _setTargetLifecycle(true, enabled_);

        vm.recordLogs();
        vm.prank(caller_);
        claimer.setNextAssetIndex(assetsExist_ ? 1 : 0);

        assertEq(vm.getRecordedLogs().length, 0, "same cursor emits no event");
        assertEq(claimer.nextAssetIndex(), assetsExist_ ? 1 : 0, "cursor unchanged");
    }

    // Scenarios: BLYC-CURSOR-P01.
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

    // Scenarios: BLYC-CURSOR-P04.
    function test_givenInactivePolicy_whenSetting_reverts(
        address caller_,
        uint8 roleClass_,
        bool enabled_,
        uint256 value_
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
        claimer.setNextAssetIndex(value_);
        assertEq(_settingsDigest(), settings, "Inactive setter preserves every field");
    }

    // Scenarios: BLYC-CURSOR-P03.
    function test_givenCursorInvalidAfterShrink_whenSameIndexSet_reverts(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        address[] memory assets = new address[](3);
        assets[0] = address(1);
        assets[1] = address(2);
        assets[2] = address(3);
        target.setAssets(assets);
        vm.prank(caller_);
        claimer.setNextAssetIndex(2);
        target.setAssets(new address[](1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidAssetIndex.selector,
                2,
                1
            )
        );
        vm.prank(caller_);
        claimer.setNextAssetIndex(2);
        assertEq(claimer.nextAssetIndex(), 2, "Validation precedes equality");
    }

    // Scenarios: BLYC-CURSOR-A02, BLYC-CURSOR-A03, BLYC-CURSOR-A04.
    function test_whenAuthorizedRoleAndLocalStateSeeds() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            for (uint8 mode; mode < 3; ++mode) {
                test_whenChangedCursorIsValid_storesExactInput(
                    address(0xBEEF),
                    roleClass,
                    mode,
                    true,
                    3,
                    2
                );
                vm.revertToState(snapshot);
            }
        }
    }
}
