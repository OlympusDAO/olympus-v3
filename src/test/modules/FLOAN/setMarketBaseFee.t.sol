// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketBaseFeeTest is FLOANTest {
    // setMarketBaseFee
    // given the caller lacks Kernel permission
    //  when the base fee is set
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketBaseFee(marketId, 200);
    }

    // setMarketBaseFee
    // given invalid market ID
    //  when the base fee is set
    //   then it reverts
    function test_givenInvalidMarket_reverts_fuzz(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketBaseFee(marketId_, 200);
    }

    // setMarketBaseFee
    // given the caller is not the market manager
    //  when the base fee is set
    //   then it reverts
    function test_givenCallerIsNotMarketManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketBaseFee(marketId, 200);
    }

    // setMarketBaseFee
    // given caller is the facility but not the market manager
    //  when the base fee is set
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketBaseFee(marketId, 200);
    }

    // setMarketBaseFee
    // given the fee is above 100 percent
    //  when the base fee is set
    //   then it reverts
    function test_givenFeeAboveMaximum_reverts_fuzz(uint16 fee_) public {
        fee_ = uint16(bound(fee_, 10_001, type(uint16).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.setMarketBaseFee(marketId, fee_);
    }

    // setMarketBaseFee
    // given the fee is valid
    //  when the manager sets the base fee
    //   then only the base fee changes
    function test_givenValidFee_updatesOnlyBaseFee_fuzz(uint16 fee_) public {
        fee_ = uint16(bound(fee_, 0, 10_000));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory marketBefore = floan.getMarket(marketId);
        bytes32 configDataBefore = keccak256(abi.encode(floan.getMarketConfigData(marketId)));

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketConfigUpdated(marketId);
        vm.prank(manager);
        floan.setMarketBaseFee(marketId, fee_);

        marketBefore.baseFeeBps = fee_;
        _assertMarket(marketId, marketBefore);
        assertEq(
            keccak256(abi.encode(floan.getMarketConfigData(marketId))),
            configDataBefore,
            "opaque config"
        );
    }
}
