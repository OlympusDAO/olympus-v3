// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockGohm} from "src/test/mocks/MockGohm.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {LegacyMigrator} from "policies/LegacyMigrator.sol";
import {Hashes} from "@openzeppelin-5.3.0/utils/cryptography/Hashes.sol";

/// @title LegacyMigratorTest
/// @notice Parent test contract for LegacyMigrator with shared setup and helpers
contract LegacyMigratorTest is StdInvariant, Test {
    UserFactory public userCreator;

    // Role holders - distinct users for each role
    address internal adminUser; // Has "admin" role
    address internal legacyMigrationAdmin; // Has "legacy_migration_admin" role
    address internal emergencyUser; // Has "emergency" role

    // Regular users
    address internal alice;
    address internal bob;

    // Tokens
    MockOhm internal ohmV1;
    MockOhm internal ohmV2;
    MockGohm internal gOHM;

    // Kernel and modules
    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;

    // Policies
    RolesAdmin internal rolesAdmin;
    LegacyMigrator internal migrator;

    // Test constants
    uint256 internal constant ALICE_ALLOWANCE = 1000e9; // 1000 OHM (9 decimals)
    uint256 internal constant BOB_ALLOWANCE = 5000e9; // 5000 OHM (9 decimals)
    uint256 internal constant INITIAL_CAP = 10000e9; // 10000 OHM (9 decimals)

    // Merkle tree data
    bytes32 internal merkleRoot;
    bytes32[] internal aliceProof;
    bytes32[] internal bobProof;

    function setUp() public virtual {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021
        userCreator = new UserFactory();

        // Create users (5 users for roles + regular users)
        address[] memory users = userCreator.create(5);
        alice = users[0];
        bob = users[1];
        adminUser = users[2];
        legacyMigrationAdmin = users[3];
        emergencyUser = users[4];

        // Label users
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(adminUser, "adminUser");
        vm.label(legacyMigrationAdmin, "legacyMigrationAdmin");
        vm.label(emergencyUser, "emergencyUser");

        // Deploy mock OHM tokens (both 9 decimals)
        ohmV1 = new MockOhm("Olympus V1", "OHM", 9);
        ohmV2 = new MockOhm("Olympus V2", "OHM", 9);

        // Deploy mock gOHM token (18 decimals, with index that causes rounding)
        gOHM = new MockGohm("Governance OHM", "gOHM", 18);

        // Label tokens
        vm.label(address(ohmV1), "OHM_V1");
        vm.label(address(ohmV2), "OHM_V2");
        vm.label(address(gOHM), "GOHM");

        // Deploy kernel
        kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        // Deploy modules
        MINTR = new OlympusMinter(kernel, address(ohmV2));
        ROLES = new OlympusRoles(kernel);

        // Label modules
        vm.label(address(MINTR), "MINTR");
        vm.label(address(ROLES), "ROLES");

        // Generate merkle tree BEFORE deploying LegacyMigrator (merkleRoot is in constructor)
        _generateMerkleTree();

        // Deploy policies
        rolesAdmin = new RolesAdmin(kernel);
        migrator = new LegacyMigrator(
            kernel,
            IERC20(address(ohmV1)),
            IgOHM(address(gOHM)),
            merkleRoot
        );

        // Label policies
        vm.label(address(rolesAdmin), "RolesAdmin");
        vm.label(address(migrator), "LegacyMigrator");

        // Initialize system
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        kernel.executeAction(Actions.ActivatePolicy, address(migrator));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Configure access control
        // Grant "admin" role to adminUser (NOT to this test contract)
        rolesAdmin.grantRole("admin", adminUser);
        // Grant "legacy_migration_admin" role to legacyMigrationAdmin
        rolesAdmin.grantRole("legacy_migration_admin", legacyMigrationAdmin);
        // Grant "emergency" role to emergencyUser
        rolesAdmin.grantRole("emergency", emergencyUser);

        // Grant this test contract "admin" role temporarily for setup
        rolesAdmin.grantRole("admin", address(this));

        // Enable the migrator with initial cap (merkle root is in constructor)
        migrator.enable(abi.encode(INITIAL_CAP));

        // Give alice and bob some OHM v1
        ohmV1.mint(alice, ALICE_ALLOWANCE);
        ohmV1.mint(bob, BOB_ALLOWANCE);

        // Revoke "admin" role from this test contract after setup
        rolesAdmin.revokeRole("admin", address(this));
    }

    // ======== MERKLE TREE HELPERS ======== //
    // NOTE: We use OpenZeppelin's Hashes.commutativeKeccak256 for hashing pairs, which matches
    // the standard approach used by OZ's MerkleProof library. This ensures commutativity (hashing
    // order doesn't matter) and uses efficient memory layout for keccak256 operations.
    //
    // For simple static trees with known leaves (like our 2-user test), manual generation is
    // straightforward. OZ's MerkleTree library is designed for incremental on-chain tree building
    // (push-based), which is overkill for this use case.

    /// @dev Generate merkle tree for alice and bob with their allowances
    /// Uses double-hashing for leaves (OpenZeppelin standard for merkle allowlists)
    function _generateMerkleTree() internal {
        bytes32[] memory leaves = _generateLeaves();
        _sortBytes32Array(leaves);

        // Compute root using OpenZeppelin's commutative hashing
        merkleRoot = Hashes.commutativeKeccak256(leaves[0], leaves[1]);

        // Generate proofs for alice and bob
        bytes32 aliceLeaf = _leaf(alice, ALICE_ALLOWANCE);

        aliceProof = new bytes32[](1);
        bobProof = new bytes32[](1);

        // Each proof is the sibling leaf
        if (leaves[0] == aliceLeaf) {
            aliceProof[0] = leaves[1]; // Alice's sibling is Bob
            bobProof[0] = leaves[0]; // Bob's sibling is Alice
        } else {
            aliceProof[0] = leaves[0]; // Alice's sibling is Bob
            bobProof[0] = leaves[1]; // Bob's sibling is Alice
        }
    }

    /// @dev Refresh the merkle tree with the same allocations (simulates root update)
    function _refreshMerkleTree() internal {
        _generateMerkleTree();

        // Update the contract's merkle root
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(merkleRoot);
    }

    /// @dev Generate double-hashed leaves for alice and bob
    function _generateLeaves() internal view returns (bytes32[] memory leaves) {
        leaves = new bytes32[](2);
        leaves[0] = _leaf(alice, ALICE_ALLOWANCE);
        leaves[1] = _leaf(bob, BOB_ALLOWANCE);
    }

    /// @dev Generate a double-hashed leaf for merkle tree (OpenZeppelin standard)
    function _leaf(address account_, uint256 amount_) internal pure returns (bytes32) {
        /// forge-lint: disable-next-line(asm-keccak256)
        return keccak256(bytes.concat(keccak256(abi.encode(account_, amount_))));
    }

    /// @dev Sort bytes32 array in ascending order
    function _sortBytes32Array(bytes32[] memory arr) internal pure {
        for (uint256 i = 0; i < arr.length - 1; i++) {
            for (uint256 j = i + 1; j < arr.length; j++) {
                if (arr[i] > arr[j]) {
                    bytes32 temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
    }

    // ======== STATE SETTING MODIFIERS ======== //

    /// @dev Modifier to set state where the contract is disabled
    modifier givenContractDisabled() {
        vm.prank(emergencyUser);
        migrator.disable("");
        _;
    }

    /// @dev Modifier to set state where alice has approved OHM v1 to the migrator
    modifier givenAliceApproved() {
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where bob has approved OHM v1 to the migrator
    modifier givenBobApproved() {
        vm.prank(bob);
        ohmV1.approve(address(migrator), BOB_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where alice has partially migrated
    modifier givenAlicePartiallyMigrated(uint256 migratedAmount_) {
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(migratedAmount_, aliceProof, ALICE_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where alice has fully migrated
    modifier givenAliceFullyMigrated() {
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof, ALICE_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where bob has fully migrated
    modifier givenBobFullyMigrated() {
        vm.prank(bob);
        ohmV1.approve(address(migrator), BOB_ALLOWANCE);
        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof, BOB_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where the migration cap is set to a specific value
    modifier givenCapSet(uint256 newCap_) {
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap_);
        _;
    }

    /// @dev Modifier to set state where the cap is reached (set to 0)
    modifier givenCapReached() {
        vm.prank(adminUser);
        migrator.setMigrationCap(0);
        _;
    }

    /// @dev Modifier to set state where the merkle root has been updated (resets migrated amounts)
    modifier givenMerkleRootUpdated() {
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);
        _;
    }

    /// @dev Modifier to set state where the merkle root has been updated to same allocations (refreshes tree)
    modifier givenMerkleRootRefreshed() {
        _refreshMerkleTree();
        _;
    }

    /// @dev Modifier to set state where the contract is re-enabled (disabled then enabled)
    modifier givenReEnabled() {
        vm.prank(emergencyUser);
        migrator.disable("");
        vm.prank(adminUser);
        // Re-enable with same cap (merkle root is in constructor, doesn't change)
        migrator.enable(abi.encode(INITIAL_CAP));
        _;
    }

    // ======== ROLE MODIFIERS ======== //

    /// @dev Modifier to run a function as the admin user
    modifier asAdmin() {
        vm.startPrank(adminUser);
        _;
        vm.stopPrank();
    }

    /// @dev Modifier to run a function as the legacy migration admin
    modifier asLegacyMigrationAdmin() {
        vm.startPrank(legacyMigrationAdmin);
        _;
        vm.stopPrank();
    }

    /// @dev Modifier to run a function as the emergency user
    modifier asEmergency() {
        vm.startPrank(emergencyUser);
        _;
        vm.stopPrank();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
