// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Contracts
import {Kernel, Module} from "src/Kernel.sol";

/// @title FLOAN v1
/// @notice Storage base for the fixed-term loan ledger.
// solhint-disable-next-line max-states-count
abstract contract FLOANv1 is Module, IFLOANv1 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Next sequential market identifier and number of stored markets.
    uint32 internal _marketCount;

    /// @dev Next sequential position identifier and number of stored positions.
    uint64 internal _positionCount;

    /// @dev Complete market definitions keyed by their globally unique identifiers.
    mapping(uint32 marketId => Market market) internal _markets;

    /// @dev Market IDs indexed by facility, collateral token, and debt token.
    mapping(address facility => mapping(address collateralToken => mapping(address debtToken => EnumerableSet.UintSet marketIds)))
        internal _marketIds;

    /// @dev Opaque product-specific market configuration keyed by market identifier.
    mapping(uint32 marketId => bytes configData) internal _marketConfigData;

    /// @dev Complete position records keyed by their globally unique identifiers.
    mapping(uint64 positionId => Position position) internal _positions;

    /// @dev Position IDs indexed by market.
    mapping(uint32 marketId => EnumerableSet.UintSet positionIds) internal _positionIdsByMarket;

    /// @dev Position IDs indexed by borrower across markets.
    mapping(address borrower => EnumerableSet.UintSet positionIds) internal _positionIdsByBorrower;

    /// @dev Position IDs indexed by market and borrower without imposing uniqueness.
    mapping(uint32 marketId => mapping(address borrower => EnumerableSet.UintSet positionIds))
        internal _positionIdsByMarketAndBorrower;

    /// @dev Borrowers with at least one debt-bearing position indexed by market.
    mapping(uint32 marketId => EnumerableSet.AddressSet borrowers)
        internal _activeBorrowersByMarket;

    /// @dev Number of debt-bearing positions for each market and borrower.
    mapping(uint32 marketId => mapping(address borrower => uint32 count))
        internal _activePositionCount;

    /// @notice Current credited collateral per market, denominated in the collateral token.
    mapping(uint32 marketId => uint256 collateral) public override getMarketCollateral;

    /// @notice Live principal per market, denominated in the market debt token.
    mapping(uint32 marketId => uint128 principalDue) public override getMarketPrincipalDue;

    /// @dev Live principal per facility and debt token.
    mapping(address facility => mapping(address debtToken => uint256 principalDue))
        internal _facilityPrincipalDue;

    /// @notice Live deferred interest per market, denominated in the market debt token.
    mapping(uint32 marketId => uint256 interestDue) public override getMarketInterestDue;

    /// @notice Cumulative principal defaulted per market.
    mapping(uint32 marketId => uint256 principalDefaulted)
        public
        override getMarketPrincipalDefaulted;

    constructor(Kernel kernel_) Module(kernel_) {}
}
