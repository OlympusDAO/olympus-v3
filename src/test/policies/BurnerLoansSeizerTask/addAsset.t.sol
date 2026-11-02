// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansSeizerTaskAddAssetTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-ADD-ASSET-I02.
    function test_givenEnabled_whenAdminAddsRegisteredAsset(address caller_) public {
        _assertRegisteredAssetAdded(caller_, true);
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I02.
    function test_givenDisabled_whenAdminAddsRegisteredAsset(
        address caller_
    ) public givenTaskDisabled {
        _assertRegisteredAssetAdded(caller_, false);
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I02.
    function test_givenReEnabled_whenAdminAddsRegisteredAsset(
        address caller_
    ) public givenTaskReEnabled {
        _assertRegisteredAssetAdded(caller_, true);
    }

    // Scenarios: BLSEIZ-ADD-ASSET-P01.
    function test_givenDuplicateAsset_whenAdded_reverts() public {
        _task.addAsset(address(_asset));
        vm.expectCall(
            address(_core),
            abi.encodeCall(_core.isAssetRegistered, (address(_asset))),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_AssetAlreadyManaged.selector,
                address(_asset)
            )
        );
        _task.addAsset(address(_asset));
        assertEq(
            _task.getAssets(),
            _one(address(_asset)),
            "Duplicate rejection preserves registry"
        );
    }

    // Scenarios: BLSEIZ-ADD-ASSET-A01.
    function test_whenCallerIsUnauthorized_reverts(address caller_, address asset_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        _task.addAsset(asset_);
        assertEq(_task.getAssets().length, 0, "Unauthorized caller cannot change registry");
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I01.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0)
            )
        );
        _task.addAsset(address(0));
        assertEq(_task.getAssets().length, 0, "Zero rejection preserves registry");
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I03.
    function test_whenAssetIsUnregistered_reverts(address asset_) public {
        vm.assume(asset_ != address(0) && !_core.isAssetRegistered(asset_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        _task.addAsset(asset_);
        assertFalse(_task.isAssetManaged(asset_), "Unsupported asset is not admitted");
        assertEq(_task.getAssets().length, 0, "Unsupported asset creates no registry entry");
        assertEq(_task.assetCursor(asset_), 0, "Unsupported asset creates no borrower cursor");
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I03.
    function test_whenUnregisteredAddressBoundaries_reverts() public {
        test_whenAssetIsUnregistered_reverts(address(1));
        test_whenAssetIsUnregistered_reverts(address(type(uint160).max));
        test_whenAssetIsUnregistered_reverts(address(_task));
    }

    // Scenarios: BLSEIZ-ADD-ASSET-I02.
    function test_whenLifecycleStatesSeeded_thenRegisteredAssetAdded() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenAdminAddsRegisteredAsset(_ALICE);
        assertTrue(vm.revertToState(checkpoint), "Restore disabled admission fixture");
        test_givenDisabled_whenAdminAddsRegisteredAsset(_ALICE);
        assertTrue(vm.revertToState(checkpoint), "Restore re-enabled admission fixture");
        test_givenReEnabled_whenAdminAddsRegisteredAsset(_ALICE);
    }

    // Scenarios: BLSEIZ-ADD-ASSET-P03.
    function test_givenCoreUnavailable_whenRegisteredAssetAdded(
        bool active_,
        bool enabled_
    ) public {
        _setCoreLifecycle(active_, enabled_);
        _task.addAsset(address(_asset));
        assertTrue(
            _task.isAssetManaged(address(_asset)),
            "Listing does not require Core readiness"
        );
    }

    // Scenarios: BLSEIZ-ADD-ASSET-P02.
    function test_givenInactiveTask_whenAssetAdded_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.addAsset(address(_asset));
        assertEq(_task.getAssets().length, 0, "Inactive admission preserves registry");
        _setPolicyActive(address(_task), true);
        _task.addAsset(address(_asset));
        assertTrue(_task.isAssetManaged(address(_asset)), "Admission recovers after reactivation");
    }

    function _assertRegisteredAssetAdded(address caller_, bool enabled_) private {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, ADMIN_ROLE)) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint48 transition = _task.lastTransitionAt();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.AssetAdded(address(_asset));
        vm.prank(caller_);
        _task.addAsset(address(_asset));
        assertTrue(_task.isAssetManaged(address(_asset)), "Registered asset is managed");
        assertEq(_task.getAssets(), _one(address(_asset)), "Managed registry has one entry");
        assertEq(_task.assetCursor(address(_asset)), 0, "Initial borrower cursor");
        assertEq(_task.lastTransitionAt(), transition, "Adding an asset preserves lifecycle");
        assertEq(_task.isEnabled(), enabled_, "Adding an asset preserves local enablement");
    }
}
