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
        vm.assume(caller_ != admin && caller_ != address(burnerLoans));

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
    function test_givenCapBelowActiveDebt_reverts(uint128 activeDebtOhm_, uint128 cap_) public {
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, type(uint128).max));
        cap_ = uint128(bound(cap_, 0, activeDebtOhm_ - 1));
        _setOtherMarketDebtForTest(activeDebtOhm_);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.setGlobalDebtCap(cap_);
    }

    // setGlobalDebtCap
    // given new global debt cap is below a configured market cap but active debt is zero
    //  when setGlobalDebtCap is called by admin
    //   then it succeeds because configured capacity is not outstanding principal
    function test_givenCapBelowConfiguredAssetCap_setsIndependentFacilityCap(uint128 cap_) public {
        _addDefaultUsdsAsset();
        uint128 assetCap = uint128(burnerLoansConfig.getAssetConfig(address(usds)).debtCap);
        cap_ = uint128(bound(cap_, 0, assetCap - 1));

        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(cap_);

        assertEq(burnerLoans.globalDebtCapOhm(), cap_, "global debt cap");
    }

    // setGlobalDebtCap
    // given new global debt cap is within bounds
    //  when setGlobalDebtCap is called by admin
    //   then it stores the cap
    function test_givenAdminCaller_setsCap(uint128 debtCapOhm_) public {
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit GlobalDebtCapSet(debtCapOhm_);
        burnerLoans.setGlobalDebtCap(debtCapOhm_);

        assertEq(burnerLoans.globalDebtCapOhm(), debtCapOhm_, "global debt cap");
        assertEq(mintr.mintApproval(address(burnerLoans)), debtCapOhm_, "mint approval");
    }

    // setGlobalDebtCap
    // given an existing global cap
    //  when the cap is increased and then decreased
    //   then the remaining MINTR approval changes only by each cap delta
    function test_givenExistingCap_reconcilesMintApprovalByCapDelta() public {
        vm.startPrank(admin);
        burnerLoans.setGlobalDebtCap(1_000e9);
        burnerLoans.setGlobalDebtCap(1_500e9);
        assertEq(mintr.mintApproval(address(burnerLoans)), 1_500e9, "increased approval");

        burnerLoans.setGlobalDebtCap(750e9);
        vm.stopPrank();

        assertEq(mintr.mintApproval(address(burnerLoans)), 750e9, "decreased approval");
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
    function test_givenCapEqualsActiveDebt_setsCap(uint128 activeDebtOhm_) public {
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, type(uint128).max));
        _setOtherMarketDebtForTest(activeDebtOhm_);

        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit GlobalDebtCapSet(activeDebtOhm_);
        burnerLoans.setGlobalDebtCap(activeDebtOhm_);

        assertEq(burnerLoans.globalDebtCapOhm(), activeDebtOhm_, "global debt cap");
    }
}
