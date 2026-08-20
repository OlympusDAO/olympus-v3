// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANAddCollateralTest is FLOANTest {
    uint32 internal _marketId;
    uint64 internal _positionId;

    modifier givenMarketAndPositionAreCreated() {
        _marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _positionId = _createPosition(_marketId, facility, borrower);
        _;
    }

    // addCollateral
    // given caller without kernel permission
    //  when addCollateral is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(
        address caller_
    ) public givenMarketAndPositionAreCreated {
        _expectKernelPermissionRevert(caller_);
        floan.addCollateral(_positionId, 1);
    }

    // addCollateral
    // given valid amount
    //  when addCollateral is called
    //   then it updates only collateral
    function test_givenValidAmount_updatesOnlyCollateral_fuzz(
        uint128 amount_
    ) public givenMarketAndPositionAreCreated {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));

        vm.prank(facility);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(_positionId, amount_);
        uint128 collateral = floan.addCollateral(_positionId, amount_);

        IFLOANv1.Position memory position = floan.getPosition(_positionId);
        assertEq(collateral, amount_, "returned collateral");
        assertEq(position.collateral, amount_, "stored collateral");
        assertEq(floan.getMarketCollateral(_marketId), amount_, "market collateral");
        assertEq(position.principalDue, 0, "principal unchanged");
        assertEq(position.maturity, 0, "maturity unchanged");
    }

    // addCollateral
    // given a position whose previous episode defaulted
    //  when addCollateral is called
    //   then it starts collateral for a reusable position
    function test_givenDefaultedPosition_addsCollateralForNewEpisode() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.startPrank(facility);
        floan.defaultPosition(positionId);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(positionId, 1);
        uint128 collateral = floan.addCollateral(positionId, 1);
        vm.stopPrank();

        assertEq(collateral, 1, "new episode collateral");
        assertEq(floan.getPosition(positionId).collateral, 1, "stored collateral");
        assertEq(floan.getPositionCount(), 1, "position ID reused");
    }

    // addCollateral
    // given market originations are disabled
    //  when addCollateral is called
    //   then it reverts without changing collateral
    function test_givenOriginationsDisabled_revertsWithoutStateChange()
        public
        givenMarketAndPositionAreCreated
    {
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(_marketId, false);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_OriginationsDisabled.selector, _marketId)
        );
        floan.addCollateral(_positionId, 1);

        assertEq(floan.getPosition(_positionId).collateral, 0, "position collateral unchanged");
        assertEq(floan.getMarketCollateral(_marketId), 0, "market collateral unchanged");
    }

    // addCollateral
    // given multiple positions whose collateral exceeds uint128 in aggregate
    //  when collateral is added to each position
    //   then the market getter returns the full uint256 aggregate
    function test_givenMultiplePositions_aggregatesBeyondUint128() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 firstPositionId = _createPosition(marketId, facility, borrower);
        uint64 secondPositionId = _createPosition(marketId, facility, otherBorrower);

        vm.startPrank(facility);
        floan.addCollateral(firstPositionId, type(uint128).max);
        floan.addCollateral(secondPositionId, type(uint128).max);
        vm.stopPrank();

        assertEq(
            floan.getMarketCollateral(marketId),
            uint256(type(uint128).max) * 2,
            "market collateral"
        );
    }

    // addCollateral
    // given zero amount
    //  when addCollateral is called
    //   then it reverts
    function test_givenZeroAmount_reverts() public givenMarketAndPositionAreCreated {
        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.addCollateral(_positionId, 0);
    }

    // addCollateral
    // given invalid position id
    //  when addCollateral is called
    //   then it reverts
    function test_givenInvalidPositionId_reverts_fuzz(uint64 positionId_) public {
        positionId_ = uint64(bound(positionId_, floan.getPositionCount(), type(uint64).max));
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionId_)
        );
        floan.addCollateral(positionId_, 1);
    }

    // addCollateral
    // given caller is not the position market facility
    //  when addCollateral is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts()
        public
        givenMarketAndPositionAreCreated
    {
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, _marketId, otherFacility)
        );
        floan.addCollateral(_positionId, 1);
    }

    // addCollateral
    // given caller is the position market manager but not its facility
    //  when addCollateral is called
    //   then it reverts
    function test_givenCallerIsPositionMarketManager_reverts()
        public
        givenMarketAndPositionAreCreated
    {
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, _marketId, manager)
        );
        floan.addCollateral(_positionId, 1);
    }
}
