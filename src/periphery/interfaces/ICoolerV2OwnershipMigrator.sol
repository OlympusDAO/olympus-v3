// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";

/// @title  ICoolerV2OwnershipMigrator
/// @notice Interface for the Cooler V2 Ownership Migrator contract, which allows users to migrate the ownership of a Cooler V2 position to a new address
interface ICoolerV2OwnershipMigrator {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the Cooler is not owned by the caller
    error Only_CoolerOwner();

    /// @notice Thrown when the new owner address provided does not match the authorization
    error Params_InvalidNewOwner();

    /// @notice Thrown when the new owner address is the same as the current owner
    error Params_SameOwner();

    // ========= EVENTS ========= //

    /// @notice Emitted when a position's ownership is migrated.
    event OwnershipMigrated(
        address indexed from,
        address indexed to,
        uint256 collateralAmount,
        uint256 debtAmount
    );

    // ========= FUNCTIONS ========= //

    /// @notice Preview the migration of a position.
    ///
    /// @param  owner_            The address of the current owner of the position.
    /// @param  collateralAmount_   The amount of collateral to migrate. Use type(uint128).max to migrate the entire position.
    /// @return debtToMigrate       The amount of debt that will be migrated.
    function previewMigrateOwnership(
        address owner_,
        uint128 collateralAmount_
    ) external view returns (uint256 debtToMigrate);

    /// @notice Get the collateral and debt for a user's position.
    ///
    /// @param  owner_            The address of the owner of the position.
    /// @return collateralAmount    The total amount of collateral in the position.
    /// @return debtAmount          The total amount of debt in the position.
    function userPosition(
        address owner_
    ) external view returns (uint256 collateralAmount, uint256 debtAmount);

    /// @notice Migrate ownership of a Cooler V2 position.
    ///
    /// @param  collateralAmount_       The amount of collateral to migrate. Use type(uint128).max to migrate the entire position.
    /// @param  currentOwnerAuth_   Authorization parameters for the current owner.
    /// @param  currentOwnerSig_    Authorization signature for the current owner.
    /// @param  newOwner_           Address of the new owner of the Cooler V2 position.
    /// @param  newOwnerAuth_       Authorization parameters for the new owner.
    /// @param  newOwnerSig_        Authorization signature for the new owner.
    function migrateOwnership(
        uint128 collateralAmount_,
        IMonoCooler.Authorization memory currentOwnerAuth_,
        IMonoCooler.Signature calldata currentOwnerSig_,
        address newOwner_,
        IMonoCooler.Authorization memory newOwnerAuth_,
        IMonoCooler.Signature calldata newOwnerSig_
    ) external;
}
