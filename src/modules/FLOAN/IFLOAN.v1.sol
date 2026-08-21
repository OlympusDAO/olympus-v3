// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

/// @title Fixed-Term Loan Module Interface
/// @notice Dependency-free ledger for fixed-term loan markets and positions.
interface IFLOANv1 is IERC165 {
    /// @notice The supplied amount is zero or invalid for the requested state transition.
    error FLOAN_InvalidAmount();
    /// @notice The supplied market, position, or configuration fields are inconsistent.
    error FLOAN_InvalidConfig();
    /// @notice The market identifier does not refer to an existing market.
    /// @param marketId Invalid market identifier.
    error FLOAN_InvalidMarket(uint32 marketId);
    /// @notice A debt increase or extension supplied a maturity inconsistent with the position.
    /// @param expected Existing or minimum expected maturity.
    /// @param actual Supplied maturity.
    error FLOAN_InvalidMaturity(uint48 expected, uint48 actual);
    /// @notice The requested maturity exceeds the market's configured horizon.
    /// @param requested Requested maturity timestamp.
    /// @param maximum Maximum permitted maturity timestamp.
    error FLOAN_MaturityHorizonExceeded(uint48 requested, uint48 maximum);
    /// @notice The position identifier does not refer to an existing position.
    /// @param positionId Invalid position identifier.
    error FLOAN_InvalidPosition(uint64 positionId);
    /// @notice An active-borrower index is outside the market's current set.
    error FLOAN_ActiveBorrowerIndexOutOfBounds();
    /// @notice The caller is not the manager of the specified market.
    /// @param marketId Market whose configuration was targeted.
    /// @param caller Unauthorized caller.
    error FLOAN_NotManager(uint32 marketId, address caller);
    /// @notice The caller is not the facility servicing the specified market.
    /// @param marketId Market whose position was targeted.
    /// @param caller Unauthorized caller.
    error FLOAN_NotFacility(uint32 marketId, address caller);
    /// @notice The market does not permit collateral additions, new debt, or extensions.
    /// @param marketId Disabled market identifier.
    error FLOAN_OriginationsDisabled(uint32 marketId);
    /// @notice The resulting live principal would exceed the market cap.
    /// @param marketId Capped market identifier.
    /// @param principalCap Configured principal cap.
    error FLOAN_PrincipalCapExceeded(uint32 marketId, uint128 principalCap);
    /// @notice A required token, manager, facility, or borrower address is zero.
    error FLOAN_ZeroAddress();

    /// @notice Caller-supplied configuration used to create a market.
    /// @dev Token decimals and origination state are derived by the module and are therefore not
    ///      caller-supplied fields.
    /// @param collateralToken Token accepted as collateral.
    /// @param debtToken Token denominating principal and deferred interest.
    /// @param manager Address authorized to configure and rotate this market.
    /// @param facility Policy authorized to mutate positions belonging to this market.
    /// @param configId Product configuration schema identifier for `configData`.
    /// @param principalCap Maximum live principal in debt-token decimals.
    /// @param termLength Standard origination term in seconds.
    /// @param maxMaturityHorizon Maximum maturity distance from the current timestamp.
    /// @param collateralFactorBps Collateral value recognized by the facility, in basis points.
    /// @param minCollateralRatioBps Minimum collateral ratio, in basis points.
    /// @param baseFeeBps Base origination fee, in basis points.
    struct MarketInput {
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
    }

    /// @notice Fixed-term loan market definition and mutable standard configuration.
    /// @dev Token identity, manager, facility, config ID, and decimals are immutable except through
    ///      their dedicated authority functions where one exists.
    /// @param collateralToken Token accepted as collateral.
    /// @param debtToken Token denominating principal and deferred interest.
    /// @param manager Address authorized to configure and rotate this market.
    /// @param facility Policy authorized to mutate positions belonging to this market.
    /// @param configId Product configuration schema identifier for `configData`.
    /// @param principalCap Maximum live principal in debt-token decimals.
    /// @param termLength Standard origination term in seconds.
    /// @param maxMaturityHorizon Maximum maturity distance from the current timestamp.
    /// @param collateralFactorBps Collateral value recognized by the facility, in basis points.
    /// @param minCollateralRatioBps Minimum collateral ratio, in basis points.
    /// @param baseFeeBps Base origination fee, in basis points.
    /// @param collateralDecimals Decimal precision of the collateral token.
    /// @param debtDecimals Decimal precision of the debt and deferred-interest token.
    /// @param originationsEnabled Whether new debt and maturity extensions are enabled.
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

