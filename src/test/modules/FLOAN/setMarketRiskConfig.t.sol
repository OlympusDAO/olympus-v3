// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketRiskConfigTest is FLOANTest {
    // setMarketRiskConfig
    // given the caller lacks Kernel permission
    //  when risk config is set
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketRiskConfig(marketId, 60 days, 500 days, 8_000, 15_000);
    }

    // setMarketRiskConfig
    // given invalid market ID
    //  when risk config is set
    //   then it reverts
    function test_givenInvalidMarket_reverts_fuzz(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketRiskConfig(marketId_, 60 days, 500 days, 8_000, 15_000);
    }

    // setMarketRiskConfig
    // given a Kernel-permissioned caller that is not the market manager
    //  when risk config is set
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketRiskConfig(marketId, 60 days, 500 days, 8_000, 15_000);
    }

    // setMarketRiskConfig
    // given caller is the facility but not the market manager
    //  when risk config is set
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketRiskConfig(marketId, 60 days, 500 days, 8_000, 15_000);
    }

    // setMarketRiskConfig
    // given zero term length
    //  when risk config is set
    //   then it reverts
    function test_givenZeroTermLength_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketRiskConfig(marketId, 0, 365 days, 9_000, 12_000);
    }

    // setMarketRiskConfig
    // given maturity horizon at or below term length
    //  when risk config is set
    //   then it reverts
    function test_givenInvalidMaturityHorizon_reverts_fuzz(
        uint48 termLength_,
        uint48 horizon_
    ) public {
        termLength_ = uint48(bound(termLength_, 1, type(uint48).max - 1));
        horizon_ = uint48(bound(horizon_, 0, termLength_));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketRiskConfig(marketId, termLength_, horizon_, 9_000, 12_000);
    }

    // setMarketRiskConfig
    // given collateral factor above 100 percent
    //  when risk config is set
    //   then it reverts
    function test_givenInvalidCollateralFactor_reverts_fuzz(uint16 collateralFactorBps_) public {
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 10_001, type(uint16).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketRiskConfig(marketId, 30 days, 365 days, collateralFactorBps_, 12_000);
    }

    // setMarketRiskConfig
    // given valid risk fields
    //  when the manager sets risk config
    //   then only the risk fields change
    function test_givenValidRiskFields_updatesOnlyRiskFields_fuzz(
        uint48 termLength_,
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_
    ) public {
        termLength_ = uint48(bound(termLength_, 1, type(uint48).max));
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 0, 10_000));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory before_ = floan.getMarket(marketId);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketConfigUpdated(marketId);
        vm.prank(manager);
        floan.setMarketRiskConfig(
            marketId,
            termLength_,
            type(uint48).max,
            collateralFactorBps_,
            minCollateralRatioBps_
        );

        IFLOANv1.Market memory after_ = floan.getMarket(marketId);
        assertEq(after_.termLength, termLength_, "term length");
        assertEq(after_.maxMaturityHorizon, type(uint48).max, "maturity horizon");
        assertEq(after_.collateralFactorBps, collateralFactorBps_, "collateral factor");
        assertEq(after_.minCollateralRatioBps, minCollateralRatioBps_, "minimum collateral ratio");
        assertEq(after_.collateralToken, before_.collateralToken, "collateral token");
        assertEq(after_.debtToken, before_.debtToken, "debt token");
        assertEq(after_.principalCap, before_.principalCap, "principal cap");
        assertEq(after_.baseFeeBps, before_.baseFeeBps, "base fee");
    }
}
