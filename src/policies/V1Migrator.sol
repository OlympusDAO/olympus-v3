// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// ============  INTERFACES ============ //

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC20BurnableMintable} from "src/interfaces/IERC20BurnableMintable.sol";
import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";

// ============  LIBRARIES ============ //

import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";

// ============  EXTERNAL CONTRACTS ============ //

// ============  INTERNAL CONTRACTS ============ //

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title V1Migrator
/// @notice Policy to allow OHM v1 holders to migrate to OHM v2 via merkle proof verification
/// @dev    Inherits from Policy, RolesConsumer, PolicyEnabler, IVersioned, and IV1Migrator
///
///         Migration flow (partial migrations allowed):
///         1. User has OHM v1 balance
///         2. User proves eligibility via merkle proof with their allocated amount
///         3. User can migrate any amount up to their allocation in multiple transactions
///         4. Contract calculates OHM v2 amount using gOHM conversion (to match production flow):
///            - Convert OHM v1 to gOHM via gOHM.balanceTo(ohmV1Amount)
///            - Convert gOHM back to OHM v2 via gOHM.balanceFrom(gOHMAmount)
///            - This matches the production flow: OHM v1 -> gOHM -> OHM v2
///            - When gOHM index is not at base level, the result may be slightly less due to rounding
///         5. Contract burns OHM v1 and mints calculated OHM v2 amount to user
///         6. User's migrated amount is tracked by OHM v1 amount (original allocation)
///
///         Admin functions:
///         - setMerkleRoot: Update eligibility tree (resets all migrated amounts)
///         - setMigrationCap: Update global cap and MINTR approval
///         - enable/disable: Emergency pause/resume
contract V1Migrator is Policy, RolesConsumer, PolicyEnabler, IVersioned, IV1Migrator {
    using MerkleProof for bytes32[];

    // =========  CONSTANTS ========= //

    /// @notice The role required to set merkle root
    bytes32 internal constant LEGACY_MIGRATION_ADMIN_ROLE = "legacy_migration_admin";

    // =========  STATE VARIABLES ========= //

    /// @notice The MINTR module reference for minting OHM v2
    MINTRv1 internal MINTR;

    // ROLES is already declared in RolesConsumer

    /// @notice The gOHM token contract used for OHM v2 amount calculation
    IgOHM internal immutable _GOHM;

    /// @notice The OHM v1 token contract (9 decimals)
    IERC20 internal immutable _OHMV1;

    /// @notice The OHM v2 token contract from MINTR (9 decimals)
    /// @dev    Set in configureDependencies via MINTR.ohm()
    IERC20 internal _OHMV2;

    /// @inheritdoc IV1Migrator
    bytes32 public override merkleRoot;

    /// @notice Current merkle root nonce for invalidating old migrations on root update
    uint256 internal _currentMerkleNonce = 1;

    /// @notice Mapping of user => nonce => migrated amount
    /// @dev    Nonce-based invalidation allows O(1) merkle root updates
    mapping(address user => mapping(uint256 nonce => uint256 amount)) private _migratedAmounts;

    /// @inheritdoc IV1Migrator
    uint256 public override totalMigrated;

    // =========  CONSTRUCTOR ========= //

    constructor(Kernel kernel_, IERC20 ohmV1_, IgOHM gOHM_, bytes32 merkleRoot_) Policy(kernel_) {
        if (address(ohmV1_) == address(0)) revert ZeroAddress();
        if (address(gOHM_) == address(0)) revert ZeroAddress();
        _OHMV1 = ohmV1_;
        _GOHM = gOHM_;

        // Set the merkle root
        merkleRoot = merkleRoot_;
        emit MerkleRootUpdated(merkleRoot_, msg.sender);
    }

    // =========  INTERFACE GETTERS ========= //

    /// @inheritdoc IV1Migrator
    function ohmV1() external view returns (IERC20 ohmV1_) {
        return _OHMV1;
    }

    /// @inheritdoc IV1Migrator
    function ohmV2() external view returns (IERC20 ohmV2_) {
        return _OHMV2;
    }

    /// @inheritdoc IV1Migrator
    function gOHM() external view returns (address gOHM_) {
        return address(_GOHM);
    }

    /// @inheritdoc IV1Migrator
    function remainingMintApproval() external view returns (uint256 remaining_) {
        remaining_ = MINTR.mintApproval(address(this));
    }

    /// @inheritdoc IV1Migrator
    /// @dev    Returns the migrated amount for the current merkle root nonce
    function migratedAmounts(address account_) external view returns (uint256 migratedAmount_) {
        migratedAmount_ = _migratedAmounts[account_][_currentMerkleNonce];
    }

    /// @notice Calculate OHM v2 amount from OHM v1 amount using gOHM conversion
    /// @dev    Used by both migrate() and previewMigrate() to ensure consistency
    /// @param amount_ The OHM v1 amount (9 decimals)
    /// @return ohmV2Amount_ The OHM v2 amount (9 decimals), or 0 if conversion rounds to zero
    function _calculateOHMv2Amount(uint256 amount_) internal view returns (uint256 ohmV2Amount_) {
        // Migration flow: OHM v1 -> gOHM (balanceTo) -> OHM v2 (balanceFrom)
        uint256 gohmAmount = _GOHM.balanceTo(amount_);
        ohmV2Amount_ = _GOHM.balanceFrom(gohmAmount);
    }

    /// @inheritdoc IV1Migrator
    function previewMigrate(uint256 amount_) external view returns (uint256 ohmV2Amount_) {
        ohmV2Amount_ = _calculateOHMv2Amount(amount_);
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
        _OHMV2 = IERC20(address(MINTR.ohm()));
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");

        requests = new Permissions[](3);
        requests[0] = Permissions({keycode: MINTR_KEYCODE, funcSelector: MINTR.mintOhm.selector});
        requests[1] = Permissions({
            keycode: MINTR_KEYCODE,
            funcSelector: MINTR.increaseMintApproval.selector
        });
        requests[2] = Permissions({
            keycode: MINTR_KEYCODE,
            funcSelector: MINTR.decreaseMintApproval.selector
        });
    }

    // =========  ENABLE/DISABLE OVERRIDES ========= //

    /// @notice Override _enable to accept initial migration cap
    /// @dev    The enableData should be ABI-encoded as (uint256 migrationCap)
    ///
    ///         This allows setting the initial migration cap when enabling the contract.
    ///         The merkle root is set in the constructor and cannot be changed via enable().
    ///
    ///         On re-enable, the MINTR approval is adjusted to match the provided cap.
    ///
    /// @param enableData_ ABI-encoded (uint256 migrationCap)
    function _enable(bytes calldata enableData_) internal override {
        // Decode enableData: (uint256 migrationCap)
        uint256 migrationCap = abi.decode(enableData_, (uint256));
        _setMigrationCap(migrationCap);
    }

    // =========  INTERNAL FUNCTIONS ========= //

    /// @notice Internal function to set the migration cap by adjusting MINTR approval
    /// @dev    Gets current MINTR approval and increases or decreases to reach target cap
    /// @param cap_ The target migration cap (in OHM v2 units)
    function _setMigrationCap(uint256 cap_) internal {
        // Get current MINTR approval
        uint256 currentApproval = MINTR.mintApproval(address(this));

        // Increase or decrease MINTR approval to reach the target cap
        if (cap_ > currentApproval) {
            MINTR.increaseMintApproval(address(this), cap_ - currentApproval);
        } else if (cap_ < currentApproval) {
            MINTR.decreaseMintApproval(address(this), currentApproval - cap_);
        }

        // Emit event
        emit MigrationCapUpdated(cap_, currentApproval);
    }

    // =========  VERSION ========= //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    // =========  ERC165 ========= //

    /// @notice ERC165 interface support
    /// @dev    Supports IERC165, IVersioned, IV1Migrator, and IEnabler (via PolicyEnabler)
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            interfaceId == type(IV1Migrator).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // =========  MODIFIERS ========= //

    function _onlyAdminOrLegacyMigrationAdmin() internal view {
        if (!ROLES.hasRole(msg.sender, LEGACY_MIGRATION_ADMIN_ROLE) && !_isAdmin(msg.sender))
            revert NotAuthorised();
    }

    modifier onlyAdminOrLegacyMigrationAdmin() {
        _onlyAdminOrLegacyMigrationAdmin();
        _;
    }

    // =========  MIGRATE FUNCTIONS ========= //

    /// @notice Internal function to verify a merkle proof
    /// @dev Uses double-hashing to prevent leaf collision attacks (OpenZeppelin standard)
    /// @param account_ The account to verify
    /// @param allocatedAmount_ The allocated amount to verify
    /// @param proof_ The merkle proof
    /// @return valid True if the proof is valid
    function _verifyClaim(
        address account_,
        uint256 allocatedAmount_,
        bytes32[] calldata proof_
    ) internal view returns (bool valid) {
        // Generate leaf for this account and allocated amount (double-hashed)
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account_, allocatedAmount_))));

        // Verify proof against current root
        return proof_.verify(merkleRoot, leaf);
    }

    /// @inheritdoc IV1Migrator
    function verifyClaim(
        address account_,
        uint256 allocatedAmount_,
        bytes32[] calldata proof_
    ) external view returns (bool valid_) {
        return _verifyClaim(account_, allocatedAmount_, proof_);
    }

    /// @inheritdoc IV1Migrator
    function migrate(
        uint256 amount_,
        bytes32[] calldata proof_,
        uint256 allocatedAmount_
    ) external onlyEnabled {
        // Verify merkle proof for this claim with the allocated amount
        if (!_verifyClaim(msg.sender, allocatedAmount_, proof_)) revert InvalidProof();

        // Check that amount doesn't exceed user's allocation
        uint256 userMigrated = _migratedAmounts[msg.sender][_currentMerkleNonce];
        if (userMigrated + amount_ > allocatedAmount_) {
            revert AmountExceedsAllowance(amount_, allocatedAmount_, userMigrated);
        }

        // Calculate OHM v2 amount using gOHM conversion to match the migration flow
        // Migration flow: OHM v1 -> gOHM (balanceTo) -> OHM v2 (balanceFrom)
        uint256 ohmV2Amount = _calculateOHMv2Amount(amount_);

        // Check that OHM v2 amount is not zero (may happen due to gOHM rounding)
        if (ohmV2Amount == 0) revert ZeroAmount();

        // Check MINTR approval (represents remaining amount that can be minted)
        uint256 mintrApproval = MINTR.mintApproval(address(this));
        if (ohmV2Amount > mintrApproval) {
            revert CapExceeded(ohmV2Amount, mintrApproval);
        }

        // Update user's migrated amount for current nonce (tracked by OHM v1 amount)
        _migratedAmounts[msg.sender][_currentMerkleNonce] = userMigrated + amount_;

        // Update tracking (use OHM v1 amount for total migrated)
        totalMigrated += amount_;

        // Burn OHM v1 from user (user must have approved this contract)
        IERC20BurnableMintable(address(_OHMV1)).burnFrom(msg.sender, amount_);

        // Mint OHM v2 to user (amount calculated via gOHM conversion)
        MINTR.mintOhm(msg.sender, ohmV2Amount);

        emit Migrated(msg.sender, amount_, ohmV2Amount);
    }

    /// @inheritdoc IV1Migrator
    /// @dev    When the merkle root is updated, the nonce is incremented.
    ///         This resets all previous migrations without needing to iterate over users.
    ///         The new merkle tree should reflect the amount each user can migrate going
    ///         forward (i.e., their current OHM v1 balance).
    function setMerkleRoot(bytes32 merkleRoot_) external onlyAdminOrLegacyMigrationAdmin {
        // Guard against setting the same root (would reset nonce and allow re-migration)
        if (merkleRoot_ == merkleRoot) revert SameMerkleRoot();

        // Increment nonce to reset all previous migrations
        _currentMerkleNonce++;

        // Update merkle root
        merkleRoot = merkleRoot_;
        emit MerkleRootUpdated(merkleRoot_, msg.sender);
    }

    /// @inheritdoc IV1Migrator
    function setMigrationCap(uint256 cap_) external onlyAdminRole {
        _setMigrationCap(cap_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
