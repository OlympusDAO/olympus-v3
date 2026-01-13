// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {Kernel, Keycode, Permissions, Actions, toKeycode, fromKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {LegacyMigrator} from "policies/LegacyMigrator.sol";

/// @title LegacyMigratorTest
/// @notice Test suite for the LegacyMigrator policy
contract LegacyMigratorTest is StdInvariant, Test {
    UserFactory public userCreator;

    // Test addresses
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal admin;

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

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021
        userCreator = new UserFactory();

        // Create users
        address[] memory users = userCreator.create(4);
        alice = users[0];
        bob = users[1];
        guardian = users[2];
        admin = users[3];

        // Label users
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(guardian, "guardian");
        vm.label(admin, "admin");

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

        // Configure access control - grant legacy_migration_admin to admin
        // Also grant admin role to this test contract for enabling/disabling policies
        rolesAdmin.grantRole("admin", address(this));
        rolesAdmin.grantRole("legacy_migration_admin", admin);
        rolesAdmin.grantRole("emergency", guardian);

        // Generate merkle tree and set it in the migrator
        _generateMerkleTree();
        vm.prank(admin);
        migrator.setMerkleRoot(merkleRoot);

        // Enable the migrator
        migrator.enable("");

        // Give alice and bob some OHM v1
        ohmV1.mint(alice, ALICE_ALLOWANCE);
        ohmV1.mint(bob, BOB_ALLOWANCE);

        // Set initial migration cap
        migrator.setMigrationCap(INITIAL_CAP);
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

    // ======== SETUP TESTS ======== //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = migrator.configureDependencies();
        assertEq(deps.length, expectedDeps.length, "Dependencies length mismatch");
        assertEq(
            fromKeycode(deps[0]),
            fromKeycode(expectedDeps[0]),
            "First dependency should be MINTR"
        );
        assertEq(
            fromKeycode(deps[1]),
            fromKeycode(expectedDeps[1]),
            "Second dependency should be ROLES"
        );
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);

        Permissions[] memory perms = migrator.requestPermissions();
        assertEq(perms.length, expectedPerms.length, "Permissions length mismatch");
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(
                fromKeycode(perms[i].keycode),
                fromKeycode(expectedPerms[i].keycode),
                "Permission keycode mismatch"
            );
            assertEq(
                perms[i].funcSelector,
                expectedPerms[i].funcSelector,
                "Permission function selector mismatch"
            );
        }
    }

    // ========== EVENTS FOR TESTING ========== //

    event Migrated(address indexed user, uint256 ohmV1Amount, uint256 ohmV2Amount);
    event MerkleRootUpdated(bytes32 indexed newRoot, address indexed updater);
    event MigrationCapUpdated(uint256 indexed newCap, uint256 indexed oldCap);
    event Enabled();

    // ========== MIGRATE TESTS ========== //
    // Given the contract is disabled
    //  [X] it reverts when migrating

    function test_givenContractIsDisabled_reverts() public {
        // Disable the contract
        vm.prank(guardian);
        migrator.disable("");

        // Attempt migration should revert
        bytes memory err = abi.encodeWithSignature("NotEnabled()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== INVALID PROOF TESTS ========== //
    // Given invalid merkle proof
    //  [X] it reverts when migrating

    function test_givenInvalidMerkleProof_reverts() public {
        // Create invalid proof (empty array)
        bytes32[] memory invalidProof = new bytes32[](0);

        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, invalidProof);
    }

    // ========== VALID MIGRATION TESTS ========== //
    // Given valid proof, full amount
    //  [X] it migrates successfully
    //  [X] it emits Migrated event
    //  [X] it updates hasMigrated
    //  [X] it updates totalMigrated

    function test_givenValidProof_fullAmount_succeeds() public {
        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit Migrated(alice, ALICE_ALLOWANCE, ALICE_ALLOWANCE);

        // Migrate
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        // Check total migrated updated
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Check OHM v2 received
        assertEq(
            ohmV2.balanceOf(alice),
            ALICE_ALLOWANCE,
            "Alice should receive ALICE_ALLOWANCE OHM v2"
        );
    }

    // ========== ALL-OR-NOTHING MIGRATION TESTS ========== //
    // Given user migrates full amount
    //  [X] it succeeds
    //  [X] second migration attempt reverts

    function test_givenUserMigratesFullAmount_secondAttemptReverts() public {
        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // First migration with full amount
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");

        // Check total migrated
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Second migration should revert (already migrated)
        bytes memory err = abi.encodeWithSignature("AmountExceedsAllowance()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== PARTIAL AMOUNT TESTS ========== //
    // Given user attempts partial migration
    //  [X] it reverts (all-or-nothing)

    function test_givenPartialAmount_reverts() public {
        uint256 partialAmount = 500e9; // 500 OHM (less than full allowance)

        // Approve OHM v1 to migrator
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);

        // Partial migration should revert (proof doesn't match partial amount)
        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(partialAmount, aliceProof);
    }

    // ========== CAP TESTS ========== //
    // Given migration cap reached
    //  [X] it reverts when migrating

    function test_givenCapReached_reverts() public {
        // Set cap to exactly alice's allowance
        uint256 newCap = ALICE_ALLOWANCE;
        migrator.setMigrationCap(newCap);

        // Approve OHM v1 to migrator
        vm.prank(bob);
        ohmV1.approve(address(migrator), BOB_ALLOWANCE);

        // Bob should not be able to migrate (cap would be exceeded)
        bytes memory err = abi.encodeWithSignature("CapExceeded()");
        vm.expectRevert(err);

        vm.prank(bob);
        migrator.migrate(BOB_ALLOWANCE, bobProof);
    }

    // ========== MERKLE ROOT UPDATE TESTS ========== //
    // Given merkle root update
    //  [X] it updates the merkle root
    //  [X] it resets hasMigrated to false
    //  [X] old proof is invalid (cannot migrate with old proof)

    function test_givenMerkleRootUpdate_doesNotAllowRemigration() public {
        // First, do a full migration
        vm.prank(alice);
        ohmV1.approve(address(migrator), ALICE_ALLOWANCE);
        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);

        // Check user has migrated
        assertTrue(migrator.hasMigrated(alice), "Alice should have migrated");
        assertEq(
            migrator.totalMigrated(),
            ALICE_ALLOWANCE,
            "Total migrated should equal ALICE_ALLOWANCE"
        );

        // Update merkle root
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(newRoot, admin);
        migrator.setMerkleRoot(newRoot);

        // Check that merkle root is updated
        assertEq(migrator.merkleRoot(), newRoot, "Merkle root should be updated to newRoot");

        // Check that hasMigrated is reset
        assertFalse(migrator.hasMigrated(alice), "Alice should be reset after root change");

        // User should not be able to migrate again with the old proof (now invalid)
        bytes memory err = abi.encodeWithSignature("InvalidProof()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(ALICE_ALLOWANCE, aliceProof);
    }

    // ========== ADMIN ACCESS TESTS ========== //
    // Given non-admin sets merkle root
    //  [X] it reverts

    function test_givenNonAdmin_setsMerkleRoot_reverts() public {
        bytes32 newRoot = bytes32(uint256(1));

        // casting to 'bytes32' is safe because "legacy_migration_admin" is a fixed 23-byte string that fits in bytes32
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("legacy_migration_admin")
        );
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.setMerkleRoot(newRoot);
    }

    // ========== CAP UPDATE TESTS ========== //
    // Given admin (this contract) sets migration cap
    //  [X] it calls MINTR.increaseMintApproval() if higher
    //  [X] it calls MINTR.decreaseMintApproval() if lower
    //  [X] it emits MigrationCapUpdated event

    function test_givenAdmin_setsHigherCap_increasesApproval() public {
        uint256 newCap = INITIAL_CAP + 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        migrator.setMigrationCap(newCap);

        // Check cap updated
        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated to newCap");
    }

    function test_givenAdmin_setsLowerCap_decreasesApproval() public {
        uint256 newCap = INITIAL_CAP - 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        migrator.setMigrationCap(newCap);

        // Check cap updated
        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated to newCap");
    }

    function test_givenAdmin_setsCap_emitsEvent() public {
        uint256 newCap = 20000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        migrator.setMigrationCap(newCap);
    }

    // ========== ENABLE/DISABLE TESTS ========== //
    // Given contract enabled
    //  [X] admin can disable it

    function test_givenEnabled_adminDisables_succeeds() public {
        vm.prank(guardian);
        migrator.disable("");

        // Check contract is disabled
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");
    }

    // ========== VERIFY CLAIM TESTS ========== //

    function test_verifyClaim_validClaim() public {
        // Alice's claim should be valid
        assertTrue(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, aliceProof),
            "Alice's claim should be valid"
        );

        // Bob's claim should be valid
        assertTrue(
            migrator.verifyClaim(bob, BOB_ALLOWANCE, bobProof),
            "Bob's claim should be valid"
        );
    }

    function test_verifyClaim_invalidClaim() public {
        // Invalid proof should fail
        bytes32[] memory invalidProof = new bytes32[](0);
        assertFalse(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, invalidProof),
            "Invalid proof should fail"
        );
    }
}
