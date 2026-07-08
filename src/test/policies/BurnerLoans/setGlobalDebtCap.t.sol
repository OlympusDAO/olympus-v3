// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetGlobalDebtCapTest is BurnerLoansTest {
    event GlobalDebtCapSet(uint256 debtCapOhm);

    // setGlobalDebtCap
    // given caller does not have the admin role
    //  when setGlobalDebtCap is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.setGlobalDebtCap(1_000_000e9);
    }

    // setGlobalDebtCap
    // given the policy is disabled
    //  when setGlobalDebtCap is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.setGlobalDebtCap(1_000_000e9);
    }

    // setGlobalDebtCap
    // given new global debt cap is below total active debt
    //  when setGlobalDebtCap is called by admin
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint256 activeDebtOhm_, uint256 cap_) public {
        activeDebtOhm_ = bound(activeDebtOhm_, 1, type(uint128).max);
        cap_ = bound(cap_, 0, activeDebtOhm_ - 1);
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, 0);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.setGlobalDebtCap(cap_);
    }

    // setGlobalDebtCap
    // given new global debt cap is below a configured asset cap
    //  when setGlobalDebtCap is called by admin
    //   then it reverts
    function test_givenCapBelowConfiguredAssetCap_reverts(uint256 cap_) public {
        _addDefaultUsdsAsset();
        uint256 assetCap = burnerLoans.getAssetConfig(address(usds)).debtCap;
        cap_ = bound(cap_, 0, assetCap - 1);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.setGlobalDebtCap(cap_);
    }

    // setGlobalDebtCap
    // given new global debt cap is within bounds
    //  when setGlobalDebtCap is called by admin
    //   then it stores the cap
    function test_givenAdminCaller_setsCap(uint256 debtCapOhm_) public {
        debtCapOhm_ = bound(debtCapOhm_, 1, type(uint128).max);

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit GlobalDebtCapSet(debtCapOhm_);
        burnerLoans.setGlobalDebtCap(debtCapOhm_);

        assertEq(burnerLoans.globalDebtCapOhm(), debtCapOhm_, "global debt cap");
    }

    // setGlobalDebtCap
    // given total active debt is zero and no configured asset cap exceeds zero
    //  when setGlobalDebtCap is called with zero by admin
    //   then it stores zero as a valid capacity shutdown value
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit GlobalDebtCapSet(0);
        burnerLoans.setGlobalDebtCap(0);

        assertEq(burnerLoans.globalDebtCapOhm(), 0, "global debt cap");
    }

    // setGlobalDebtCap
    // given new global debt cap equals total active debt
    //  when setGlobalDebtCap is called by admin
    //   then it stores the cap
    function test_givenCapEqualsActiveDebt_setsCap(uint256 activeDebtOhm_) public {
        activeDebtOhm_ = bound(activeDebtOhm_, 1, type(uint128).max);
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, 0);

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit GlobalDebtCapSet(activeDebtOhm_);
        burnerLoans.setGlobalDebtCap(activeDebtOhm_);

        assertEq(burnerLoans.globalDebtCapOhm(), activeDebtOhm_, "global debt cap");
    }
}
