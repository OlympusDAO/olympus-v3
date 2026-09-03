// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerAddAssetTest is BurnerLoansSeizerTest {
    // addAsset
    // given admin
    //  when an asset is added
    //   then it adds the managed asset and updates its getters
    function test_givenAdmin_addsManagedAsset() public {
        vm.prank(admin);
        seizer.addAsset(assetOne);

        assertTrue(seizer.isAssetManaged(assetOne), "asset managed");
        assertEq(seizer.getAssets(), _single(assetOne), "managed assets");
    }

    // addAsset
    // given duplicate asset
    //  when addAsset is called
    //   then it reverts
    function test_givenDuplicateAsset_reverts() public {
        vm.startPrank(admin);
        seizer.addAsset(assetOne);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_AssetAlreadyManaged.selector,
                assetOne
            )
        );
        seizer.addAsset(assetOne);
        vm.stopPrank();
    }

    // addAsset
    // given unauthorized caller
    //  when addAsset is called
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        seizer.addAsset(assetOne);
    }

    // addAsset
    // given the seizer is disabled
    //  when admin adds an asset
    //   then configuration remains available while execution is paused
    function test_givenDisabled_addsManagedAsset() public {
        vm.prank(admin);
        seizer.disable("");

        vm.prank(admin);
        seizer.addAsset(assetOne);

        assertTrue(seizer.isAssetManaged(assetOne), "asset managed while disabled");
    }
}
