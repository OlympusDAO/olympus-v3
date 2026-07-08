// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetAssetDebtCapTest is BurnerLoansTest {
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
        burnerLoans.setAssetDebtCap(address(usds), 200_000e9);
    }

    // setAssetDebtCap
    // given the policy is disabled
    //  when setAssetDebtCap is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        _addDefaultUsdsAsset();
        vm.prank(admin);
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.setAssetDebtCap(address(usds), 200_000e9);
    }

    // setAssetDebtCap
    // given new asset debt cap is below active asset debt
    //  when setAssetDebtCap is called by admin
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint256 activeDebtOhm_, uint256 cap_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = bound(activeDebtOhm_, 1, burnerLoans.globalDebtCapOhm());
        cap_ = bound(cap_, 0, activeDebtOhm_ - 1);
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.setAssetDebtCap(address(usds), cap_);
    }

    // setAssetDebtCap
    // given new asset debt cap is above the global debt cap
    //  when setAssetDebtCap is called by admin
    //   then it reverts
    function test_givenCapAboveGlobalCap_reverts(uint256 cap_) public {
        _addDefaultUsdsAsset();
        uint256 globalDebtCap = burnerLoans.globalDebtCapOhm();
        cap_ = bound(cap_, globalDebtCap + 1, type(uint128).max);

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.setAssetDebtCap(address(usds), cap_);
    }

    // setAssetDebtCap
    // given new asset debt cap is within bounds
    //  when setAssetDebtCap is called by admin
    //   then it stores the cap
    function test_givenAdminCaller_setsCap(uint256 debtCapOhm_) public {
        _addDefaultUsdsAsset();
        debtCapOhm_ = bound(debtCapOhm_, 1, burnerLoans.globalDebtCapOhm());

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        burnerLoans.setAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, debtCapOhm_, "asset debt cap");
    }

    // setAssetDebtCap
    // given active asset debt is zero
    //  when setAssetDebtCap is called with zero by admin
    //   then it stores zero as a valid capacity shutdown value
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), 0);
        burnerLoans.setAssetDebtCap(address(usds), 0);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, 0, "asset debt cap");
    }

    // setAssetDebtCap
    // given caller is the configurator
    //  when new asset debt cap is within bounds
    //   then it stores the cap
    function test_givenConfiguratorCaller_setsCap(uint256 debtCapOhm_) public {
        _addDefaultUsdsAsset();
        _setDefaultConfigurator();
        debtCapOhm_ = bound(debtCapOhm_, 1, burnerLoans.globalDebtCapOhm());

        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        burnerLoans.setAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, debtCapOhm_, "asset debt cap");
    }

    // setAssetDebtCap
    // given new asset debt cap equals active asset debt
    //  when setAssetDebtCap is called by admin
    //   then it stores the cap
    function test_givenCapEqualsActiveDebt_setsCap(uint256 activeDebtOhm_) public {
        _addDefaultUsdsAsset();
        activeDebtOhm_ = bound(activeDebtOhm_, 1, burnerLoans.globalDebtCapOhm());
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), activeDebtOhm_);
        burnerLoans.setAssetDebtCap(address(usds), activeDebtOhm_);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).debtCap,
            activeDebtOhm_,
            "asset debt cap"
        );
    }
}
