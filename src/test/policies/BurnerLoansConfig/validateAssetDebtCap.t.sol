// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigValidateAssetDebtCapTest is BurnerLoansTest {
    // validateAssetDebtCap
    // given asset is not configured
    //  when validating an asset debt cap
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts(address asset_, uint128 debtCapOhm_) public {
        vm.assume(asset_ != address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoansConfig.validateAssetDebtCap(asset_, debtCapOhm_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is below active asset debt
    //  when validating an asset debt cap
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint128 activeDebtOhm_, uint128 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, _defaultAssetDebtCap()));
        cap_ = uint128(bound(cap_, 0, activeDebtOhm_ - 1));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoansConfig.validateAssetDebtCap(address(usds), cap_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is above the facility's global debt cap
    //  when validating an asset debt cap
    //   then validation succeeds because the caps are independent
    function test_givenCapAboveGlobalCap_succeeds(uint128 cap_) public {
        _addDefaultUsdsAsset();
        cap_ = uint128(bound(cap_, burnerLoans.globalDebtCapOhm() + 1, type(uint128).max));

        burnerLoansConfig.validateAssetDebtCap(address(usds), cap_);
    }

    // validateAssetDebtCap
    // given active asset debt is zero
    //  when validating zero asset debt cap
    //   then it succeeds
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        _addDefaultUsdsAsset();

        burnerLoansConfig.validateAssetDebtCap(address(usds), 0);
    }

    // validateAssetDebtCap
    // given new asset debt cap equals active asset debt
    //  when validating an asset debt cap
    //   then it succeeds
    function test_givenCapEqualsActiveDebt_succeeds(uint128 activeDebtOhm_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, _defaultAssetDebtCap()));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        burnerLoansConfig.validateAssetDebtCap(address(usds), activeDebtOhm_);
    }

    // validateAssetDebtCap
    // given new asset debt cap is within bounds
    //  when validating an asset debt cap
    //   then it succeeds
    function test_givenCapWithinBounds_succeeds(uint128 activeDebtOhm_, uint128 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 0, _defaultAssetDebtCap()));
        cap_ = uint128(bound(cap_, activeDebtOhm_, type(uint128).max));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        burnerLoansConfig.validateAssetDebtCap(address(usds), cap_);
    }
}
