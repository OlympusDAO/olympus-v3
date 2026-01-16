// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
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

    /// @notice Thrown when the amount exceeds the user's allocation
    ///
    /// @param requested The amount requested to migrate
    /// @param allocated The user's allocated amount from the merkle tree
    /// @param migrated The amount already migrated by the user
    error AmountExceedsAllowance(uint256 requested, uint256 allocated, uint256 migrated);

    /// @notice Thrown when the migration cap would be exceeded
    ///
    /// @param amount The amount requested to migrate
    /// @param remaining The remaining MINTR approval for the migrator contract
    error CapExceeded(uint256 amount, uint256 remaining);

    /// @notice Thrown when the OHM v2 amount after gOHM conversion is zero
    /// @dev    This can happen when the input OHM v1 amount is very small and
    ///         gOHM conversion rounds down to zero
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

    /// @notice The gOHM token contract used for conversion calculations
    /// @dev    Used to calculate OHM v2 amount via balanceTo/balanceFrom to match production flow
    ///
    /// @return gOHM_ The gOHM token
    function gOHM() external view returns (address gOHM_);

    /// @notice The current merkle root for verifying eligible claims
    ///
    /// @return merkleRoot_ The current merkle root
    function merkleRoot() external view returns (bytes32 merkleRoot_);

    /// @notice The amount a user has migrated under the current root
    /// @param account_ The account to check
    /// @return migratedAmount_ The amount migrated by the user
    function migratedAmounts(address account_) external view returns (uint256 migratedAmount_);

    /// @notice The remaining amount of OHM that can be minted by this contract
    /// @dev    Returns the actual MINTR mint approval, not a stored value. This is the
    ///         remaining amount available for migration and is always in sync with MINTR state.
    ///
    /// @return remaining_ The remaining OHM that can be minted
    function remainingMintApproval() external view returns (uint256 remaining_);

    /// @notice The total amount of OHM v1 migrated so far
    ///
    /// @return totalMigrated_ The total migrated amount
    function totalMigrated() external view returns (uint256 totalMigrated_);

    // ============ FUNCTIONS ============ //

    /// @notice Migrate OHM v1 to OHM v2
    /// @dev    User must approve this contract to transfer their OHM v1
    ///         Users can migrate any amount up to their allocated amount in multiple transactions
    ///
    /// @param amount_ The amount of OHM v1 to migrate (9 decimals)
    /// @param proof_ The merkle proof proving the user is eligible
    /// @param allocatedAmount_ The user's allocated amount from the merkle tree
    function migrate(uint256 amount_, bytes32[] calldata proof_, uint256 allocatedAmount_) external;

    /// @notice Update the merkle root for eligible claims
    ///
    /// @param merkleRoot_ The new merkle root
    function setMerkleRoot(bytes32 merkleRoot_) external;

    /// @notice Update the migration cap
    /// @dev    Queries the current MINTR approval and adjusts it to the target cap.
    ///         This ensures the cap is always in sync with MINTR state.
    ///
    /// @param cap_ The new migration cap (9 decimals)
    function setMigrationCap(uint256 cap_) external;

    /// @notice Verify if a claim is valid for a given account and allocated amount
    ///
    /// @param account_ The account to verify
    /// @param allocatedAmount_ The allocated amount to verify
    /// @param proof_ The merkle proof
    /// @return valid_ True if the claim is valid
    function verifyClaim(
        address account_,
        uint256 allocatedAmount_,
        bytes32[] calldata proof_
    ) external view returns (bool valid_);
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
