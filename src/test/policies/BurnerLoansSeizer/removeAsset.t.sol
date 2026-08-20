// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerRemoveAssetTest is BurnerLoansSeizerTest {
    // removeAsset
    // given a managed asset and admin
    //  when the asset is removed
    //   then it removes the asset from its getters
    function test_givenManagedAssetAndAdmin_removesAsset() public {
        vm.startPrank(admin);
        seizer.addAsset(assetOne);
        seizer.removeAsset(assetOne);
        vm.stopPrank();

        assertFalse(seizer.isAssetManaged(assetOne), "asset removed");
        assertEq(seizer.getAssets().length, 0, "managed asset count");
    }

    // removeAsset
    // given missing asset
    //  when removeAsset is called
    //   then it reverts
    function test_givenMissingAsset_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_AssetNotManaged.selector,
                assetOne
            )
        );
        vm.prank(admin);
        seizer.removeAsset(assetOne);
    }

    // removeAsset
    // given unauthorized caller
    //  when removeAsset is called
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        seizer.addAsset(assetOne);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        seizer.removeAsset(assetOne);
    }
}
