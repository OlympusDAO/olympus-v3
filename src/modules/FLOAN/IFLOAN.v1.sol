// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Fixed-Term Loan Module Interface
/// @notice Dependency-free ledger for fixed-term loan markets and positions.
interface IFLOANv1 {
    error FLOAN_InvalidAmount();
    error FLOAN_InvalidConfig();
    error FLOAN_InvalidMarket(uint32 marketId);
    error FLOAN_InvalidMaturity(uint48 expected, uint48 actual);
    error FLOAN_MaturityHorizonExceeded(uint48 requested, uint48 maximum);
    error FLOAN_InvalidPosition(uint64 positionId);
    error FLOAN_PositionDefaulted(uint64 positionId);
    error FLOAN_NotManager(uint32 marketId, address caller);
    error FLOAN_NotFacility(uint32 marketId, address caller);
    error FLOAN_OriginationsDisabled(uint32 marketId);
    error FLOAN_PrincipalCapExceeded(uint32 marketId, uint128 principalCap);
    error FLOAN_InvalidImportId(uint256 expectedId, uint256 providedId);
    error FLOAN_ZeroAddress();

    struct Market {
        address collateralToken;
        address debtToken;
        address manager;
        address facility;
        bytes16 configId;
        uint128 principalCap;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 baseFeeBps;
        uint8 collateralDecimals;
        uint8 debtDecimals;
        bool originationsEnabled;
    }

    struct Position {
        address borrower;
        uint32 marketId;
        uint128 collateral;
        uint128 principalDrawn;
        uint128 principalDue;
        uint128 interestDue;
        uint48 maturity;
        uint32 lastBorrowBlock;
        bool defaulted;
    }

    event MarketCreated(
        uint32 indexed marketId,
        address indexed collateralToken,
        address indexed debtToken,
        address manager,
        address facility,
        bytes16 configId
    );
    event MarketConfigSet(uint32 indexed marketId, Market market, bytes configData);
    event MarketManagerSet(
        uint32 indexed marketId,
        address indexed oldManager,
        address indexed newManager
    );
    event MarketOriginationsSet(uint32 indexed marketId, bool enabled);
    event MarketFacilitySet(
        uint32 indexed marketId,
        address indexed oldFacility,
        address indexed newFacility
    );
    event PositionCreated(
        uint64 indexed positionId,
        uint32 indexed marketId,
        address indexed borrower
    );
    event PositionCollateralChanged(uint64 indexed positionId, uint128 collateral);
    event PositionDebtIncreased(
        uint64 indexed positionId,
        uint128 principalDrawn,
        uint128 principalDue,
        uint128 interestDue,
        uint48 maturity
    );
    event PositionDebtDecreased(
        uint64 indexed positionId,
        uint128 principalDue,
        uint128 interestDue
    );
    event PositionMaturityExtended(
        uint64 indexed positionId,
        uint48 oldMaturity,
        uint48 newMaturity
    );
    event PositionDefaulted(
        uint64 indexed positionId,
        uint128 principalDefaulted,
        uint128 interestDefaulted,
        uint128 collateralSeized
    );
    event MarketImported(uint32 indexed marketId);
    event PositionImported(uint64 indexed positionId, uint128 principalDefaulted);

    function marketCount() external view returns (uint32);

    function positionCount() external view returns (uint64);

    function marketPrincipalDue(uint32 marketId_) external view returns (uint128);

    function facilityPrincipalDue(
        address facility_,
        address debtToken_
    ) external view returns (uint256);

    function debtTokenPrincipalDue(address debtToken_) external view returns (uint256);

    function marketPrincipalDefaulted(uint32 marketId_) external view returns (uint256);

    function facilityPrincipalDefaulted(
        address facility_,
        address debtToken_
    ) external view returns (uint256);

    function debtTokenPrincipalDefaulted(address debtToken_) external view returns (uint256);

    /// @notice Returns every market matching a facility and token pair.
    /// @dev A facility may own more than one market for the same collateral and debt tokens.
    function getMarketIds(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) external view returns (uint256[] memory marketIds);

    function getMarket(uint32 marketId_) external view returns (Market memory);

    function getMarketConfigData(uint32 marketId_) external view returns (bytes memory);

    function getPosition(uint64 positionId_) external view returns (Position memory);

    function isPositionDefaulted(uint64 positionId_) external view returns (bool);

    function getPositionIdsForBorrower(address borrower_) external view returns (uint256[] memory);

    function getPositionIdsForMarket(uint32 marketId_) external view returns (uint256[] memory);

    function getPositionIdsForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view returns (uint256[] memory);

    /// @notice Returns the number of positions for a pair and the first indexed ID, if any.
    /// @dev Callers that require uniqueness must check that `count == 1` before using the ID.
    function getPositionIdForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view returns (uint256 count, uint64 positionId);

    function getActiveBorrowers(uint32 marketId_) external view returns (address[] memory);

    function activeBorrowerCount(uint32 marketId_) external view returns (uint256);

    function activeBorrowerAt(uint32 marketId_, uint256 index_) external view returns (address);

    function createMarket(
        Market calldata market_,
        bytes calldata configData_
    ) external returns (uint32 marketId);

    /// @notice Imports the next market while preserving its identifier from a previous FLOAN ledger.
    /// @dev The provided ID must equal `marketCount`; sparse or reordered imports are rejected.
    function importMarket(
        uint32 marketId_,
        Market calldata market_,
        bytes calldata configData_
    ) external;

    function setMarketConfig(
        uint32 marketId_,
        Market calldata market_,
        bytes calldata configData_
    ) external;

    function setMarketManager(uint32 marketId_, address manager_) external;

    function setMarketOriginationsEnabled(uint32 marketId_, bool enabled_) external;

    function setMarketFacility(uint32 marketId_, address facility_) external;

    function createPosition(
        uint32 marketId_,
        address borrower_
    ) external returns (uint64 positionId);

    /// @notice Imports the next position and reconstructs its indexes and aggregate accounting.
    /// @dev The provided ID must equal `positionCount`; sparse or reordered imports are rejected.
    ///      `principalDefaulted_` must be zero for non-defaulted positions.
    function importPosition(
        uint64 positionId_,
        Position calldata position_,
        uint128 principalDefaulted_
    ) external;

    function addCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external returns (uint128 collateral);

    function removeCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external returns (uint128 collateral);

    function increaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_,
        uint48 maturity_
    ) external returns (Position memory position);

    function decreaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_
    ) external returns (Position memory position);

    function extendMaturity(
        uint64 positionId_,
        uint48 newMaturity_
    ) external returns (Position memory position);

    /// @notice Closes a defaulted position and removes its debt and collateral from active totals.
    /// @dev Preserves origination and maturity fields as historical facts. The servicing facility
    ///      is responsible for custody settlement using the returned amounts.
    function defaultPosition(
        uint64 positionId_
    )
        external
        returns (uint128 principalDefaulted, uint128 interestDefaulted, uint128 collateralSeized);
}
