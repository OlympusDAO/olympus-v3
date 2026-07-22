// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANImportMarketTest is FLOANTest {
    // importMarket
    // given the caller lacks Kernel permission
    //  when a market is imported
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        _expectKernelPermissionRevert(caller_);
        floan.importMarket(
            0,
            _marketInput(_market(manager, facility, collateralToken, debtToken, 1_000e9)),
            hex"",
            true
        );
    }

    // importMarket
    // given the imported ID is not the next contiguous market ID
    //  when a market is imported
    //   then it reverts
    function test_givenNonContiguousId_reverts_fuzz(uint32 marketId_) public {
        marketId_ = uint32(bound(marketId_, 1, type(uint32).max));
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidImportId.selector, 0, marketId_)
        );
        floan.importMarket(
            marketId_,
            _marketInput(_market(manager, facility, collateralToken, debtToken, 1_000e9)),
            hex"",
            true
        );
    }

    // importMarket
    // given the collateral token is zero
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenZeroCollateralToken_reverts() public {
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            address(0),
            debtToken,
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_ZeroAddress.selector);
    }

    // importMarket
    // given the debt token is zero
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenZeroDebtToken_reverts() public {
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            address(0),
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_ZeroAddress.selector);
    }

    // importMarket
    // given the manager is zero
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenZeroManager_reverts() public {
        IFLOANv1.Market memory imported = _market(
            address(0),
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_ZeroAddress.selector);
    }

    // importMarket
    // given the facility is zero
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenZeroFacility_reverts() public {
        IFLOANv1.Market memory imported = _market(
            manager,
            address(0),
            collateralToken,
            debtToken,
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_ZeroAddress.selector);
    }

    // importMarket
    // given the base fee exceeds 100 percent
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidBaseFee_reverts_fuzz(uint16 baseFeeBps_) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 10_001, type(uint16).max));
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        imported.baseFeeBps = baseFeeBps_;
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given the term length is zero
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenZeroTermLength_reverts() public {
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        imported.termLength = 0;
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given a finite maturity horizon at or below the term
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidMaturityHorizon_reverts_fuzz(
        uint48 termLength_,
        uint48 horizon_
    ) public {
        termLength_ = uint48(bound(termLength_, 1, type(uint48).max - 1));
        horizon_ = uint48(bound(horizon_, 0, termLength_));
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        imported.termLength = termLength_;
        imported.maxMaturityHorizon = horizon_;
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given the collateral factor exceeds 100 percent
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidRiskConfiguration_reverts_fuzz(uint16 collateralFactorBps_) public {
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 10_001, type(uint16).max));
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        imported.collateralFactorBps = collateralFactorBps_;
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given collateral token decimals exceed the supported power-of-ten range
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidCollateralDecimals_reverts_fuzz(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 78, type(uint8).max));
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            address(new MockERC20("Collateral", "COL", decimals_)),
            debtToken,
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given debt token decimals exceed the supported power-of-ten range
    //  when a market is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidDebtDecimals_reverts_fuzz(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 78, type(uint8).max));
        IFLOANv1.Market memory imported = _market(
            manager,
            facility,
            collateralToken,
            address(new MockERC20("Debt", "DEBT", decimals_)),
            1_000e9
        );
        _expectImportRevert(imported, IFLOANv1.FLOAN_InvalidConfig.selector);
    }

    // importMarket
    // given an existing market
    //  when the following contiguous market is imported
    //   then it preserves the imported ID
    //   then it stores configuration and lookup indexes
    function test_givenExistingMarket_preservesContiguousIdAndIndexes() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory imported = _market(
            otherManager,
            otherFacility,
            otherCollateralToken,
            otherDebtToken,
            2_000e9
        );
        imported.originationsEnabled = false;

        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketCreated(
            1,
            imported.collateralToken,
            imported.debtToken,
            imported.manager,
            imported.facility,
            imported.configId
        );
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketOriginationsSet(1, imported.originationsEnabled);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketImported(1);
        vm.prank(manager);
        floan.importMarket(
            1,
            _marketInput(imported),
            abi.encode(uint256(456)),
            imported.originationsEnabled
        );

        IFLOANv1.Market memory stored = floan.getMarket(1);
        uint256[] memory lookupIds = floan.getMarketIds(
            otherFacility,
            otherCollateralToken,
            otherDebtToken
        );
        assertEq(floan.getMarketCount(), 2, "market count");
        _assertMarket(1, imported);
        assertEq(abi.encode(stored), abi.encode(imported), "complete market");
        assertEq(abi.decode(floan.getMarketConfigData(1), (uint256)), 456, "config data");
        assertEq(lookupIds.length, 1, "lookup count");
        assertEq(lookupIds[0], 1, "lookup market id");
    }

    function _expectImportRevert(IFLOANv1.Market memory imported_, bytes4 selector_) internal {
        vm.prank(manager);
        vm.expectRevert(selector_);
        floan.importMarket(0, _marketInput(imported_), hex"", imported_.originationsEnabled);
        assertEq(floan.getMarketCount(), 0, "market ID not consumed");
    }
}
