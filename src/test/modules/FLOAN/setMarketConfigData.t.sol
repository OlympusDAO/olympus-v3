// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketConfigDataTest is FLOANTest {
    // setMarketConfigData
    // given the caller lacks Kernel permission
    //  when opaque config is set
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketConfigData(marketId, hex"1234");
    }

    // setMarketConfigData
    // given invalid market ID
    //  when opaque config is set
    //   then it reverts
    function test_givenInvalidMarket_reverts(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketConfigData(marketId_, hex"1234");
    }

    // setMarketConfigData
    // given the caller is not the market manager
    //  when opaque config is set
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketConfigData(marketId, hex"1234");
    }

    // setMarketConfigData
    // given caller is the facility but not the market manager
    //  when opaque config is set
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketConfigData(marketId, hex"1234");
    }

    // setMarketConfigData
    // given a market
    //  when the manager sets arbitrary opaque config
    //   then only opaque config changes
    function test_givenArbitraryData_updatesOnlyOpaqueConfig(bytes calldata configData_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        bytes32 marketBefore = keccak256(abi.encode(floan.getMarket(marketId)));

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketConfigUpdated(marketId);
        vm.prank(manager);
        floan.setMarketConfigData(marketId, configData_);

        assertEq(floan.getMarketConfigData(marketId), configData_, "opaque config");
        assertEq(
            keccak256(abi.encode(floan.getMarket(marketId))),
            marketBefore,
            "market unchanged"
        );
    }
}
