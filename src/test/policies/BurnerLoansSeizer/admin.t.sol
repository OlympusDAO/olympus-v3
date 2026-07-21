// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerAdminTest is BurnerLoansSeizerTest {
    function test_givenAdmin_addsAndRemovesManagedAsset() public {
        vm.startPrank(admin);
        seizer.addAsset(assetOne);
        assertTrue(seizer.isAssetManaged(assetOne), "asset managed");
        assertEq(seizer.getAssets(), _single(assetOne), "managed assets");

        seizer.removeAsset(assetOne);
        vm.stopPrank();

        assertFalse(seizer.isAssetManaged(assetOne), "asset removed");
        assertEq(seizer.getAssets().length, 0, "managed asset count");
    }

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

    function test_givenMissingAsset_removeReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_AssetNotManaged.selector,
                assetOne
            )
        );
        vm.prank(admin);
        seizer.removeAsset(assetOne);
    }

    function test_givenAdminOrBurnerLoansAdmin_setsScanLimits() public {
        vm.prank(admin);
        seizer.setScanLimits(20, 10);
        assertEq(seizer.maxBorrowersToCheck(), 20, "admin check limit");
        assertEq(seizer.maxBorrowersToSeize(), 10, "admin seize limit");

        vm.prank(burnerLoansAdmin);
        seizer.setScanLimits(30, 15);
        assertEq(seizer.maxBorrowersToCheck(), 30, "operator check limit");
        assertEq(seizer.maxBorrowersToSeize(), 15, "operator seize limit");
    }

    function testFuzz_givenInvalidScanLimits_reverts(uint16 checkLimit_, uint8 seizeLimit_) public {
        bool invalid = checkLimit_ == 0 ||
            checkLimit_ > seizer.MAX_BORROWERS_TO_CHECK() ||
            seizeLimit_ == 0 ||
            seizeLimit_ > seizer.MAX_BORROWERS_TO_SEIZE() ||
            seizeLimit_ > checkLimit_;
        vm.assume(invalid);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidScanLimits.selector,
                checkLimit_,
                seizeLimit_
            )
        );
        vm.prank(admin);
        seizer.setScanLimits(checkLimit_, seizeLimit_);
    }

    function testFuzz_givenUnauthorizedCaller_cannotChangeConfiguration(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);

        vm.startPrank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        seizer.setScanLimits(20, 10);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        seizer.addAsset(assetOne);
        vm.stopPrank();
    }
}
