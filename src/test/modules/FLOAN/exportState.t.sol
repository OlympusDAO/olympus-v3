// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANExportStateTest is FLOANTest {
    IFLOANv1.Market[] internal _expectedMarkets;
    bytes[] internal _expectedMarketConfigData;
    IFLOANv1.Position[] internal _expectedPositions;
    uint256[] internal _expectedPrincipalDefaulted;

    address[] internal _knownFacilities;
    address[] internal _knownCollateralTokens;
    address[] internal _knownDebtTokens;
    address[] internal _knownBorrowers;

    address internal _thirdBorrower;

    // export state
    // given the ledger is empty
    //  when counts and the first out-of-range records are read
    //   then counts are zero and record getters revert with record-specific errors
    function test_givenEmptyLedger_reportsZeroCountsAndCountBoundReverts() public {
        uint32 marketCount = floan.getMarketCount();
        uint64 positionCount = floan.getPositionCount();
        assertEq(marketCount, 0, "empty market count");
        assertEq(positionCount, 0, "empty position count");

        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getMarket(marketCount);

        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, 0));
        floan.getPosition(positionCount);
    }

    // export state
    // given a ledger with multiple markets, facilities, tokens, borrowers, and position states
    //  when canonical records are enumerated sequentially
    //   then every field is recoverable and every live index and aggregate is reconstructable
    function test_givenDiverseLedger_whenSequentiallyExported_reconstructsCurrentState() public {
        _buildDiverseLedger();

        _assertSequentialMarketExport();
        _assertSequentialPositionExport();
        _assertMarketIndexesReconstructed();
        _assertPositionIndexesReconstructed();
        _assertActiveBorrowersReconstructed();
        _assertAccountingReconstructed();

        uint32 marketCount = floan.getMarketCount();
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketCount));
        floan.getMarket(marketCount);

        uint64 positionCount = floan.getPositionCount();
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionCount)
        );
        floan.getPosition(positionCount);
    }

    // export state
    // given one position is repeatedly defaulted and reused at the maximum principal scale
    //  when cumulative default history is exported
    //   then the full uint256 total remains readable after the current record is cleared
    function test_givenRepeatedMaximumScaleDefaults_preservesFullCumulativeHistory() public {
        uint32 marketId = _createMarket(
            manager,
            facility,
            collateralToken,
            debtToken,
            type(uint128).max
        );
        uint64 positionId = _createPosition(marketId, facility, borrower);
        uint48 maturity = uint48(block.timestamp + 30 days);

        vm.startPrank(facility);
        floan.increaseDebt(positionId, type(uint128).max, 0, maturity);
        floan.defaultPosition(positionId);
        floan.increaseDebt(positionId, type(uint128).max, 0, maturity);
        floan.defaultPosition(positionId);
        vm.stopPrank();

        // Each episode defaults type(uint128).max principal (9 debt-token decimals).
        // Two cleared episodes sum in uint256 storage to a value above uint128.
        uint256 expectedDefaulted = uint256(type(uint128).max) * 2;
        assertGt(expectedDefaulted, type(uint128).max, "default history exceeds uint128");
        assertEq(
            floan.getMarketPrincipalDefaulted(marketId),
            expectedDefaulted,
            "full cumulative principal defaulted"
        );
        _assertPosition(
            positionId,
            IFLOANv1.Position({
                borrower: borrower,
                marketId: marketId,
                collateral: 0,
                principalDrawn: 0,
                principalDue: 0,
                interestDue: 0,
                maturity: 0,
                lastBorrowBlock: 0
            })
        );
    }

    function _buildDiverseLedger() internal {
        _thirdBorrower = makeAddr("thirdBorrower");
        _knownFacilities.push(facility);
        _knownFacilities.push(otherFacility);
        _knownCollateralTokens.push(collateralToken);
        _knownCollateralTokens.push(otherCollateralToken);
        _knownDebtTokens.push(debtToken);
        _knownDebtTokens.push(otherDebtToken);
        _knownBorrowers.push(borrower);
        _knownBorrowers.push(otherBorrower);
        _knownBorrowers.push(_thirdBorrower);

        _buildMarkets();
        _buildPositions();

        vm.prank(manager);
        floan.setMarketFacility(3, otherFacility);
        _expectedMarkets[3].facility = otherFacility;

        vm.prank(otherManager);
        floan.setMarketOriginationsEnabled(1, false);
        _expectedMarkets[1].originationsEnabled = false;
    }

    function _buildMarkets() internal {
        IFLOANv1.Market memory market = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000_000e9
        );
        market.configId = 0x6275726e65722d763100000000000000;
        market.termLength = 14 days;
        market.maxMaturityHorizon = 120 days;
        market.maxLtvBps = 8_000;
        market.baseFeeBps = 75;
        _createExpectedMarket(market, abi.encode(uint32(7), address(0x1234)));

        market = _market(otherManager, facility, collateralToken, debtToken, 500_000e9);
        market.configId = 0x656d7074792d636f6e66696700000000;
        market.termLength = 21 days;
        market.maxMaturityHorizon = 180 days;
        market.maxLtvBps = 7_500;
        market.baseFeeBps = 0;
        _createExpectedMarket(market, hex"");

        market = _market(
            otherManager,
            otherFacility,
            otherCollateralToken,
            otherDebtToken,
            1_000_000e18
        );
        market.configId = 0x6f746865722d646562742d7632000000;
        market.termLength = 30 days;
        market.maxMaturityHorizon = 365 days;
        market.maxLtvBps = 6_500;
        market.baseFeeBps = 125;
        _createExpectedMarket(market, abi.encode("schema-2", uint256(42)));

        market = _market(manager, facility, otherCollateralToken, debtToken, 250_000e9);
        market.configId = 0x726f74617461626c652d763100000000;
        market.termLength = 7 days;
        market.maxMaturityHorizon = 60 days;
        market.maxLtvBps = 9_500;
        market.baseFeeBps = 10;
        _createExpectedMarket(market, hex"deadbeef");
    }

    function _buildPositions() internal {
        uint48 shortMaturity = uint48(block.timestamp + 15 days);
        uint48 longMaturity = uint48(block.timestamp + 45 days);

        uint64 positionId = _createExpectedPosition(0, facility, borrower);
        _addExpectedCollateral(positionId, facility, 120e18);
        _increaseExpectedDebt(positionId, facility, 100e9, 5e9, shortMaturity);

        IFLOANv1.Position memory defaultedEpisode = _expectedPositions[positionId];
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtDecreased(positionId, 0, 0);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionCollateralChanged(positionId, 0);
        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.PositionDefaulted(
            positionId,
            defaultedEpisode.marketId,
            defaultedEpisode.borrower,
            defaultedEpisode.principalDrawn,
            defaultedEpisode.principalDue,
            defaultedEpisode.interestDue,
            defaultedEpisode.collateral,
            defaultedEpisode.maturity,
            defaultedEpisode.lastBorrowBlock
        );
        vm.prank(facility);
        floan.defaultPosition(positionId);
        _expectedPrincipalDefaulted[0] += defaultedEpisode.principalDue;
        _clearDefaultedPosition(positionId);

        _addExpectedCollateral(positionId, facility, 180e18);
        _increaseExpectedDebt(positionId, facility, 80e9, 8e9, longMaturity);

        positionId = _createExpectedPosition(0, facility, borrower);
        _addExpectedCollateral(positionId, facility, 50e18);
        _increaseExpectedDebt(positionId, facility, 50e9, 2e9, longMaturity);

        positionId = _createExpectedPosition(0, facility, otherBorrower);
        _addExpectedCollateral(positionId, facility, 60e18);
        _increaseExpectedDebt(positionId, facility, 40e9, 4e9, longMaturity);

        positionId = _createExpectedPosition(1, facility, borrower);
        _addExpectedCollateral(positionId, facility, 500e18);
        _increaseExpectedDebt(positionId, facility, 20e9, 3e9, shortMaturity);
        _decreaseExpectedDebt(positionId, facility, 20e9, 3e9);

        positionId = _createExpectedPosition(2, otherFacility, borrower);
        _addExpectedCollateral(positionId, otherFacility, 250e6);
        _increaseExpectedDebt(positionId, otherFacility, 3e18, 3e17, longMaturity);

        positionId = _createExpectedPosition(2, otherFacility, _thirdBorrower);
        _addExpectedCollateral(positionId, otherFacility, 350e6);
        _increaseExpectedDebt(positionId, otherFacility, 4e18, 4e17, longMaturity);

        positionId = _createExpectedPosition(3, facility, otherBorrower);
        _addExpectedCollateral(positionId, facility, 120e6);
        _increaseExpectedDebt(positionId, facility, 70e9, 7e9, shortMaturity);
        _decreaseExpectedDebt(positionId, facility, 70e9, 0);
    }

    function _createExpectedMarket(
        IFLOANv1.Market memory market_,
        bytes memory configData_
    ) internal {
        vm.prank(market_.manager);
        uint32 marketId = floan.createMarket(_marketInput(market_), configData_);
        assertEq(marketId, _expectedMarkets.length, "sequential fixture market ID");
        _expectedMarkets.push(market_);
        _expectedMarketConfigData.push(configData_);
        _expectedPrincipalDefaulted.push(0);
    }

    function _createExpectedPosition(
        uint32 marketId_,
        address facility_,
        address borrower_
    ) internal returns (uint64 positionId) {
        vm.prank(facility_);
        positionId = floan.createPosition(marketId_, borrower_);
        assertEq(positionId, _expectedPositions.length, "sequential fixture position ID");
        _expectedPositions.push(
            IFLOANv1.Position({
                borrower: borrower_,
                marketId: marketId_,
                collateral: 0,
                principalDrawn: 0,
                principalDue: 0,
                interestDue: 0,
                maturity: 0,
                lastBorrowBlock: 0
            })
        );
    }

    function _addExpectedCollateral(
        uint64 positionId_,
        address facility_,
        uint128 amount_
    ) internal {
        vm.prank(facility_);
        floan.addCollateral(positionId_, amount_);
        _expectedPositions[positionId_].collateral += amount_;
    }

    function _increaseExpectedDebt(
        uint64 positionId_,
        address facility_,
        uint128 principal_,
        uint128 interest_,
        uint48 maturity_
    ) internal {
        vm.prank(facility_);
        floan.increaseDebt(positionId_, principal_, interest_, maturity_);

        IFLOANv1.Position storage position = _expectedPositions[positionId_];
        bool startsDebtEpisode = position.principalDue == 0 && position.interestDue == 0;
        if (principal_ != 0) {
            position.principalDrawn = startsDebtEpisode
                ? principal_
                : position.principalDrawn + principal_;
            position.lastBorrowBlock = uint32(block.number);
        }
        if (startsDebtEpisode) position.maturity = maturity_;
        position.principalDue += principal_;
        position.interestDue += interest_;
    }

    function _decreaseExpectedDebt(
        uint64 positionId_,
        address facility_,
        uint128 principal_,
        uint128 interest_
    ) internal {
        vm.prank(facility_);
        floan.decreaseDebt(positionId_, principal_, interest_);

        IFLOANv1.Position storage position = _expectedPositions[positionId_];
        position.principalDue -= principal_;
        position.interestDue -= interest_;
        if (position.principalDue == 0 && position.interestDue == 0) {
            position.principalDrawn = 0;
            position.maturity = 0;
            position.lastBorrowBlock = 0;
        }
    }

    function _clearDefaultedPosition(uint64 positionId_) internal {
        IFLOANv1.Position storage position = _expectedPositions[positionId_];
        position.collateral = 0;
        position.principalDrawn = 0;
        position.principalDue = 0;
        position.interestDue = 0;
        position.maturity = 0;
        position.lastBorrowBlock = 0;
    }

    function _assertSequentialMarketExport() internal view {
        uint32 marketCount = floan.getMarketCount();
        assertEq(marketCount, _expectedMarkets.length, "enumerated market count");
        for (uint32 marketId; marketId < marketCount; ++marketId) {
            _assertMarket(marketId, _expectedMarkets[marketId]);
            assertEq(
                floan.getMarketConfigData(marketId),
                _expectedMarketConfigData[marketId],
                "market configuration data"
            );
        }
        assertFalse(_expectedMarkets[1].originationsEnabled, "disabled market export state");
        assertEq(_expectedMarkets[3].facility, otherFacility, "rotated facility export state");
    }

    function _assertSequentialPositionExport() internal view {
        uint64 positionCount = floan.getPositionCount();
        assertEq(positionCount, _expectedPositions.length, "enumerated position count");
        for (uint64 positionId; positionId < positionCount; ++positionId) {
            _assertPosition(positionId, _expectedPositions[positionId]);
        }

        IFLOANv1.Position storage repaid = _expectedPositions[3];
        assertEq(repaid.collateral, 500e18, "repaid position retains collateral");
        assertEq(repaid.principalDrawn, 0, "repaid position clears principal drawn");
        assertEq(repaid.principalDue, 0, "repaid position clears principal due");
        assertEq(repaid.interestDue, 0, "repaid position clears interest due");
        assertEq(repaid.maturity, 0, "repaid position clears maturity");
        assertEq(repaid.lastBorrowBlock, 0, "repaid position clears borrow block");

        IFLOANv1.Position storage interestOnly = _expectedPositions[6];
        assertEq(interestOnly.principalDue, 0, "interest-only position clears principal due");
        assertEq(interestOnly.interestDue, 7e9, "interest-only position retains deferred interest");
        assertEq(
            interestOnly.maturity,
            block.timestamp + 15 days,
            "interest-only position retains maturity"
        );

        IFLOANv1.Position storage reused = _expectedPositions[0];
        assertEq(reused.principalDrawn, 80e9, "reused position has only current episode");
        assertEq(
            _expectedPrincipalDefaulted[0],
            100e9,
            "prior default remains separate from current record"
        );
    }

    function _assertMarketIndexesReconstructed() internal view {
        for (uint256 i; i < _knownFacilities.length; ++i) {
            for (uint256 j; j < _knownCollateralTokens.length; ++j) {
                for (uint256 k; k < _knownDebtTokens.length; ++k) {
                    _assertMarketTupleIndex(
                        _knownFacilities[i],
                        _knownCollateralTokens[j],
                        _knownDebtTokens[k]
                    );
                }
            }
        }
    }

    function _assertMarketTupleIndex(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) internal view {
        uint256[] memory actualIds = floan.getMarketIds(facility_, collateralToken_, debtToken_);
        uint256 expectedCount;
        for (uint256 marketId; marketId < _expectedMarkets.length; ++marketId) {
            IFLOANv1.Market storage market = _expectedMarkets[marketId];
            if (
                market.facility == facility_ &&
                market.collateralToken == collateralToken_ &&
                market.debtToken == debtToken_
            ) {
                ++expectedCount;
                assertTrue(_contains(actualIds, marketId), "tuple index contains canonical market");
            }
        }
        assertEq(actualIds.length, expectedCount, "tuple index reconstructed count");
        for (uint256 i; i < actualIds.length; ++i) {
            assertLt(
                actualIds[i],
                _expectedMarkets.length,
                "tuple index market in canonical range"
            );
            IFLOANv1.Market storage indexedMarket = _expectedMarkets[actualIds[i]];
            assertEq(indexedMarket.facility, facility_, "tuple index facility");
            assertEq(indexedMarket.collateralToken, collateralToken_, "tuple index collateral");
            assertEq(indexedMarket.debtToken, debtToken_, "tuple index debt");
        }
    }

    function _assertPositionIndexesReconstructed() internal view {
        for (uint256 borrowerIndex; borrowerIndex < _knownBorrowers.length; ++borrowerIndex) {
            address indexedBorrower = _knownBorrowers[borrowerIndex];
            _assertBorrowerPositionIndex(indexedBorrower);
            for (uint32 marketId; marketId < _expectedMarkets.length; ++marketId) {
                _assertPairPositionIndex(marketId, indexedBorrower);
            }
        }
        for (uint32 marketId; marketId < _expectedMarkets.length; ++marketId) {
            _assertMarketPositionIndex(marketId);
        }
    }

    function _assertBorrowerPositionIndex(address borrower_) internal view {
        uint256[] memory actualIds = floan.getPositionIdsForBorrower(borrower_);
        uint256 expectedCount;
        for (uint256 positionId; positionId < _expectedPositions.length; ++positionId) {
            if (_expectedPositions[positionId].borrower == borrower_) {
                ++expectedCount;
                assertTrue(
                    _contains(actualIds, positionId),
                    "borrower index contains canonical position"
                );
            }
        }
        assertEq(actualIds.length, expectedCount, "borrower index reconstructed count");
    }

    function _assertMarketPositionIndex(uint32 marketId_) internal view {
        uint256[] memory actualIds = floan.getPositionIdsForMarket(marketId_);
        uint256 expectedCount;
        for (uint256 positionId; positionId < _expectedPositions.length; ++positionId) {
            if (_expectedPositions[positionId].marketId == marketId_) {
                ++expectedCount;
                assertTrue(
                    _contains(actualIds, positionId),
                    "market index contains canonical position"
                );
            }
        }
        assertEq(actualIds.length, expectedCount, "market index reconstructed count");
    }

    function _assertPairPositionIndex(uint32 marketId_, address borrower_) internal view {
        uint256[] memory actualIds = floan.getPositionIdsForMarketAndBorrower(marketId_, borrower_);
        uint256 expectedCount;
        for (uint256 positionId; positionId < _expectedPositions.length; ++positionId) {
            IFLOANv1.Position storage position = _expectedPositions[positionId];
            if (position.marketId == marketId_ && position.borrower == borrower_) {
                ++expectedCount;
                assertTrue(
                    _contains(actualIds, positionId),
                    "pair index contains canonical position"
                );
            }
        }
        assertEq(actualIds.length, expectedCount, "pair index reconstructed count");
    }

    function _assertActiveBorrowersReconstructed() internal view {
        for (uint32 marketId; marketId < _expectedMarkets.length; ++marketId) {
            address[] memory actualBorrowers = floan.getActiveBorrowers(marketId);
            uint256 expectedCount;
            for (uint256 i; i < _knownBorrowers.length; ++i) {
                bool expectedActive = _hasActivePosition(marketId, _knownBorrowers[i]);
                assertEq(
                    _containsAddress(actualBorrowers, _knownBorrowers[i]),
                    expectedActive,
                    "active borrower membership"
                );
                if (expectedActive) ++expectedCount;
            }
            assertEq(actualBorrowers.length, expectedCount, "active borrower reconstructed count");
            assertEq(
                floan.getActiveBorrowerCount(marketId),
                expectedCount,
                "active borrower direct count"
            );
            for (uint256 i; i < expectedCount; ++i) {
                address borrowerAt = floan.getActiveBorrowerAt(marketId, i);
                assertTrue(
                    _containsAddress(actualBorrowers, borrowerAt),
                    "indexed active borrower belongs to exported membership"
                );
                assertTrue(
                    _hasActivePosition(marketId, borrowerAt),
                    "indexed active borrower derives from canonical positions"
                );
            }
        }
    }

    function _assertAccountingReconstructed() internal view {
        for (uint32 marketId; marketId < _expectedMarkets.length; ++marketId) {
            uint256 collateral;
            uint256 principal;
            uint256 interest;
            for (uint256 i; i < _expectedPositions.length; ++i) {
                IFLOANv1.Position storage position = _expectedPositions[i];
                if (position.marketId != marketId) continue;
                collateral += position.collateral;
                principal += position.principalDue;
                interest += position.interestDue;
            }
            assertEq(
                floan.getMarketCollateral(marketId),
                collateral,
                "reconstructed market collateral"
            );
            assertEq(
                floan.getMarketPrincipalDue(marketId),
                principal,
                "reconstructed market principal"
            );
            assertEq(
                floan.getMarketInterestDue(marketId),
                interest,
                "reconstructed market interest"
            );
            assertEq(
                floan.getMarketPrincipalDefaulted(marketId),
                _expectedPrincipalDefaulted[marketId],
                "direct cumulative principal defaulted"
            );
        }

        for (uint256 i; i < _knownFacilities.length; ++i) {
            for (uint256 j; j < _knownDebtTokens.length; ++j) {
                _assertFacilityPrincipalReconstructed(_knownFacilities[i], _knownDebtTokens[j]);
            }
        }
    }

    function _assertFacilityPrincipalReconstructed(
        address facility_,
        address debtToken_
    ) internal view {
        uint256 expectedPrincipal;
        for (uint256 i; i < _expectedPositions.length; ++i) {
            IFLOANv1.Position storage position = _expectedPositions[i];
            IFLOANv1.Market storage market = _expectedMarkets[position.marketId];
            if (market.facility == facility_ && market.debtToken == debtToken_) {
                expectedPrincipal += position.principalDue;
            }
        }
        assertEq(
            floan.getFacilityPrincipalDue(facility_, debtToken_),
            expectedPrincipal,
            "reconstructed facility and debt-token principal"
        );
    }

    function _hasActivePosition(uint32 marketId_, address borrower_) internal view returns (bool) {
        for (uint256 i; i < _expectedPositions.length; ++i) {
            IFLOANv1.Position storage position = _expectedPositions[i];
            if (
                position.marketId == marketId_ &&
                position.borrower == borrower_ &&
                (position.principalDue != 0 || position.interestDue != 0)
            ) return true;
        }
        return false;
    }

    function _containsAddress(
        address[] memory values_,
        address value_
    ) internal pure returns (bool) {
        for (uint256 i; i < values_.length; ++i) {
            if (values_[i] == value_) return true;
        }
        return false;
    }
}