    /// @notice Fixed-term position owned by one borrower in one market.
    /// @param borrower Borrower associated with the position.
    /// @param marketId Market containing the position.
    /// @param collateral Current credited collateral in collateral-token decimals.
    /// @param principalDrawn Principal originated during the current active debt episode.
    /// @param principalDue Current outstanding principal in debt-token decimals.
    /// @param interestDue Current deferred interest in debt-token decimals.
    /// @param maturity Current maturity timestamp.
    /// @param lastBorrowBlock Block number of the latest principal increase.
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

    /// @notice Emitted when a market is created with the next sequential identifier.
    event MarketCreated(
        uint32 indexed marketId,
        address indexed collateralToken,
        address indexed debtToken,
        address manager,
        address facility,
        bytes16 configId
    );
    /// @notice Emitted when typed or opaque market configuration changes.
    /// @dev Consumers should read the complete resulting configuration from the module.
    event MarketConfigUpdated(uint32 indexed marketId);
    /// @notice Emitted when market configuration authority is transferred.
    event MarketManagerSet(
        uint32 indexed marketId,
        address indexed oldManager,
        address indexed newManager
    );
    /// @notice Emitted when a market's origination state changes.
    event MarketOriginationsSet(uint32 indexed marketId, bool enabled);
    /// @notice Emitted when a market's servicing facility changes.
    event MarketFacilitySet(
        uint32 indexed marketId,
        address indexed oldFacility,
        address indexed newFacility
    );
    /// @notice Emitted when an empty position is created.
    event PositionCreated(
        uint64 indexed positionId,
        uint32 indexed marketId,
        address indexed borrower
    );
    /// @notice Emitted after a position's credited collateral changes.
    event PositionCollateralChanged(uint64 indexed positionId, uint128 collateral);
    /// @notice Emitted after principal or deferred interest is added to a position.
    event PositionDebtIncreased(
        uint64 indexed positionId,
        uint128 principalDrawn,
        uint128 principalDue,
        uint128 interestDue,
        uint48 maturity
    );
    /// @notice Emitted after principal or deferred interest is removed from a position.
    event PositionDebtDecreased(
        uint64 indexed positionId,
        uint128 principalDue,
        uint128 interestDue
    );
    /// @notice Emitted after an active position's maturity is extended.
    event PositionMaturityExtended(
        uint64 indexed positionId,
        uint48 oldMaturity,
        uint48 newMaturity
    );
    /// @notice Emitted before a fully repaid position's episode fields are cleared.
    event PositionClosed(
        uint64 indexed positionId,
        uint32 indexed marketId,
        address indexed borrower,
        uint128 collateral,
        uint128 principalDrawn,
        uint48 maturity,
        uint32 lastBorrowBlock
    );
    /// @notice Emitted with the pre-default snapshot after financial and episode fields are cleared.
    event PositionDefaulted(
        uint64 indexed positionId,
        uint32 indexed marketId,
        address indexed borrower,
        uint128 principalDrawn,
        uint128 principalDefaulted,
        uint128 interestDefaulted,
        uint128 collateralSeized,
        uint48 maturity,
        uint32 lastBorrowBlock
    );

    /// @notice Returns the next market identifier and number of stored markets.
    /// @return marketCount Next market identifier and number of stored markets.
    function getMarketCount() external view returns (uint32 marketCount);

    /// @notice Returns the next position identifier and number of stored positions.
    /// @return positionCount Next position identifier and number of stored positions.
    function getPositionCount() external view returns (uint64 positionCount);

    /// @notice Returns current credited collateral for one market.
    /// @dev Returns zero when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return collateral Current collateral in the market collateral token's decimals.
    function getMarketCollateral(uint32 marketId_) external view returns (uint256 collateral);

