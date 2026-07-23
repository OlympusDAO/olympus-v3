// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetDebtCapTest is BurnerLoansTest {
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);

    // setAssetDebtCap
    // given caller is neither admin nor configurator
    //  when setAssetDebtCap is called
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        _addDefaultUsdsAsset();
        _setDefaultConfigurator();

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                caller_
            )
        );
        burnerLoansConfig.setAssetDebtCap(address(usds), 200_000e9);
    }

    // setAssetDebtCap
    // given the policy is disabled
    //  when setAssetDebtCap is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        _addDefaultUsdsAsset();
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setAssetDebtCap(address(usds), 200_000e9);
    }

    // setAssetDebtCap
    // given new asset debt cap is below active asset debt
    //  when setAssetDebtCap is called by admin
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint128 activeDebtOhm_, uint128 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, _defaultAssetDebtCap()));
        cap_ = uint128(bound(cap_, 0, activeDebtOhm_ - 1));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoansConfig.setAssetDebtCap(address(usds), cap_);
    }

    // setAssetDebtCap
    // given new asset debt cap is above the facility's global debt cap
    //  when setAssetDebtCap is called by admin
    //   then the independent market cap is still accepted
    function test_givenCapAboveGlobalCap_setsIndependentMarketCap(uint128 cap_) public {
        _addDefaultUsdsAsset();
        cap_ = uint128(bound(cap_, burnerLoans.globalDebtCapOhm() + 1, type(uint128).max));

        vm.prank(admin);
        burnerLoansConfig.setAssetDebtCap(address(usds), cap_);

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).debtCap, cap_, "asset debt cap");
    }

    // setAssetDebtCap
    // given new asset debt cap is within bounds
    //  when setAssetDebtCap is called by admin
    //   then it stores the cap
    function test_givenAdminCaller_setsCap(uint128 debtCapOhm_) public {
        _addDefaultUsdsAsset();
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        burnerLoansConfig.setAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            debtCapOhm_,
            "asset debt cap"
        );
    }

    // setAssetDebtCap
    // given active asset debt is zero
    //  when setAssetDebtCap is called with zero by admin
    //   then it stores zero as a valid capacity shutdown value
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), 0);
        burnerLoansConfig.setAssetDebtCap(address(usds), 0);

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).debtCap, 0, "asset debt cap");
    }

    // setAssetDebtCap
    // given caller is the configurator
    //  when new asset debt cap is within bounds
    //   then it stores the cap
    function test_givenConfiguratorCaller_setsCap(uint128 debtCapOhm_) public {
        _addDefaultUsdsAsset();
        _setDefaultConfigurator();
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));

        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        burnerLoansConfig.setAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            debtCapOhm_,
            "asset debt cap"
        );
    }

    // setAssetDebtCap
    // given new asset debt cap equals active asset debt
    //  when setAssetDebtCap is called by admin
    //   then it stores the cap
    function test_givenCapEqualsActiveDebt_setsCap(uint128 activeDebtOhm_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, _defaultAssetDebtCap()));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), activeDebtOhm_);
        burnerLoansConfig.setAssetDebtCap(address(usds), activeDebtOhm_);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            activeDebtOhm_,
            "asset debt cap"
        );
    }
}
