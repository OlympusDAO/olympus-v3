// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

/// @title ILegacyMigrator
/// @notice Interface for the LegacyMigrator policy that allows OHM v1 holders to migrate to OHM v2
///         via merkle proof verification
interface ILegacyMigrator is IEnabler, IVersioned {
    // ============ EVENTS ============ //

    /// @notice Emitted when a user successfully migrates OHM v1 to OHM v2
    ///
    /// @param user The address of the user migrating
    /// @param ohmV1Amount The amount of OHM v1 burned
    /// @param ohmV2Amount The amount of OHM v2 minted
    event Migrated(address indexed user, uint256 ohmV1Amount, uint256 ohmV2Amount);

    /// @notice Emitted when the merkle root is updated
    ///
    /// @param newRoot The new merkle root
    /// @param updater The address that updated the root
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);

    /// @notice Emitted when the migration cap is updated
    ///
    /// @param newCap The new migration cap
    /// @param oldCap The old migration cap
    event MigrationCapUpdated(uint256 indexed newCap, uint256 indexed oldCap);

    // ============ ERRORS ============ //

    /// @notice Thrown when the provided merkle proof is invalid
    error InvalidProof();

    /// @notice Thrown when the amount exceeds the user's allowance
    error AmountExceedsAllowance();

    /// @notice Thrown when the migration cap would be exceeded
    error CapExceeded();

    /// @notice Thrown when the amount is zero
    error ZeroAmount();

    /// @notice Thrown when an address parameter is zero
    error ZeroAddress();

    // ============ STATE VARIABLES ============ //

    /// @notice The OHM v1 token contract
    ///
    /// @return ohmV1_ The OHM v1 token
    function ohmV1() external view returns (IERC20 ohmV1_);

    /// @notice The OHM v2 token contract
    ///
    /// @return ohmV2_ The OHM v2 token
    function ohmV2() external view returns (IERC20 ohmV2_);

    /// @notice The current merkle root for verifying eligible claims
    ///
    /// @return merkleRoot_ The current merkle root
    function merkleRoot() external view returns (bytes32 merkleRoot_);

    /// @notice Whether the user has migrated under the current root
    /// @param account_ The account to check
    /// @return hasMigrated_ True if the user has migrated
    function hasMigrated(address account_) external view returns (bool hasMigrated_);

    /// @notice The maximum amount of OHM v2 that can be migrated
    ///
    /// @return cap_ The migration cap
    function migrationCap() external view returns (uint256 cap_);

    /// @notice The total amount of OHM v2 migrated so far
    ///
    /// @return totalMigrated_ The total migrated amount
    function totalMigrated() external view returns (uint256 totalMigrated_);

    // ============ FUNCTIONS ============ //

    /// @notice Migrate OHM v1 to OHM v2
    /// @dev    User must approve this contract to transfer their OHM v1
    ///         Users must migrate their full allowance in one transaction (all-or-nothing)
    ///
    /// @param amount_ The amount of OHM v1 to migrate (9 decimals) - must equal full allowance
    /// @param proof_ The merkle proof proving the user is eligible for this amount
    function migrate(uint256 amount_, bytes32[] calldata proof_) external;

    /// @notice Update the merkle root for eligible claims
    /// @dev    Resets all migrated amounts to zero
    ///
    /// @param merkleRoot_ The new merkle root
    function setMerkleRoot(bytes32 merkleRoot_) external;

    /// @notice Update the migration cap
    /// @dev    Adjusts MINTR approval accordingly
    ///
    /// @param cap_ The new migration cap (9 decimals)
    function setMigrationCap(uint256 cap_) external;

    /// @notice Verify if a claim is valid for a given account and amount
    /// @param account_ The account to verify
    /// @param amount_ The amount to verify
    /// @param proof_ The merkle proof
    /// @return valid_ True if the claim is valid
    function verifyClaim(
        address account_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) external view returns (bool valid_);
}
