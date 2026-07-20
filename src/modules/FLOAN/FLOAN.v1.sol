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
abstract contract FLOANv1 is Module, IFLOANv1 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint32 internal _marketCount;
    uint64 internal _positionCount;

    mapping(uint32 marketId => Market market) internal _markets;
    mapping(address facility => mapping(address collateralToken => mapping(address debtToken => EnumerableSet.UintSet marketIds)))
        internal _marketIds;
    mapping(uint32 marketId => bytes configData) internal _marketConfigData;
    mapping(uint64 positionId => Position position) internal _positions;
    mapping(uint32 marketId => mapping(address borrower => uint64 positionIdPlusOne))
        internal _defaultPositionIds;
    mapping(uint32 marketId => EnumerableSet.UintSet positionIds) internal _positionIdsByMarket;
    mapping(address borrower => EnumerableSet.UintSet positionIds) internal _positionIdsByBorrower;
    mapping(uint32 marketId => mapping(address borrower => EnumerableSet.UintSet positionIds))
        internal _positionIdsByMarketAndBorrower;
    mapping(uint32 marketId => EnumerableSet.AddressSet borrowers)
        internal _activeBorrowersByMarket;
    mapping(uint32 marketId => mapping(address borrower => uint32 count))
        internal _activePositionCount;
    mapping(uint32 marketId => uint128 principalDue) internal _marketPrincipalDue;
    mapping(address facility => mapping(address debtToken => uint256 principalDue))
        internal _facilityPrincipalDue;
    mapping(address debtToken => uint256 principalDue) internal _debtTokenPrincipalDue;

    constructor(Kernel kernel_) Module(kernel_) {}
}