    /// @notice Returns live principal for one market.
    /// @dev Returns zero when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return principalDue Live principal in the market debt token's decimals.
    function getMarketPrincipalDue(uint32 marketId_) external view returns (uint128 principalDue);

    /// @notice Returns live principal serviced by a facility for one debt token.
    /// @param facility_ Facility to query.
    /// @param debtToken_ Debt token used to scope the aggregate.
    /// @return principalDue Live principal in `debtToken_` decimals.
    function getFacilityPrincipalDue(
        address facility_,
        address debtToken_
    ) external view returns (uint256 principalDue);

    /// @notice Returns live deferred interest for one market.
    /// @dev Returns zero when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return interestDue Live deferred interest in the market debt token's decimals.
    function getMarketInterestDue(uint32 marketId_) external view returns (uint256 interestDue);

    /// @notice Returns cumulative principal defaulted by one market.
    /// @dev Returns zero when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return principalDefaulted Historical principal in the market debt token's decimals.
    function getMarketPrincipalDefaulted(
        uint32 marketId_
    ) external view returns (uint256 principalDefaulted);

    /// @notice Returns every market matching a facility and token pair.
    /// @dev A facility may own more than one market for the same collateral and debt tokens.
    /// @param facility_ Facility to query.
    /// @param collateralToken_ Collateral token to query.
    /// @param debtToken_ Debt token to query.
    /// @return marketIds Matching market identifiers.
    function getMarketIds(
        address facility_,
        address collateralToken_,
        address debtToken_
    ) external view returns (uint256[] memory marketIds);

    /// @notice Returns a market definition.
    /// @dev Reverts when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return market Stored market definition.
    function getMarket(uint32 marketId_) external view returns (Market memory market);

    /// @notice Returns opaque product configuration for a market.
    /// @dev Reverts when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return configData Opaque data interpreted according to the market's `configId`.
    function getMarketConfigData(uint32 marketId_) external view returns (bytes memory configData);

    /// @notice Returns a position.
    /// @dev Reverts when `positionId_` does not identify a stored position.
    /// @param positionId_ Position to query.
    /// @return position Stored position.
    function getPosition(uint64 positionId_) external view returns (Position memory position);

    /// @notice Returns every position ID indexed to a borrower.
    /// @param borrower_ Borrower to query.
    /// @return positionIds Matching position identifiers.
    function getPositionIdsForBorrower(
        address borrower_
    ) external view returns (uint256[] memory positionIds);

    /// @notice Returns every position ID indexed to a market.
    /// @dev Returns an empty array when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return positionIds Matching position identifiers.
    function getPositionIdsForMarket(
        uint32 marketId_
    ) external view returns (uint256[] memory positionIds);

    /// @notice Returns every position ID indexed to both a market and borrower.
    /// @dev Returns an empty array when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @param borrower_ Borrower to query.
    /// @return positionIds Matching position identifiers.
    function getPositionIdsForMarketAndBorrower(
        uint32 marketId_,
        address borrower_
    ) external view returns (uint256[] memory positionIds);

    /// @notice Returns one position ID indexed to both a market and borrower.
    /// @dev Returns `(false, 0)` when `index_` is outside the indexed positions, including when
    ///      `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @param borrower_ Borrower to query.
    /// @param index_ Zero-based position index.
    /// @return exists Whether a position exists at `index_`.
    /// @return positionId Position identifier at `index_`, or zero when absent.
    function getPositionIdForMarketAndBorrowerAt(
        uint32 marketId_,
        address borrower_,
        uint256 index_
    ) external view returns (bool exists, uint64 positionId);

    /// @notice Returns borrowers with at least one active position in a market.
    /// @dev Returns an empty array when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return borrowers Active borrower addresses.
    function getActiveBorrowers(
        uint32 marketId_
    ) external view returns (address[] memory borrowers);

    /// @notice Returns the number of active borrowers in a market.
    /// @dev Returns zero when `marketId_` does not identify a stored market.
    /// @param marketId_ Market to query.
    /// @return count Number of active borrowers.
    function getActiveBorrowerCount(uint32 marketId_) external view returns (uint256 count);

