// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

// ============  INTERFACES ============ //

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC20BurnableMintable} from "src/interfaces/IERC20BurnableMintable.sol";
import {ILegacyMigrator} from "src/interfaces/ILegacyMigrator.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// ============  LIBRARIES ============ //

import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";

// ============  EXTERNAL CONTRACTS ============ //

import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

// ============  INTERNAL CONTRACTS ============ //

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title LegacyMigrator
/// @notice Policy to allow OHM v1 holders to migrate to OHM v2 via merkle proof verification
/// @dev    Inherits from Policy, RolesConsumer, PolicyEnabler, IVersioned, and ILegacyMigrator
///
///         Migration flow (all-or-nothing):
///         1. User has OHM v1 balance
///         2. User proves eligibility via merkle proof
///         3. User transfers OHM v1 to contract
///         4. Contract mints OHM v2 to user (1:1, same decimals)
///         5. User marked as migrated (cannot migrate again)
///
///         Admin functions:
///         - setMerkleRoot: Update eligibility tree
///         - setMigrationCap: Update global cap and MINTR approval
///         - enable/disable: Emergency pause/resume
contract LegacyMigrator is Policy, RolesConsumer, PolicyEnabler, IVersioned, ILegacyMigrator {
    using MerkleProof for bytes32[];

    // =========  CONSTANTS ========= //

    /// @notice The role required to set merkle root and migration cap
    bytes32 internal constant LEGACY_MIGRATION_ADMIN_ROLE = "legacy_migration_admin";

    // =========  STATE VARIABLES ========= //

    /// @notice The MINTR module reference for minting OHM v2
    MINTRv1 internal MINTR;

    // ROLES is already declared in RolesConsumer

    /// @notice The OHM v1 token contract (9 decimals)
    IERC20 internal immutable _ohmV1;

    /// @notice The OHM v2 token contract from MINTR (9 decimals)
    /// @dev    Set in configureDependencies via MINTR.ohm()
    OlympusERC20Token internal _ohmV2;

    /// @inheritdoc ILegacyMigrator
    bytes32 public override merkleRoot;

    /// @inheritdoc ILegacyMigrator
    mapping(address => bool) public override hasMigrated;

    /// @notice Array of users who have migrated for resetting when merkle root changes
    address[] public users;

    /// @inheritdoc ILegacyMigrator
    uint256 public override migrationCap;

    /// @inheritdoc ILegacyMigrator
    uint256 public override totalMigrated;

    // =========  CONSTRUCTOR ========= //

    constructor(Kernel kernel_, IERC20 ohmV1_) Policy(kernel_) {
        if (address(ohmV1_) == address(0)) revert ZeroAddress();
        _ohmV1 = ohmV1_;
    }

    // =========  INTERFACE GETTERS ========= //

    /// @inheritdoc ILegacyMigrator
    function ohmV1() external view returns (IERC20 ohmV1_) {
        return _ohmV1;
    }

    /// @inheritdoc ILegacyMigrator
    function ohmV2() external view returns (IERC20 ohmV2_) {
        return IERC20(address(_ohmV2));
    }

    // =========  POLICY SETUP ========= //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        bytes memory expected = abi.encode([1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        // Set ohmV2 from MINTR
        _ohmV2 = MINTR.ohm();
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");

        requests = new Permissions[](3);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);
    }

    // =========  VERSION ========= //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    // =========  ERC165 ========= //

    /// @notice ERC165 interface support
    /// @dev    Supports IERC165, IVersioned, ILegacyMigrator, and IEnabler (via PolicyEnabler)
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            interfaceId == type(ILegacyMigrator).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // =========  MIGRATE FUNCTIONS ========= //

    /// @notice Internal function to verify a merkle proof
    /// @param account_ The account to verify
    /// @param amount_ The amount to verify
    /// @param proof_ The merkle proof
    /// @return valid True if the proof is valid
    function _verifyClaim(
        address account_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view returns (bool valid) {
        // Generate leaf for this account and amount
        bytes32 leaf = keccak256(abi.encode(account_, amount_));

        // Verify proof against current root
        return proof_.verify(merkleRoot, leaf);
    }

    /// @inheritdoc ILegacyMigrator
    function verifyClaim(
        address account_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) external view returns (bool valid_) {
        return _verifyClaim(account_, amount_, proof_);
    }

    /// @inheritdoc ILegacyMigrator
    function migrate(uint256 amount_, bytes32[] calldata proof_) external onlyEnabled {
        // Check amount is not zero
        if (amount_ == 0) revert ZeroAmount();

        // Verify merkle proof for this claim
        if (!_verifyClaim(msg.sender, amount_, proof_)) revert InvalidProof();

        // Check if user has already migrated under current root
        if (hasMigrated[msg.sender]) revert AmountExceedsAllowance();

        // Check that total migration doesn't exceed cap (1:1 conversion)
        if (totalMigrated + amount_ > migrationCap) revert CapExceeded();

        // Mark user as migrated
        hasMigrated[msg.sender] = true;

        // Track user for resetting when merkle root changes
        users.push(msg.sender);

        // Burn OHM v1 from user (user must have approved this contract)
        IERC20BurnableMintable(address(_ohmV1)).burnFrom(msg.sender, amount_);

        // Mint OHM v2 to user (1:1 conversion, same decimals)
        // Note: MINTR approval is pre-set via setMigrationCap, not here
        MINTR.mintOhm(msg.sender, amount_);

        // Update tracking
        totalMigrated += amount_;

        emit Migrated(msg.sender, amount_, amount_);
    }

    /// @inheritdoc ILegacyMigrator
    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(LEGACY_MIGRATION_ADMIN_ROLE) {
        // Reset migration status for all tracked users
        for (uint256 i = 0; i < users.length; i++) {
            hasMigrated[users[i]] = false;
        }

        // Clear the users array
        delete users;

        // Update merkle root
        merkleRoot = merkleRoot_;
        emit MerkleRootUpdated(merkleRoot_, msg.sender);
    }

    /// @inheritdoc ILegacyMigrator
    function setMigrationCap(uint256 cap_) external onlyAdminRole {
        uint256 oldCap = migrationCap;

        // Adjust MINTR approval accordingly
        if (cap_ > oldCap) {
            // Increase approval
            MINTR.increaseMintApproval(address(this), cap_ - oldCap);
        } else if (cap_ < oldCap) {
            // Decrease approval
            MINTR.decreaseMintApproval(address(this), oldCap - cap_);
        }

        migrationCap = cap_;
        emit MigrationCapUpdated(cap_, oldCap);
    }
}
