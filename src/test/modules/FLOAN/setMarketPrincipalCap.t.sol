// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketPrincipalCapTest is FLOANTest {
    // setMarketPrincipalCap
    // given the caller lacks Kernel permission
    //  when the principal cap is set
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketPrincipalCap(marketId, 2_000e9);
    }

    // setMarketPrincipalCap
    // given invalid market ID
    //  when the principal cap is set
    //   then it reverts
    function test_givenInvalidMarket_reverts_fuzz(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketPrincipalCap(marketId_, 2_000e9);
    }

    // setMarketPrincipalCap
    // given a Kernel-permissioned caller that is not the market manager
    //  when the principal cap is set
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketPrincipalCap(marketId, 2_000e9);
    }

    // setMarketPrincipalCap
    // given caller is the facility but not the market manager
    //  when the principal cap is set
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketPrincipalCap(marketId, 2_000e9);
    }

    // setMarketPrincipalCap
    // given live principal
    //  when the cap is below live principal
    //   then it reverts without changing the cap or principal
    function test_givenCapBelowLivePrincipal_reverts_fuzz(uint128 reduction_) public {
        reduction_ = uint128(bound(reduction_, 1, 100e9));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketPrincipalCap(marketId, 100e9 - reduction_);

        assertEq(floan.getMarket(marketId).principalCap, 1_000e9, "principal cap unchanged");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "live principal unchanged");
    }

    // setMarketPrincipalCap
    // given live principal
    //  when the manager sets the cap at or above live principal
    //   then only the cap changes
    function test_givenCapAtOrAboveLivePrincipal_updatesOnlyCap_fuzz(uint128 surplus_) public {
        surplus_ = uint128(bound(surplus_, 0, type(uint128).max - 100e9));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint128 cap = 100e9 + surplus_;

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketConfigUpdated(marketId);
        vm.prank(manager);
        floan.setMarketPrincipalCap(marketId, cap);

        assertEq(floan.getMarket(marketId).principalCap, cap, "principal cap");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "live principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
    }
}
