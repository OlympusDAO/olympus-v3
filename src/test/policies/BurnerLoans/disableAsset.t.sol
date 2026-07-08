// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDisableAssetTest is BurnerLoansTest {
    event AssetDisabled(address indexed asset);

    // disableAsset
    // given caller has neither admin nor emergency role
    //  when disableAsset is called for a configured asset
    //   then it reverts
    function test_givenNonEmergencyOrAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        _addDefaultUsdsAsset();

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.disableAsset(address(usds));
    }

    // disableAsset
    // given asset is not configured
    //  when disableAsset is called by emergency
    //   then it reverts
    function test_givenAssetNotConfigured_reverts(address asset_) public {
        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoans.disableAsset(asset_);
    }

    // disableAsset
    // given asset is already disabled
    //  when disableAsset is called again
    //   then it reverts and preserves the original disabled timestamp
    function test_givenAlreadyDisabled_revertsAndDoesNotRefreshGraceWindow() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.warp(2345);
        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotEnabled.selector, address(usds))
        );
        burnerLoans.disableAsset(address(usds));

        assertEq(burnerLoans.assetDisabledAt(address(usds)), 1234, "disabled at");
    }

    // disableAsset
    // given caller has the emergency role
    //  when disableAsset is called for an enabled asset
    //   then the asset is disabled and timestamp is recorded
    function test_givenEmergencyCaller_disablesAssetAndRecordsTimestamp() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDisabled(address(usds));
        burnerLoans.disableAsset(address(usds));

        assertFalse(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 1234, "disabled at");
    }
}
