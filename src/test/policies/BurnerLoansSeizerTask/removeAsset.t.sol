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
    function test_givenManagedAssetAndAdmin_removesAsset() public {
        _task.addAsset(address(_asset));
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
        _task.removeAsset(address(_asset));
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _task.addAsset(address(_asset));

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        _task.removeAsset(address(_asset));
    }

    function test_givenDisabled_givenManagedAsset_removesAsset() public {
        _task.addAsset(address(_asset));
        _task.disable("");

        _task.removeAsset(address(_asset));

        assertFalse(_task.isAssetManaged(address(_asset)), "asset removed while disabled");
    }
}
