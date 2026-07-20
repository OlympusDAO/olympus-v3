// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDisableAssetTest is BurnerLoansTest {
    event AssetDisabled(address indexed asset);

    // disableAsset
    // given caller has neither admin nor burner_loans_admin role
    //  when disableAsset is called for a configured asset
    //   then it reverts
    function test_givenNonAdminOrBurnerLoansAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _addDefaultUsdsAsset();

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));
    }

    // disableAsset
    // given asset is not configured
    //  when disableAsset is called by burner_loans_admin
    //   then it reverts
    function test_givenAssetNotConfigured_reverts(address asset_) public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoansConfig.disableAsset(address(burnerLoans), asset_);
    }

    // disableAsset
    // given asset is already disabled
    //  when disableAsset is called again
    //   then it reverts
    function test_givenAlreadyDisabled_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(burnerLoansAdmin);
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotEnabled.selector, address(usds))
        );
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));
    }

    // disableAsset
    // given caller has the emergency role only
    //  when disableAsset is called for an enabled asset
    //   then it reverts
    function test_givenEmergencyCaller_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(emergency);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));
    }

    // disableAsset
    // given caller has the admin role
    //  when disableAsset is called for an enabled asset
    //   then the asset is disabled
    function test_givenAdminCaller_disablesAsset() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDisabled(address(usds));
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(burnerLoans), address(usds)).enabled,
            "enabled"
        );
    }

    // disableAsset
    // given caller has the burner_loans_admin role
    //  when disableAsset is called for an enabled asset
    //   then the asset is disabled
    function test_givenBurnerLoansAdminCaller_disablesAsset() public {
        _addDefaultUsdsAsset();

        vm.prank(burnerLoansAdmin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDisabled(address(usds));
        burnerLoansConfig.disableAsset(address(burnerLoans), address(usds));

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(burnerLoans), address(usds)).enabled,
            "enabled"
        );
    }
}
