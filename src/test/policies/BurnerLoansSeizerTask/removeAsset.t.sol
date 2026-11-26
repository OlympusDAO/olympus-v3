// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansSeizerTaskRemoveAssetTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-REMOVE-ASSET-P07.
    function test_givenUnequalCursors_whenAssetRemoved_thenBothCursorsAreCleared() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        _mockCount(10);
        vm.prank(_seizerAdmin);
        _task.setScanLimits(2, 1);
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
        vm.prank(_seizerAdmin);
        _task.removeAsset(address(_asset));
        assertEq(_task.expiredAssetCursor(address(_asset)), 0, "Removal clears expiry progress");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Removal clears unhealthy progress"
        );
        assertFalse(
            _task.isAssetManaged(address(_asset)),
            "Removed asset leaves both discovery lanes"
        );
    }

    function test_givenManagedAssetAndAdmin_removesAsset() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.removeAsset(address(_asset));

        assertFalse(_task.isAssetManaged(address(_asset)), "asset removed");
        assertEq(_task.getAssets().length, 0, "managed asset count");
    }

    function test_givenMissingAsset_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_AssetNotManaged.selector,
                address(_asset)
            )
        );
        vm.prank(_seizerAdmin);
        _task.removeAsset(address(_asset));
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        _task.removeAsset(address(_asset));
    }

    function test_givenDisabled_givenManagedAsset_removesAsset() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.disable("");

        vm.prank(_seizerAdmin);
        _task.removeAsset(address(_asset));

        assertFalse(_task.isAssetManaged(address(_asset)), "asset removed while disabled");
    }
}
