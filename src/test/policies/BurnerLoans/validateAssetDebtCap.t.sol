// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansValidateAssetDebtCapTest is BurnerLoansTest {
    // validateAssetDebtCap
    // given asset is not configured
    //  when validating an asset debt cap
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts(address asset_, uint256 debtCapOhm_) public {
        vm.assume(asset_ != address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoans.validateAssetDebtCap(asset_, debtCapOhm_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is below active asset debt
    //  when validating an asset debt cap
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint256 activeDebtOhm_, uint256 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = bound(activeDebtOhm_, 1, burnerLoans.globalDebtCapOhm());
        cap_ = bound(cap_, 0, activeDebtOhm_ - 1);
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.validateAssetDebtCap(address(usds), cap_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is above the global debt cap
    //  when validating an asset debt cap
    //   then it reverts
    function test_givenCapAboveGlobalCap_reverts(uint256 cap_) public {
        _addDefaultUsdsAsset();
        uint256 globalDebtCap = burnerLoans.globalDebtCapOhm();
        cap_ = bound(cap_, globalDebtCap + 1, type(uint128).max);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.validateAssetDebtCap(address(usds), cap_);
    }

    // validateAssetDebtCap
    // given active asset debt is zero
    //  when validating zero asset debt cap
    //   then it succeeds
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        _addDefaultUsdsAsset();

        burnerLoans.validateAssetDebtCap(address(usds), 0);
    }

    // validateAssetDebtCap
    // given new asset debt cap equals active asset debt
    //  when validating an asset debt cap
    //   then it succeeds
    function test_givenCapEqualsActiveDebt_succeeds(uint256 activeDebtOhm_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = bound(activeDebtOhm_, 1, burnerLoans.globalDebtCapOhm());
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        burnerLoans.validateAssetDebtCap(address(usds), activeDebtOhm_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is within bounds
    //  when validating an asset debt cap
    //   then it succeeds
    function test_givenCapWithinBounds_succeeds(uint256 activeDebtOhm_, uint256 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = bound(activeDebtOhm_, 0, burnerLoans.globalDebtCapOhm());
        cap_ = bound(cap_, activeDebtOhm_, burnerLoans.globalDebtCapOhm());
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        burnerLoans.validateAssetDebtCap(address(usds), cap_);
    }
}
