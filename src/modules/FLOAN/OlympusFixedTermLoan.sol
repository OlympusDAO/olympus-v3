// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

// Libraries
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";

// Contracts
import {FLOANv1} from "src/modules/FLOAN/FLOAN.v1.sol";
import {Kernel, Keycode, toKeycode} from "src/Kernel.sol";

/// @title Olympus Fixed-Term Loan Ledger
/// @notice Stores markets and positions while leaving custody and economics to servicing policies.
contract OlympusFixedTermLoan is FLOANv1 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint16 internal constant _BPS = 10_000;

    constructor(Kernel kernel_) FLOANv1(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("FLOAN");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    function marketCount() external view override returns (uint32) {
        return _marketCount;
    }

    function positionCount() external view override returns (uint64) {
        return _positionCount;
    }

    function marketPrincipalDue(uint32 marketId_) external view override returns (uint128) {
        _requireMarket(marketId_);
        return _marketPrincipalDue[marketId_];
    }

    function facilityPrincipalDue(
        address facility_,
        address debtToken_
    ) external view override returns (uint256) {
        return _facilityPrincipalDue[facility_][debtToken_];
    }

    function debtTokenPrincipalDue(address debtToken_) external view override returns (uint256) {
        return _debtTokenPrincipalDue[debtToken_];
    }

    function marketPrincipalDefaulted(uint32 marketId_) external view override returns (uint256) {
        _requireMarket(marketId_);
        return _marketPrincipalDefaulted[marketId_];
    }

    function facilityPrincipalDefaulted(
        address facility_,
        address debtToken_
    ) external view override returns (uint256) {
        return _facilityPrincipalDefaulted[facility_][debtToken_];
    }

    function debtTokenPrincipalDefaulted(
        address debtToken_
    ) external view override returns (uint256) {
        return _debtTokenPrincipalDefaulted[debtToken_];
    }

    function getMarketIds(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) external view override returns (uint256[] memory marketIds) {
        return _marketIds[facility_][collateralToken_][debtToken_].values();
    }

    function getMarket(uint32 marketId_) external view override returns (Market memory) {
        _requireMarket(marketId_);
        return _markets[marketId_];
    }

    function getMarketConfigData(uint32 marketId_) external view override returns (bytes memory) {
        _requireMarket(marketId_);
        return _marketConfigData[marketId_];
    }

    function getPosition(uint64 positionId_) external view override returns (Position memory) {
        _requirePosition(positionId_);
        return _positions[positionId_];
    }

    function isPositionDefaulted(uint64 positionId_) external view override returns (bool) {
        _requirePosition(positionId_);
        return _positions[positionId_].defaulted;
    }

    function getPositionId(
        uint32 marketId_,
        address borrower_
    ) public view override returns (bool exists, uint64 positionId) {
        _requireMarket(marketId_);
        uint64 positionIdPlusOne = _defaultPositionIds[marketId_][borrower_];
        return (positionIdPlusOne != 0, positionIdPlusOne == 0 ? 0 : positionIdPlusOne - 1);
    }

    function getPositionForBorrower(
        uint32 marketId_,
        address borrower_
    ) external view override returns (Position memory) {
        (bool exists, uint64 positionId) = getPositionId(marketId_, borrower_);
        return
            exists
                ? _positions[positionId]
                : Position({
                    borrower: borrower_,
                    marketId: marketId_,
                    collateral: 0,
                    principalDrawn: 0,
                    principalDue: 0,
                    interestDue: 0,
                    maturity: 0,
                    lastBorrowBlock: 0,
                    defaulted: false
                });
    }

    function getPositionIdsForBorrower(
        address borrower_
    ) external view override returns (uint256[] memory) {
        return _positionIdsByBorrower[borrower_].values();
    }

    function getPositionIdsForMarket(
        uint32 marketId_
    ) external view override returns (uint256[] memory) {
        _requireMarket(marketId_);
        return _positionIdsByMarket[marketId_].values();
    }

    function getPositionIdsForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view override returns (uint256[] memory) {
        _requireMarket(marketId_);
        return _positionIdsByMarketAndBorrower[marketId_][borrower_].values();
    }

    function getActiveBorrowers(
        uint32 marketId_
    ) external view override returns (address[] memory) {
        _requireMarket(marketId_);
        return _activeBorrowersByMarket[marketId_].values();
    }

    function activeBorrowerCount(uint32 marketId_) external view override returns (uint256) {
        _requireMarket(marketId_);
        return _activeBorrowersByMarket[marketId_].length();
    }

    function activeBorrowerAt(
        uint32 marketId_,
        uint256 index_
    ) external view override returns (address) {
        _requireMarket(marketId_);
        return _activeBorrowersByMarket[marketId_].at(index_);
    }

    function createMarket(
        Market calldata market_,
        bytes calldata configData_
    ) external override permissioned returns (uint32 marketId) {
        _validateNewMarket(market_);

        marketId = _marketCount++;
        _markets[marketId] = market_;
        _marketIds[market_.facility][market_.collateralToken][market_.debtToken].add(marketId);
        _marketConfigData[marketId] = configData_;

        emit MarketCreated(
            marketId,
            market_.collateralToken,
            market_.debtToken,
            market_.manager,
            market_.facility,
            market_.configId
        );
        emit MarketOriginationsSet(marketId, market_.originationsEnabled);
        emit MarketConfigSet(marketId, _markets[marketId], configData_);
    }

    function setMarketConfig(
        uint32 marketId_,
        Market calldata market_,
        bytes calldata configData_
    ) external override permissioned {
        _requireManager(marketId_);
        _validateMarketConfig(market_);

        Market storage stored = _markets[marketId_];
        if (
            market_.collateralToken != stored.collateralToken ||
            market_.debtToken != stored.debtToken ||
            market_.manager != stored.manager ||
            market_.facility != stored.facility ||
            market_.configId != stored.configId ||
            market_.principalCap < _marketPrincipalDue[marketId_]
        ) revert FLOAN_InvalidConfig();

        bool originationsEnabled = stored.originationsEnabled;
        _markets[marketId_] = market_;
        stored.originationsEnabled = originationsEnabled;
        _marketConfigData[marketId_] = configData_;
        emit MarketConfigSet(marketId_, stored, configData_);
    }

    function setMarketManager(uint32 marketId_, address manager_) external override permissioned {
        if (manager_ == address(0)) revert FLOAN_ZeroAddress();
        _requireManager(marketId_);
        address oldManager = _markets[marketId_].manager;
        _markets[marketId_].manager = manager_;
        emit MarketManagerSet(marketId_, oldManager, manager_);
    }

    function setMarketOriginationsEnabled(
        uint32 marketId_,
        bool enabled_
    ) external override permissioned {
        _requireManager(marketId_);
        _markets[marketId_].originationsEnabled = enabled_;
        emit MarketOriginationsSet(marketId_, enabled_);
    }

    function setMarketFacility(uint32 marketId_, address facility_) external override permissioned {
        if (facility_ == address(0)) revert FLOAN_ZeroAddress();
        _requireManager(marketId_);
        Market storage market = _markets[marketId_];
        address oldFacility = market.facility;
        if (facility_ == oldFacility) return;

        _marketIds[oldFacility][market.collateralToken][market.debtToken].remove(marketId_);
        _marketIds[facility_][market.collateralToken][market.debtToken].add(marketId_);

        uint128 principalDue = _marketPrincipalDue[marketId_];
        if (principalDue != 0) {
            _facilityPrincipalDue[oldFacility][market.debtToken] -= principalDue;
            _facilityPrincipalDue[facility_][market.debtToken] += principalDue;
        }
        market.facility = facility_;
        emit MarketFacilitySet(marketId_, oldFacility, facility_);
    }

    function createPosition(
        uint32 marketId_,
        address borrower_
    ) external override permissioned returns (uint64 positionId) {
        _requireFacility(marketId_);
        return _createPosition(marketId_, borrower_);
    }

    function getOrCreatePosition(
        uint32 marketId_,
        address borrower_
    ) external override permissioned returns (uint64 positionId) {
        _requireFacility(marketId_);
        (bool exists, uint64 existingPositionId) = getPositionId(marketId_, borrower_);
        if (exists) return existingPositionId;

        positionId = _createPosition(marketId_, borrower_);
        _defaultPositionIds[marketId_][borrower_] = positionId + 1;
    }

    function addCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external override permissioned returns (uint128 collateral) {
        Position storage position = _requireServicedPosition(positionId_);
        if (amount_ == 0) revert FLOAN_InvalidAmount();
        position.collateral += amount_;
        collateral = position.collateral;
        emit PositionCollateralChanged(positionId_, collateral);
    }

    function removeCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external override permissioned returns (uint128 collateral) {
        Position storage position = _requireServicedPosition(positionId_);
        if (amount_ == 0 || amount_ > position.collateral) revert FLOAN_InvalidAmount();
        position.collateral -= amount_;
        collateral = position.collateral;
        emit PositionCollateralChanged(positionId_, collateral);
    }

    function increaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_,
        uint48 maturity_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireServicedPosition(positionId_);
        Market storage market = _markets[stored.marketId];
        if (!market.originationsEnabled) revert FLOAN_OriginationsDisabled(stored.marketId);
        if (principal_ == 0 || maturity_ <= block.timestamp) revert FLOAN_InvalidAmount();

        uint128 resultingMarketPrincipal = _marketPrincipalDue[stored.marketId] + principal_;
        if (resultingMarketPrincipal > market.principalCap) {
            revert FLOAN_PrincipalCapExceeded(stored.marketId, market.principalCap);
        }

        bool startsDebtEpisode = stored.principalDue == 0 && stored.interestDue == 0;
        if (startsDebtEpisode) {
            stored.principalDrawn = principal_;
            stored.maturity = maturity_;
            uint32 activeCount = ++_activePositionCount[stored.marketId][stored.borrower];
            if (activeCount == 1) {
                _activeBorrowersByMarket[stored.marketId].add(stored.borrower);
            }
        } else {
            if (stored.maturity != maturity_) {
                revert FLOAN_InvalidMaturity(stored.maturity, maturity_);
            }
            stored.principalDrawn += principal_;
        }

        stored.principalDue += principal_;
        stored.interestDue += interest_;
        stored.lastBorrowBlock = _toUint32(block.number);
        _marketPrincipalDue[stored.marketId] = resultingMarketPrincipal;
        _facilityPrincipalDue[market.facility][market.debtToken] += principal_;
        _debtTokenPrincipalDue[market.debtToken] += principal_;
        emit PositionDebtIncreased(
            positionId_,
            stored.principalDrawn,
            stored.principalDue,
            stored.interestDue,
            stored.maturity
        );
        return stored;
    }

    function decreaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireServicedPosition(positionId_);
        if (
            (principal_ == 0 && interest_ == 0) ||
            (stored.principalDue == 0 && stored.interestDue == 0)
        ) revert FLOAN_InvalidAmount();
        if (principal_ > stored.principalDue || interest_ > stored.interestDue) {
            revert FLOAN_InvalidAmount();
        }

        stored.principalDue -= principal_;
        stored.interestDue -= interest_;
        _marketPrincipalDue[stored.marketId] -= principal_;
        Market storage market = _markets[stored.marketId];
        _facilityPrincipalDue[market.facility][market.debtToken] -= principal_;
        _debtTokenPrincipalDue[market.debtToken] -= principal_;
        if (stored.principalDue == 0 && stored.interestDue == 0) {
            stored.principalDrawn = 0;
            stored.maturity = 0;
            stored.lastBorrowBlock = 0;
            uint32 activeCount = --_activePositionCount[stored.marketId][stored.borrower];
            if (activeCount == 0) {
                _activeBorrowersByMarket[stored.marketId].remove(stored.borrower);
            }
        }
        emit PositionDebtDecreased(positionId_, stored.principalDue, stored.interestDue);
        return stored;
    }

    function extendMaturity(
        uint64 positionId_,
        uint48 newMaturity_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireServicedPosition(positionId_);
        if (stored.principalDue == 0 && stored.interestDue == 0) revert FLOAN_InvalidAmount();

        Market storage market = _markets[stored.marketId];
        if (!market.originationsEnabled) revert FLOAN_OriginationsDisabled(stored.marketId);
        uint48 oldMaturity = stored.maturity;
        if (newMaturity_ <= oldMaturity || newMaturity_ <= block.timestamp) {
            revert FLOAN_InvalidMaturity(oldMaturity, newMaturity_);
        }

        stored.maturity = newMaturity_;
        emit PositionMaturityExtended(positionId_, oldMaturity, newMaturity_);
        return stored;
    }

    function defaultPosition(
        uint64 positionId_
    )
        external
        override
        permissioned
        returns (uint128 principalDefaulted, uint128 interestDefaulted, uint128 collateralSeized)
    {
        _requirePosition(positionId_);
        Position storage stored = _positions[positionId_];
        _requireFacility(stored.marketId);
        if (stored.defaulted) revert FLOAN_PositionDefaulted(positionId_);
        if (stored.principalDue == 0 && stored.interestDue == 0) revert FLOAN_InvalidAmount();

        principalDefaulted = stored.principalDue;
        interestDefaulted = stored.interestDue;
        collateralSeized = stored.collateral;

        stored.principalDue = 0;
        stored.interestDue = 0;
        stored.collateral = 0;
        stored.defaulted = true;

        _marketPrincipalDue[stored.marketId] -= principalDefaulted;
        Market storage market = _markets[stored.marketId];
        _facilityPrincipalDue[market.facility][market.debtToken] -= principalDefaulted;
        _debtTokenPrincipalDue[market.debtToken] -= principalDefaulted;
        _marketPrincipalDefaulted[stored.marketId] += principalDefaulted;
        _facilityPrincipalDefaulted[market.facility][market.debtToken] += principalDefaulted;
        _debtTokenPrincipalDefaulted[market.debtToken] += principalDefaulted;
        uint32 activeCount = --_activePositionCount[stored.marketId][stored.borrower];
        if (activeCount == 0) {
            _activeBorrowersByMarket[stored.marketId].remove(stored.borrower);
        }

        emit PositionDebtDecreased(positionId_, 0, 0);
        emit PositionCollateralChanged(positionId_, 0);
        emit PositionDefaulted(
            positionId_,
            principalDefaulted,
            interestDefaulted,
            collateralSeized
        );
    }

    function _validateNewMarket(Market calldata market_) internal pure {
        if (
            market_.collateralToken == address(0) ||
            market_.debtToken == address(0) ||
            market_.manager == address(0) ||
            market_.facility == address(0)
        ) revert FLOAN_ZeroAddress();
        _validateMarketConfig(market_);
    }

    function _createPosition(
        uint32 marketId_,
        address borrower_
    ) internal returns (uint64 positionId) {
        if (borrower_ == address(0)) revert FLOAN_ZeroAddress();
        positionId = _positionCount++;
        _positions[positionId] = Position({
            borrower: borrower_,
            marketId: marketId_,
            collateral: 0,
            principalDrawn: 0,
            principalDue: 0,
            interestDue: 0,
            maturity: 0,
            lastBorrowBlock: 0,
            defaulted: false
        });
        _positionIdsByMarket[marketId_].add(positionId);
        _positionIdsByBorrower[borrower_].add(positionId);
        _positionIdsByMarketAndBorrower[marketId_][borrower_].add(positionId);
        emit PositionCreated(positionId, marketId_, borrower_);
    }

    function _validateMarketConfig(Market calldata market_) internal pure {
        if (
            market_.termLength == 0 ||
            (market_.maxMaturityHorizon != type(uint48).max &&
                market_.maxMaturityHorizon <= market_.termLength) ||
            market_.collateralFactorBps > _BPS ||
            market_.baseFeeBps > _BPS ||
            market_.collateralDecimals > 77 ||
            market_.debtDecimals > 77
        ) revert FLOAN_InvalidConfig();
    }

    function _requireMarket(uint32 marketId_) internal view {
        if (marketId_ >= _marketCount) revert FLOAN_InvalidMarket(marketId_);
    }

    function _requirePosition(uint64 positionId_) internal view {
        if (positionId_ >= _positionCount) revert FLOAN_InvalidPosition(positionId_);
    }

    function _requireManager(uint32 marketId_) internal view {
        _requireMarket(marketId_);
        if (_markets[marketId_].manager != msg.sender) {
            revert FLOAN_NotManager(marketId_, msg.sender);
        }
    }

    function _requireFacility(uint32 marketId_) internal view {
        _requireMarket(marketId_);
        if (_markets[marketId_].facility != msg.sender) {
            revert FLOAN_NotFacility(marketId_, msg.sender);
        }
    }

    function _requireServicedPosition(
        uint64 positionId_
    ) internal view returns (Position storage position) {
        _requirePosition(positionId_);
        position = _positions[positionId_];
        _requireFacility(position.marketId);
        if (position.defaulted) revert FLOAN_PositionDefaulted(positionId_);
    }

    function _toUint32(uint256 value_) internal pure returns (uint32 result) {
        return SafeCast.toUint32(value_);
    }
}
