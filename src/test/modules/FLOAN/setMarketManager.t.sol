// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketManagerTest is FLOANTest {
    // setMarketManager
    // given caller without kernel permission
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketManager(marketId, otherManager);
    }

    // setMarketManager
    // given invalid market ID
    //  when setMarketManager is called
    //   then it reverts
    function test_givenInvalidMarket_reverts(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketManager(marketId_, otherManager);
    }

    // setMarketManager
    // given current manager
    //  when setMarketManager is called
    //   then it transfers configuration authority
    function test_givenCurrentManager_transfersConfigurationAuthority() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketManagerSet(marketId, manager, otherManager);
        vm.prank(manager);
        floan.setMarketManager(marketId, otherManager);

        assertEq(floan.getMarket(marketId).manager, otherManager, "manager");
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, manager)
        );
        floan.setMarketManager(marketId, manager);
        vm.prank(otherManager);
        floan.setMarketManager(marketId, manager);
        assertEq(floan.getMarket(marketId).manager, manager, "restored manager");
    }

    // setMarketManager
    // given zero manager
    //  when setMarketManager is called
    //   then it reverts
    function test_givenZeroManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketManager(marketId, address(0));
    }

    // setMarketManager
    // given caller is not the market manager
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketManager(marketId, otherManager);
    }

    // setMarketManager
    // given caller is the facility but not the market manager
    //  when setMarketManager is called
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketManager(marketId, otherManager);
    }
}