    /// @notice Returns the active borrower at an EnumerableSet index.
    /// @dev Reverts with `FLOAN_InvalidMarket` for an invalid market or
    ///      `FLOAN_ActiveBorrowerIndexOutOfBounds` for an index at/above the current count.
    ///      Ordering is unstable when borrowers are removed.
    /// @param marketId_ Market to query.
    /// @param index_ Zero-based active-borrower index.
    /// @return borrower Active borrower stored at `index_`.
    function getActiveBorrowerAt(
        uint32 marketId_,
        uint256 index_
    ) external view returns (address borrower);

    /// @notice Creates a market with the next sequential identifier.
    /// @dev Kernel-permissioned. Reverts when a required identity address is zero, the standard
    ///      market configuration is invalid, or either token's decimals cannot be read or exceed 77.
    /// @param market_ Initial market input. Token decimals are read from the token contracts.
    /// @param configData_ Opaque product configuration.
    /// @return marketId Assigned market identifier.
    function createMarket(
        MarketInput calldata market_,
        bytes calldata configData_
    ) external returns (uint32 marketId);

    /// @notice Sets a market's live-principal cap.
    /// @dev Kernel-permissioned and manager-only. Reverts for an invalid market, a caller other
    ///      than its manager, or a cap below live market principal.
    /// @param marketId_ Market to configure.
    /// @param principalCap_ New live-principal cap in debt-token decimals.
    function setMarketPrincipalCap(uint32 marketId_, uint128 principalCap_) external;

    /// @notice Sets a market's term, horizon, and collateral-risk fields.
    /// @dev Kernel-permissioned and manager-only. Reverts for an invalid market, a caller other
    ///      than its manager, zero term, a finite horizon at or below term, or a collateral factor
    ///      above 10,000 basis points.
    /// @param marketId_ Market to configure.
    /// @param termLength_ Standard origination term in seconds.
    /// @param maxMaturityHorizon_ Maximum permitted maturity distance in seconds.
    /// @param collateralFactorBps_ Recognized collateral value in basis points.
    /// @param minCollateralRatioBps_ Minimum collateral ratio in basis points.
    function setMarketRiskConfig(
        uint32 marketId_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_
    ) external;

    /// @notice Sets a market's standard base fee.
    /// @dev Kernel-permissioned and manager-only. Reverts for an invalid market, a caller other
    ///      than its manager, or `baseFeeBps_` above 10,000.
    /// @param marketId_ Market to configure.
    /// @param baseFeeBps_ New base fee in basis points.
    function setMarketBaseFee(uint32 marketId_, uint16 baseFeeBps_) external;

    /// @notice Sets opaque product configuration for a market.
    /// @dev Kernel-permissioned and manager-only. Reverts for an invalid market or a caller other
    ///      than its manager.
    /// @param marketId_ Market to configure.
    /// @param configData_ Opaque product configuration interpreted according to `configId`.
    function setMarketConfigData(uint32 marketId_, bytes calldata configData_) external;

    /// @notice Transfers market configuration authority.
    /// @dev Kernel-permissioned and current-manager-only. Reverts for a zero manager, invalid
    ///      market, or caller other than the current manager.
    /// @param marketId_ Market to configure.
    /// @param manager_ New manager address.
    function setMarketManager(uint32 marketId_, address manager_) external;

    /// @notice Sets whether collateral additions, new debt, and maturity extensions are enabled.
    /// @dev Kernel-permissioned and manager-only. Reverts for an invalid market or a caller other
    ///      than its manager. Disabling does not block repayment or collateral withdrawals.
    /// @param marketId_ Market to configure.
    /// @param enabled_ Whether collateral additions, new debt, and extensions are permitted.
    function setMarketOriginationsEnabled(uint32 marketId_, bool enabled_) external;

    /// @notice Transfers position-servicing authority and its live principal aggregate.
    /// @dev Kernel-permissioned and manager-only. Reverts for a zero facility, invalid market, or
    ///      caller other than its manager. Historical default aggregates are not moved.
    /// @param marketId_ Market to configure.
    /// @param facility_ New servicing facility.
    function setMarketFacility(uint32 marketId_, address facility_) external;

