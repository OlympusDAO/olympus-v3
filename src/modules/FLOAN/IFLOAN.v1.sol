// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Fixed-Term Loan Module Interface
/// @notice Dependency-free ledger for fixed-term loan markets and positions.
interface IFLOANv1 {
    error FLOAN_InvalidAmount();
    error FLOAN_InvalidConfig();
    error FLOAN_InvalidMarket(uint32 marketId);
    error FLOAN_InvalidMaturity(uint48 expected, uint48 actual);
    error FLOAN_InvalidPosition(uint64 positionId);
    error FLOAN_NotManager(uint32 marketId, address caller);
    error FLOAN_MarketAlreadyExists(address facility, address collateralToken, address debtToken);
    error FLOAN_NotFacility(uint32 marketId, address caller);
    error FLOAN_OriginationsDisabled(uint32 marketId);
    error FLOAN_PrincipalCapExceeded(uint32 marketId, uint128 principalCap);
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

    function marketCount() external view returns (uint32);

    function positionCount() external view returns (uint64);

    function marketPrincipalDue(uint32 marketId_) external view returns (uint128);

    function facilityPrincipalDue(
        address facility_,
        address debtToken_
    ) external view returns (uint256);

    function debtTokenPrincipalDue(address debtToken_) external view returns (uint256);

    function getMarketId(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) external view returns (bool exists, uint32 marketId);

    function getMarket(uint32 marketId_) external view returns (Market memory);

    function getMarketConfigData(uint32 marketId_) external view returns (bytes memory);

    function getPosition(uint64 positionId_) external view returns (Position memory);

    function getPositionId(
        uint32 marketId_,
        address borrower_
    ) external view returns (bool exists, uint64 positionId);

    function getPositionForBorrower(
        uint32 marketId_,
        address borrower_
    ) external view returns (Position memory);

    function getPositionIdsForBorrower(address borrower_) external view returns (uint256[] memory);

    function getPositionIdsForMarket(uint32 marketId_) external view returns (uint256[] memory);

    function getPositionIdsForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view returns (uint256[] memory);

    function getActiveBorrowers(uint32 marketId_) external view returns (address[] memory);

    function createMarket(
        Market calldata market_,
        bytes calldata configData_
    ) external returns (uint32 marketId);

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

    function getOrCreatePosition(
        uint32 marketId_,
        address borrower_
    ) external returns (uint64 positionId);

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
}
