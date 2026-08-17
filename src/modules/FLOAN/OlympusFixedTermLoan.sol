// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";

// Contracts
import {FLOANv1} from "src/modules/FLOAN/FLOAN.v1.sol";
import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

/// @title Olympus Fixed-Term Loan Ledger
/// @notice Stores markets and positions while leaving custody and economics to servicing policies.
contract OlympusFixedTermLoan is FLOANv1 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint16 internal constant _BPS = 10_000;

    constructor(Kernel kernel_) FLOANv1(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("FLOAN");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IFLOANv1).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId;
    }

    /// @inheritdoc IFLOANv1
    function getMarketCount() external view override returns (uint32) {
        return _marketCount;
    }

    /// @inheritdoc IFLOANv1
    function getPositionCount() external view override returns (uint64) {
        return _positionCount;
    }

    /// @inheritdoc IFLOANv1
    function getFacilityPrincipalDue(
        address facility_,
        address debtToken_
    ) external view override returns (uint256) {
        return _facilityPrincipalDue[facility_][debtToken_];
    }

    /// @inheritdoc IFLOANv1
    function getMarketIds(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) external view override returns (uint256[] memory marketIds) {
        return _marketIds[facility_][collateralToken_][debtToken_].values();
    }

    /// @inheritdoc IFLOANv1
    function getMarket(uint32 marketId_) external view override returns (Market memory) {
        _requireMarket(marketId_);
        return _markets[marketId_];
    }

    /// @inheritdoc IFLOANv1
    function getMarketConfigData(uint32 marketId_) external view override returns (bytes memory) {
        _requireMarket(marketId_);
        return _marketConfigData[marketId_];
    }

    /// @inheritdoc IFLOANv1
    function getPosition(uint64 positionId_) external view override returns (Position memory) {
        _requirePosition(positionId_);
        return _positions[positionId_];
    }

    /// @inheritdoc IFLOANv1
    function getPositionIdsForBorrower(
        address borrower_
    ) external view override returns (uint256[] memory) {
        return _positionIdsByBorrower[borrower_].values();
    }

    /// @inheritdoc IFLOANv1
    function getPositionIdsForMarket(
        uint32 marketId_
    ) external view override returns (uint256[] memory) {
        return _positionIdsByMarket[marketId_].values();
    }

    /// @inheritdoc IFLOANv1
    function getPositionIdsForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view override returns (uint256[] memory) {
        return _positionIdsByMarketAndBorrower[marketId_][borrower_].values();
    }

    /// @inheritdoc IFLOANv1
    function getPositionIdForMarketAndBorrowerAt(
        uint32 marketId_,
        address borrower_,
        uint256 index_
    ) external view override returns (bool exists, uint64 positionId) {
        EnumerableSet.UintSet storage positionIds = _positionIdsByMarketAndBorrower[marketId_][
            borrower_
        ];
        if (index_ >= positionIds.length()) return (false, 0);

        // Position IDs enter this index only through uint64-typed storage helpers.
        return (true, uint64(positionIds.at(index_)));
    }

    /// @inheritdoc IFLOANv1
    function getActiveBorrowers(
        uint32 marketId_
    ) external view override returns (address[] memory) {
        return _activeBorrowersByMarket[marketId_].values();
    }

    /// @inheritdoc IFLOANv1
    function getActiveBorrowerCount(uint32 marketId_) external view override returns (uint256) {
        return _activeBorrowersByMarket[marketId_].length();
    }

    /// @inheritdoc IFLOANv1
    function getActiveBorrowerAt(
        uint32 marketId_,
        uint256 index_
    ) external view override returns (address) {
        _requireMarket(marketId_);
        EnumerableSet.AddressSet storage borrowers = _activeBorrowersByMarket[marketId_];
        if (index_ >= borrowers.length()) {
            revert FLOAN_ActiveBorrowerIndexOutOfBounds();
        }
        return borrowers.at(index_);
    }

    /// @inheritdoc IFLOANv1
    function createMarket(
        MarketInput calldata market_,
        bytes calldata configData_
    ) external override permissioned returns (uint32 marketId) {
        return _storeMarket(market_, configData_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketPrincipalCap(
        uint32 marketId_,
        uint128 principalCap_
    ) external override permissioned {
        _requireManager(marketId_);
        if (principalCap_ < getMarketPrincipalDue[marketId_]) revert FLOAN_InvalidConfig();
        _markets[marketId_].principalCap = principalCap_;
        emit MarketConfigUpdated(marketId_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketRiskConfig(
        uint32 marketId_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_
    ) external override permissioned {
        _requireManager(marketId_);
        _validateRiskConfig(termLength_, maxMaturityHorizon_, collateralFactorBps_);
        Market storage market = _markets[marketId_];
        market.termLength = termLength_;
        market.maxMaturityHorizon = maxMaturityHorizon_;
        market.collateralFactorBps = collateralFactorBps_;
        market.minCollateralRatioBps = minCollateralRatioBps_;
        emit MarketConfigUpdated(marketId_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketBaseFee(uint32 marketId_, uint16 baseFeeBps_) external override permissioned {
        _requireManager(marketId_);
        if (baseFeeBps_ > _BPS) revert FLOAN_InvalidConfig();
        _markets[marketId_].baseFeeBps = baseFeeBps_;
        emit MarketConfigUpdated(marketId_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketConfigData(
        uint32 marketId_,
        bytes calldata configData_
    ) external override permissioned {
        _requireManager(marketId_);
        _marketConfigData[marketId_] = configData_;
        emit MarketConfigUpdated(marketId_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketManager(uint32 marketId_, address manager_) external override permissioned {
        if (manager_ == address(0)) revert FLOAN_ZeroAddress();
        _requireManager(marketId_);
        Market storage market = _markets[marketId_];
        address oldManager = market.manager;
        market.manager = manager_;
        emit MarketManagerSet(marketId_, oldManager, manager_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketOriginationsEnabled(
        uint32 marketId_,
        bool enabled_
    ) external override permissioned {
        _requireManager(marketId_);
        _markets[marketId_].originationsEnabled = enabled_;
        emit MarketOriginationsSet(marketId_, enabled_);
    }

    /// @inheritdoc IFLOANv1
    function setMarketFacility(uint32 marketId_, address facility_) external override permissioned {
        if (facility_ == address(0)) revert FLOAN_ZeroAddress();
        _requireManager(marketId_);
        Market storage market = _markets[marketId_];
        address oldFacility = market.facility;
        if (facility_ == oldFacility) return;

        _marketIds[oldFacility][market.collateralToken][market.debtToken].remove(marketId_);
        _marketIds[facility_][market.collateralToken][market.debtToken].add(marketId_);

        uint128 principalDue = getMarketPrincipalDue[marketId_];
        if (principalDue != 0) {
            _facilityPrincipalDue[oldFacility][market.debtToken] -= principalDue;
            _facilityPrincipalDue[facility_][market.debtToken] += principalDue;
        }
        market.facility = facility_;
        emit MarketFacilitySet(marketId_, oldFacility, facility_);
    }

    /// @inheritdoc IFLOANv1
    function createPosition(
        uint32 marketId_,
        address borrower_
    ) external override permissioned returns (uint64 positionId) {
        _requireFacility(marketId_);
        _requireOriginationsEnabled(marketId_);
        return _createPosition(marketId_, borrower_);
    }

    /// @inheritdoc IFLOANv1
    function addCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external override permissioned returns (uint128 collateral) {
        Position storage position = _requireOriginatingPosition(positionId_);
        if (amount_ == 0) revert FLOAN_InvalidAmount();
        position.collateral += amount_;
        getMarketCollateral[position.marketId] += amount_;
        collateral = position.collateral;
        emit PositionCollateralChanged(positionId_, collateral);
    }

    /// @inheritdoc IFLOANv1
    function removeCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external override permissioned returns (uint128 collateral) {
        Position storage position = _requireServicedPosition(positionId_);
        if (amount_ == 0 || amount_ > position.collateral) revert FLOAN_InvalidAmount();
        position.collateral -= amount_;
        getMarketCollateral[position.marketId] -= amount_;
        collateral = position.collateral;
        emit PositionCollateralChanged(positionId_, collateral);
    }

    /// @inheritdoc IFLOANv1
    function increaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_,
        uint48 maturity_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireOriginatingPosition(positionId_);
        bool startsDebtEpisode = stored.principalDue == 0 && stored.interestDue == 0;
        if (maturity_ <= block.timestamp) revert FLOAN_InvalidAmount();
        if (principal_ == 0) {
            if (interest_ == 0 || startsDebtEpisode) revert FLOAN_InvalidAmount();
        } else {
            _increasePrincipal(stored.marketId, stored.borrower, principal_, startsDebtEpisode);
            stored.principalDrawn = startsDebtEpisode
                ? principal_
                : stored.principalDrawn + principal_;
            stored.lastBorrowBlock = SafeCast.toUint32(block.number);
        }

        if (startsDebtEpisode) {
            stored.maturity = maturity_;
        } else {
            if (stored.maturity != maturity_) {
                revert FLOAN_InvalidMaturity(stored.maturity, maturity_);
            }
        }

        stored.principalDue += principal_;
        stored.interestDue += interest_;
        _increaseInterest(stored.marketId, interest_);
        emit PositionDebtIncreased(
            positionId_,
            stored.principalDrawn,
            stored.principalDue,
            stored.interestDue,
            stored.maturity
        );
        return stored;
    }

    /// @inheritdoc IFLOANv1
    function decreaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireServicedPosition(positionId_);
        if (
            (principal_ == 0 && interest_ == 0) ||
            (stored.principalDue == 0 && stored.interestDue == 0)
        ) {
            revert FLOAN_InvalidAmount();
        }
        if (principal_ > stored.principalDue || interest_ > stored.interestDue) {
            revert FLOAN_InvalidAmount();
        }

        stored.principalDue -= principal_;
        stored.interestDue -= interest_;
        getMarketPrincipalDue[stored.marketId] -= principal_;
        Market storage market = _markets[stored.marketId];
        _facilityPrincipalDue[market.facility][market.debtToken] -= principal_;
        getMarketInterestDue[stored.marketId] -= interest_;
        if (stored.principalDue == 0 && stored.interestDue == 0) {
            emit PositionClosed(
                positionId_,
                stored.marketId,
                stored.borrower,
                stored.collateral,
                stored.principalDrawn,
                stored.maturity,
                stored.lastBorrowBlock
            );
            _closeDebtEpisode(stored);
        }
        emit PositionDebtDecreased(positionId_, stored.principalDue, stored.interestDue);
        return stored;
    }

    /// @inheritdoc IFLOANv1
    function extendMaturity(
        uint64 positionId_,
        uint48 newMaturity_
    ) external override permissioned returns (Position memory position) {
        Position storage stored = _requireOriginatingPosition(positionId_);
        if (stored.principalDue == 0 && stored.interestDue == 0) revert FLOAN_InvalidAmount();

        Market storage market = _markets[stored.marketId];
        uint48 oldMaturity = stored.maturity;
        if (newMaturity_ <= oldMaturity || newMaturity_ <= block.timestamp) {
            revert FLOAN_InvalidMaturity(oldMaturity, newMaturity_);
        }
        if (market.maxMaturityHorizon != type(uint48).max) {
            uint256 maximumMaturity = block.timestamp + market.maxMaturityHorizon;
            if (newMaturity_ > maximumMaturity) {
                // The cast is safe: this branch requires maximumMaturity < newMaturity_, and the
                // requested maturity is already bounded to uint48 by the function signature.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint48 maximumMaturityUint48 = uint48(maximumMaturity);
                revert FLOAN_MaturityHorizonExceeded(newMaturity_, maximumMaturityUint48);
            }
        }

        stored.maturity = newMaturity_;
        emit PositionMaturityExtended(positionId_, oldMaturity, newMaturity_);
        return stored;
    }

    /// @inheritdoc IFLOANv1
    function defaultPosition(
        uint64 positionId_
    )
        external
        override
        permissioned
        returns (uint128 principalDefaulted, uint128 interestDefaulted, uint128 collateralSeized)
    {
        Position storage stored = _requireServicedPosition(positionId_);
        if (stored.principalDue == 0 && stored.interestDue == 0) revert FLOAN_InvalidAmount();

        principalDefaulted = stored.principalDue;
        interestDefaulted = stored.interestDue;
        collateralSeized = stored.collateral;
        uint128 principalDrawn = stored.principalDrawn;
        uint48 maturity = stored.maturity;
        uint32 lastBorrowBlock = stored.lastBorrowBlock;

        stored.principalDue = 0;
        stored.interestDue = 0;
        stored.collateral = 0;

        getMarketCollateral[stored.marketId] -= collateralSeized;
        getMarketPrincipalDue[stored.marketId] -= principalDefaulted;
        Market storage market = _markets[stored.marketId];
        _facilityPrincipalDue[market.facility][market.debtToken] -= principalDefaulted;
        getMarketInterestDue[stored.marketId] -= interestDefaulted;
        getMarketPrincipalDefaulted[stored.marketId] += principalDefaulted;
        _closeDebtEpisode(stored);

        emit PositionDebtDecreased(positionId_, 0, 0);
        emit PositionCollateralChanged(positionId_, 0);
        emit PositionDefaulted(
            positionId_,
            stored.marketId,
            stored.borrower,
            principalDrawn,
            principalDefaulted,
            interestDefaulted,
            collateralSeized,
            maturity,
            lastBorrowBlock
        );
    }

    function _validateNewMarket(MarketInput calldata market_) internal pure {
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
            lastBorrowBlock: 0
        });
        _indexPosition(positionId, marketId_, borrower_);
        emit PositionCreated(positionId, marketId_, borrower_);
    }

    function _storeMarket(
        MarketInput calldata market_,
        bytes calldata configData_
    ) internal returns (uint32 marketId) {
        _validateNewMarket(market_);

        uint8 collateralDecimals = _getTokenDecimals(market_.collateralToken);
        uint8 debtDecimals = _getTokenDecimals(market_.debtToken);

        marketId = _marketCount++;
        _markets[marketId] = Market({
            collateralToken: market_.collateralToken,
            debtToken: market_.debtToken,
            manager: market_.manager,
            facility: market_.facility,
            configId: market_.configId,
            principalCap: market_.principalCap,
            termLength: market_.termLength,
            maxMaturityHorizon: market_.maxMaturityHorizon,
            collateralFactorBps: market_.collateralFactorBps,
            minCollateralRatioBps: market_.minCollateralRatioBps,
            baseFeeBps: market_.baseFeeBps,
            collateralDecimals: collateralDecimals,
            debtDecimals: debtDecimals,
            originationsEnabled: true
        });
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
        emit MarketOriginationsSet(marketId, true);
    }

    function _indexPosition(uint64 positionId_, uint32 marketId_, address borrower_) internal {
        _positionIdsByMarket[marketId_].add(positionId_);
        _positionIdsByBorrower[borrower_].add(positionId_);
        _positionIdsByMarketAndBorrower[marketId_][borrower_].add(positionId_);
    }

    function _increasePrincipal(
        uint32 marketId_,
        address borrower_,
        uint128 principal_,
        bool activatePosition_
    ) internal {
        Market storage market = _markets[marketId_];
        uint256 resultingMarketPrincipal = uint256(getMarketPrincipalDue[marketId_]) + principal_;
        if (resultingMarketPrincipal > market.principalCap) {
            revert FLOAN_PrincipalCapExceeded(marketId_, market.principalCap);
        }
        getMarketPrincipalDue[marketId_] = SafeCast.toUint128(resultingMarketPrincipal);
        _facilityPrincipalDue[market.facility][market.debtToken] += principal_;
        if (activatePosition_) {
            uint32 activeCount = ++_activePositionCount[marketId_][borrower_];
            if (activeCount == 1) _activeBorrowersByMarket[marketId_].add(borrower_);
        }
    }

    function _increaseInterest(uint32 marketId_, uint128 interest_) internal {
        if (interest_ == 0) return;
        getMarketInterestDue[marketId_] += interest_;
    }

    function _closeDebtEpisode(Position storage position_) internal {
        position_.principalDrawn = 0;
        position_.maturity = 0;
        position_.lastBorrowBlock = 0;

        uint32 activeCount = --_activePositionCount[position_.marketId][position_.borrower];
        if (activeCount == 0) {
            _activeBorrowersByMarket[position_.marketId].remove(position_.borrower);
        }
    }

    function _validateMarketConfig(MarketInput calldata market_) internal pure {
        _validateRiskConfig(
            market_.termLength,
            market_.maxMaturityHorizon,
            market_.collateralFactorBps
        );
        if (market_.baseFeeBps > _BPS) revert FLOAN_InvalidConfig();
    }

    function _getTokenDecimals(address token_) internal view returns (uint8 decimals) {
        decimals = IERC20(token_).decimals();
        if (decimals > 77) revert FLOAN_InvalidConfig();
    }

    function _validateRiskConfig(
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint16 collateralFactorBps_
    ) internal pure {
        if (
            termLength_ == 0 ||
            (maxMaturityHorizon_ != type(uint48).max && maxMaturityHorizon_ <= termLength_) ||
            collateralFactorBps_ > _BPS
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
    }

    function _requireOriginatingPosition(
        uint64 positionId_
    ) internal view returns (Position storage position) {
        position = _requireServicedPosition(positionId_);
        _requireOriginationsEnabled(position.marketId);
    }

    function _requireOriginationsEnabled(uint32 marketId_) internal view {
        if (!_markets[marketId_].originationsEnabled) {
            revert FLOAN_OriginationsDisabled(marketId_);
        }
    }
}
