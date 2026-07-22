// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANCreateMarketTest is FLOANTest {
    // createMarket
    // given no markets have been created
    //  when aggregate and index getters are read
    //   then they report empty state
    function test_givenNoMarkets_gettersReportEmptyState() public view {
        assertEq(floan.getMarketCount(), 0, "market count");
        assertEq(
            floan.getMarketIds(facility, collateralToken, debtToken).length,
            0,
            "market index count"
        );
    }

    // createMarket
    // given no markets have been created
    //  when market-scoped getters are read
    //   then direct record getters revert and aggregate getters return empty state
    function test_givenNoMarkets_marketGettersRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getMarket(0);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getMarketConfigData(0);
        assertEq(floan.getMarketCollateral(0), 0, "missing market collateral");
        assertEq(floan.getMarketPrincipalDue(0), 0, "missing market principal");
        assertEq(floan.getMarketInterestDue(0), 0, "missing market interest");
        assertEq(floan.getMarketPrincipalDefaulted(0), 0, "missing market defaulted principal");
        assertEq(floan.getActiveBorrowers(0).length, 0, "missing active borrowers");
        assertEq(floan.getActiveBorrowerCount(0), 0, "missing active borrower count");
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getActiveBorrowerAt(0, 0);
    }

    // createMarket
    // given caller without kernel permission
    //  when createMarket is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        _expectKernelPermissionRevert(caller_);
        floan.createMarket(
            _marketInput(_market(manager, facility, collateralToken, debtToken, 1_000e9)),
            hex""
        );
    }

    // createMarket
    // given zero collateral token
    //  when createMarket is called
    //   then it reverts
    function test_givenZeroCollateralToken_reverts() public {
        IFLOANv1.Market memory market = _market(manager, facility, address(0), debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(_marketInput(market), hex"");
    }

    // createMarket
    // given zero debt token
    //  when createMarket is called
    //   then it reverts
    function test_givenZeroDebtToken_reverts() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            address(0),
            1_000e9
        );

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(_marketInput(market), hex"");
    }

    // createMarket
    // given zero manager
    //  when createMarket is called
    //   then it reverts
    function test_givenZeroManager_reverts() public {
        IFLOANv1.Market memory market = _market(
            address(0),
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(_marketInput(market), hex"");
    }

    // createMarket
    // given zero facility
    //  when createMarket is called
    //   then it reverts
    function test_givenZeroFacility_reverts() public {
        IFLOANv1.Market memory market = _market(
            manager,
            address(0),
            collateralToken,
            debtToken,
            1_000e9
        );

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.createMarket(_marketInput(market), hex"");
    }

    // createMarket
    // given zero term length
    //  when createMarket is called
    //   then it reverts
    function test_givenZeroTermLength_reverts() public {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.termLength = 0;

        _expectInvalidConfig(market);
    }

    // createMarket
    // given maturity horizon at or below term length
    //  when createMarket is called
    //   then it reverts
    function test_givenInvalidMaturityHorizon_reverts_fuzz(
        uint48 termLength_,
        uint48 horizon_
    ) public {
        termLength_ = uint48(bound(termLength_, 1, type(uint48).max - 1));
        horizon_ = uint48(bound(horizon_, 0, termLength_));
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.termLength = termLength_;
        market.maxMaturityHorizon = horizon_;

        _expectInvalidConfig(market);
    }

    // createMarket
    // given collateral factor above 100 percent
    //  when createMarket is called
    //   then it reverts
    function test_givenInvalidCollateralFactor_reverts_fuzz(uint16 collateralFactorBps_) public {
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 10_001, type(uint16).max));
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.collateralFactorBps = collateralFactorBps_;

        _expectInvalidConfig(market);
    }

    // createMarket
    // given base fee above 100 percent
    //  when createMarket is called
    //   then it reverts
    function test_givenInvalidBaseFee_reverts_fuzz(uint16 baseFeeBps_) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 10_001, type(uint16).max));
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.baseFeeBps = baseFeeBps_;

        _expectInvalidConfig(market);
    }

    // createMarket
    // given collateral decimals above the uint256 power-of-ten limit
    //  when createMarket is called
    //   then it reverts
    function test_givenInvalidCollateralDecimals_reverts_fuzz(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 78, type(uint8).max));
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.collateralToken = address(new MockERC20("Collateral", "COL", decimals_));

        _expectInvalidConfig(market);
    }

    // createMarket
    // given debt decimals above the uint256 power-of-ten limit
    //  when createMarket is called
    //   then it reverts
    function test_givenInvalidDebtDecimals_reverts_fuzz(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 78, type(uint8).max));
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        market.debtToken = address(new MockERC20("Debt", "DEBT", decimals_));

        _expectInvalidConfig(market);
    }

    // createMarket
    // given valid market configuration
    //  when createMarket is called
    //   then it stores every field and lookup
    //   then it emits creation and origination events
    function test_storesCompleteMarketAndLookup() public {
        IFLOANv1.Market memory expected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );

        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketCreated(
            0,
            collateralToken,
            debtToken,
            manager,
            facility,
            expected.configId
        );
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketOriginationsSet(0, true);
        vm.prank(manager);
        uint32 marketId = floan.createMarket(_marketInput(expected), abi.encode(uint256(123)));

        uint256[] memory lookupIds = floan.getMarketIds(facility, collateralToken, debtToken);
        assertEq(marketId, 0, "market id");
        assertEq(floan.getMarketCount(), 1, "market count");
        _assertMarket(marketId, expected);
        assertEq(abi.decode(floan.getMarketConfigData(marketId), (uint256)), 123, "config data");
        assertEq(lookupIds.length, 1, "lookup market count");
        assertEq(lookupIds[0], marketId, "lookup market id");
    }

    // createMarket
    // given valid fuzzed standard configuration
    //  when createMarket is called
    //   then it stores every supplied field
    function test_givenValidConfiguration_storesEveryField_fuzz(
        uint128 principalCap_,
        uint48 termLength_,
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_,
        uint16 baseFeeBps_,
        bytes16 configId_,
        bytes calldata configData_
    ) public {
        termLength_ = uint48(bound(termLength_, 1, type(uint48).max));
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 0, 10_000));
        baseFeeBps_ = uint16(bound(baseFeeBps_, 0, 10_000));

        IFLOANv1.Market memory expected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            principalCap_
        );
        expected.termLength = termLength_;
        expected.maxMaturityHorizon = type(uint48).max;
        expected.collateralFactorBps = collateralFactorBps_;
        expected.minCollateralRatioBps = minCollateralRatioBps_;
        expected.baseFeeBps = baseFeeBps_;
        expected.configId = configId_;
        expected.originationsEnabled = true;

        vm.prank(manager);
        uint32 marketId = floan.createMarket(_marketInput(expected), configData_);

        _assertMarket(marketId, expected);
        assertEq(floan.getMarketConfigData(marketId), configData_, "config data");
    }

    // createMarket
    // given the maximum maturity horizon
    //  when createMarket is called
    //   then it stores the unlimited extension sentinel
    function test_givenMaximumMaturityHorizon_succeeds() public {
        IFLOANv1.Market memory expected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        expected.maxMaturityHorizon = type(uint48).max;

        vm.prank(manager);
        uint32 marketId = floan.createMarket(_marketInput(expected), hex"");

        assertEq(
            floan.getMarket(marketId).maxMaturityHorizon,
            type(uint48).max,
            "maximum maturity horizon"
        );
    }

    // createMarket
    // given duplicate facility and pair
    //  when createMarket is called
    //   then it stores both markets
    function test_givenDuplicateFacilityAndPair_storesBothMarkets() public {
        IFLOANv1.Market memory firstExpected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        IFLOANv1.Market memory secondExpected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            2_000e9
        );
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, facility, collateralToken, debtToken, 2_000e9);

        uint256[] memory lookupIds = floan.getMarketIds(facility, collateralToken, debtToken);
        _assertMarket(first, firstExpected);
        _assertMarket(second, secondExpected);
        assertEq(lookupIds.length, 2, "lookup market count");
        assertEq(lookupIds[0], first, "first lookup market id");
        assertEq(lookupIds[1], second, "second lookup market id");
        assertEq(floan.getMarketCount(), 2, "market count");
    }

    // createMarket
    // given different facility or token
    //  when createMarket is called
    //   then it stores each complete market independently
    function test_givenDifferentFacilityOrToken_succeeds() public {
        IFLOANv1.Market memory firstExpected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        IFLOANv1.Market memory secondExpected = _market(
            manager,
            otherFacility,
            collateralToken,
            debtToken,
            2_000e9
        );
        IFLOANv1.Market memory thirdExpected = _market(
            otherManager,
            facility,
            otherCollateralToken,
            otherDebtToken,
            3_000e9
        );
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, otherFacility, collateralToken, debtToken, 2_000e9);
        uint32 third = _createMarket(
            otherManager,
            facility,
            otherCollateralToken,
            otherDebtToken,
            3_000e9
        );

        _assertMarket(first, firstExpected);
        _assertMarket(second, secondExpected);
        _assertMarket(third, thirdExpected);
        uint256[] memory firstLookup = floan.getMarketIds(facility, collateralToken, debtToken);
        uint256[] memory secondLookup = floan.getMarketIds(
            otherFacility,
            collateralToken,
            debtToken
        );
        uint256[] memory thirdLookup = floan.getMarketIds(
            facility,
            otherCollateralToken,
            otherDebtToken
        );
        assertEq(firstLookup.length, 1, "first lookup count");
        assertEq(firstLookup[0], first, "first lookup market");
        assertEq(secondLookup.length, 1, "second lookup count");
        assertEq(secondLookup[0], second, "second lookup market");
        assertEq(thirdLookup.length, 1, "third lookup count");
        assertEq(thirdLookup[0], third, "third lookup market");
    }

    // createMarket
    // given the same address is manager and facility
    //  when createMarket is called
    //   then it can configure and service the market
    function test_givenManagerIsFacility_supportsBothAuthorities() public {
        IFLOANv1.Market memory expected = _market(
            manager,
            manager,
            collateralToken,
            debtToken,
            1_000e9
        );
        vm.prank(manager);
        uint32 marketId = floan.createMarket(_marketInput(expected), hex"");

        vm.startPrank(manager);
        floan.setMarketBaseFee(marketId, 200);
        uint64 positionId = floan.createPosition(marketId, borrower);
        vm.stopPrank();

        expected.baseFeeBps = 200;
        _assertMarket(marketId, expected);
        assertEq(floan.getPosition(positionId).borrower, borrower, "position borrower");
    }

    function _expectInvalidConfig(IFLOANv1.Market memory market_) internal {
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.createMarket(_marketInput(market_), hex"");
        assertEq(floan.getMarketCount(), 0, "market ID not consumed");
    }
}
