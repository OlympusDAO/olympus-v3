// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {Kernel, Keycode, Permissions, Actions, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {LegacyMigrator} from "policies/LegacyMigrator.sol";

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

        // Label tokens
        vm.label(address(ohmV1), "OHM_V1");
        vm.label(address(ohmV2), "OHM_V2");

        // Deploy kernel
        kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        // Deploy modules
        MINTR = new OlympusMinter(kernel, address(ohmV2));
        ROLES = new OlympusRoles(kernel);

        // Label modules
        vm.label(address(MINTR), "MINTR");
        vm.label(address(ROLES), "ROLES");

        // Deploy policies
        rolesAdmin = new RolesAdmin(kernel);
        migrator = new LegacyMigrator(kernel, IERC20(address(ohmV1)));

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

        // Generate merkle tree and set it in the migrator
        _generateMerkleTree();
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(merkleRoot);

        // Enable the migrator
        migrator.enable("");

        // Give alice and bob some OHM v1
        ohmV1.mint(alice, ALICE_ALLOWANCE);
        ohmV1.mint(bob, BOB_ALLOWANCE);

        // Set initial migration cap
        migrator.setMigrationCap(INITIAL_CAP);

        // Revoke "admin" role from this test contract after setup
        rolesAdmin.revokeRole("admin", address(this));
    }

    // ======== MERKLE TREE HELPERS ======== //

    function _generateMerkleLeaves() internal view returns (bytes32[] memory leaves) {
        leaves = new bytes32[](2);
        // Encode (address, uint256) for each user
        leaves[0] = keccak256(abi.encode(alice, ALICE_ALLOWANCE));
        leaves[1] = keccak256(abi.encode(bob, BOB_ALLOWANCE));
    }

    function _generateMerkleTree() internal {
        bytes32[] memory leaves = _generateMerkleLeaves();

        // Sort leaves for merkle tree
        _sortBytes32Array(leaves);

        // Generate proofs and root
        if (leaves[0] == keccak256(abi.encode(alice, ALICE_ALLOWANCE))) {
            // Alice is first, Bob is second
            aliceProof = new bytes32[](1);
            aliceProof[0] = leaves[1];

            bobProof = new bytes32[](1);
            bobProof[0] = leaves[0];
        } else {
            // Bob is first, Alice is second
            aliceProof = new bytes32[](1);
            aliceProof[0] = leaves[1];

            bobProof = new bytes32[](1);
            bobProof[0] = leaves[0];
        }

        // Compute root using OpenZeppelin's _hashPair approach (sort, then hash)
        // For two leaves: if a < b, hash(keccak256(a,b)), else hash(keccak256(b,a))
        // This matches how MerkleProof.processProof computes the root
        bytes32 left = leaves[0];
        bytes32 right = leaves[1];
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = right;
        // Simulate the verification: start with left, hash with right
        bytes32 computedHash = left;
        computedHash = _hashPair(computedHash, proof[0]);
        merkleRoot = computedHash;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

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

    /// @dev Modifier to set state where alice has fully migrated
    modifier givenAliceMigrated() {
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
        _;
    }

    /// @dev Modifier to set state where bob has fully migrated
    modifier givenBobMigrated() {
        vm.prank(bob);
        ohmV1.approve(address(migrator), BOB_ALLOWANCE);
        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof);
        _;
    }

    /// @dev Modifier to set state where the migration cap is set to a specific value
    modifier givenCapSet(uint256 newCap_) {
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap_);
        _;
    }

    /// @dev Modifier to set state where the cap is reached (set to alice's allowance)
    modifier givenCapReached() {
        vm.prank(adminUser);
        migrator.setMigrationCap(ALICE_ALLOWANCE);
        _;
    }

    /// @dev Modifier to set state where the merkle root has been updated (resets hasMigrated)
    modifier givenMerkleRootUpdated() {
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(legacyMigrationAdmin);
        migrator.setMerkleRoot(newRoot);
        _;
    }

    /// @dev Modifier to set state where the contract is re-enabled (disabled then enabled)
    modifier givenReEnabled() {
        vm.prank(emergencyUser);
        migrator.disable("");
        vm.prank(adminUser);
        migrator.enable("");
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