    /// @notice Creates an empty position with the next sequential identifier.
    /// @dev Kernel-permissioned. Reverts for an invalid market, a caller other than its facility,
    ///      disabled originations, or a zero borrower.
    /// @param marketId_ Market that owns the position.
    /// @param borrower_ Position borrower.
    /// @return positionId Assigned position identifier.
    function createPosition(
        uint32 marketId_,
        address borrower_
    ) external returns (uint64 positionId);

    /// @notice Increases credited collateral on a position.
    /// @dev Kernel-permissioned. Reverts for an invalid position, a caller other than the position
    ///      market's facility, disabled originations, or a zero amount.
    /// @param positionId_ Position to mutate.
    /// @param amount_ Collateral increase in collateral-token decimals.
    /// @return collateral Resulting credited collateral.
    function addCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external returns (uint128 collateral);

    /// @notice Decreases credited collateral on a position.
    /// @dev Kernel-permissioned. Reverts for an invalid position, a caller other than the position
    ///      market's facility, zero amount, or amount above current collateral.
    /// @param positionId_ Position to mutate.
    /// @param amount_ Collateral decrease in collateral-token decimals.
    /// @return collateral Resulting credited collateral.
    function removeCollateral(
        uint64 positionId_,
        uint128 amount_
    ) external returns (uint128 collateral);

    /// @notice Increases principal and optional deferred interest for a position.
    /// @dev Kernel-permissioned. Reverts for an invalid position, caller other than the facility,
    ///      disabled originations, invalid amount or maturity, a maturity differing from
    ///      the active episode, or resulting principal above the cap. A new episode requires
    ///      nonzero principal; an active episode may accrue interest alone.
    /// @param positionId_ Position to mutate.
    /// @param principal_ Principal increase in debt-token decimals.
    /// @param interest_ Deferred-interest increase in debt-token decimals.
    /// @param maturity_ Position maturity, which must match an existing active debt episode.
    /// @return position Resulting position state.
    function increaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_,
        uint48 maturity_
    ) external returns (Position memory position);

    /// @notice Decreases principal and optional deferred interest for a position.
    /// @dev Kernel-permissioned. Reverts for an invalid position, caller other than the facility,
    ///      zero combined payment, no outstanding debt, or payment above either balance.
    ///      Clearing both balances ends the debt episode and may remove the active borrower.
    /// @param positionId_ Position to mutate.
    /// @param principal_ Principal decrease in debt-token decimals.
    /// @param interest_ Deferred-interest decrease in debt-token decimals.
    /// @return position Resulting position state.
    function decreaseDebt(
        uint64 positionId_,
        uint128 principal_,
        uint128 interest_
    ) external returns (Position memory position);

    /// @notice Extends an active position's maturity.
    /// @dev Kernel-permissioned. Reverts for an invalid position, caller other than the facility,
    ///      no outstanding debt, disabled originations, non-increasing or elapsed
    ///      maturity, or a maturity beyond the configured horizon.
    /// @param positionId_ Position to mutate.
    /// @param newMaturity_ New maturity timestamp.
    /// @return position Resulting position state.
    function extendMaturity(
        uint64 positionId_,
        uint48 newMaturity_
    ) external returns (Position memory position);

    /// @notice Defaults the current debt episode and removes its debt and collateral from live totals.
    /// @dev Kernel-permissioned. Reverts for an invalid position, caller other than the facility,
    ///      or no outstanding debt. Emits the complete pre-default episode snapshot, then clears
    ///      every financial and episode field so the retained position ID can be originated again.
    ///      The facility remains responsible for custody settlement using the returned amounts.
    /// @param positionId_ Position to default.
    /// @return principalDefaulted Principal removed from active accounting.
    /// @return interestDefaulted Deferred interest removed from the position.
    /// @return collateralSeized Collateral removed from the position.
    function defaultPosition(
        uint64 positionId_
    )
        external
        returns (uint128 principalDefaulted, uint128 interestDefaulted, uint128 collateralSeized);
}
