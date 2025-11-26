// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {USDSRewardDistributor} from "policies/USDSRewardDistributor.sol";
import {IRewardDistributor} from "policies/interfaces/IRewardDistributor.sol";
import {Kernel, Keycode, Policy, toKeycode, Module, Actions} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract USDSRewardDistributorTest is Test {
    MockERC20 internal usds;
    MockERC4626 internal sUSDS;
    USDSRewardDistributor internal distributor;
    Kernel internal kernel;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;

    uint40 internal constant WEEK_DURATION = 7 days;
    uint40 internal startTimestamp;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal admin = address(0x3);

    bytes32 internal constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    // Import Actions enum
    // Actions is defined in Kernel.sol but not exported as a type we can import directly?
    // It is exported in Kernel.sol: enum Actions { ... }
    // But we need to import it.
    // We can cast to uint8 or import it if possible.
    // Actions is global in Kernel.sol? No, it's outside contract Kernel.

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021
        startTimestamp = uint40(block.timestamp);

        // Deploy mock tokens
        usds = new MockERC20("USDS", "USDS", 18);
        sUSDS = new MockERC4626(usds, "Vault Token", "vToken");

        // Deploy Kernel
        kernel = new Kernel();

        // Deploy Modules
        trsry = new OlympusTreasury(kernel);
        roles = new OlympusRoles(kernel);

        // Install Modules
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.InstallModule, address(roles));

        // Deploy distributor
        distributor = new USDSRewardDistributor(address(kernel), address(sUSDS), startTimestamp);

        // Activate Policy (this configures dependencies)
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));

        // Grant permission to test contract to call saveRole
        // modulePermissions is at slot 6
        // mapping(Keycode => mapping(Policy => mapping(bytes4 => bool)))
        bytes32 slot = keccak256(
            abi.encode(
                ROLESv1.saveRole.selector,
                keccak256(abi.encode(address(this), keccak256(abi.encode(toKeycode("ROLES"), 6))))
            )
        );
        vm.store(address(kernel), slot, bytes32(uint256(1)));

        // Grant permission to test contract to call increaseWithdrawApproval
        bytes32 slot2 = keccak256(
            abi.encode(
                TRSRYv1.increaseWithdrawApproval.selector,
                keccak256(abi.encode(address(this), keccak256(abi.encode(toKeycode("TRSRY"), 6))))
            )
        );
        vm.store(address(kernel), slot2, bytes32(uint256(1)));

        // Approve distributor to withdraw from TRSRY
        trsry.increaseWithdrawApproval(address(distributor), sUSDS, type(uint256).max);

        // Setup roles
        roles.saveRole(ROLE_MERKLE_UPDATER, admin);
        roles.saveRole(ADMIN_ROLE, address(this));

        // Enable distributor
        distributor.enable("");

        // Fund Treasury with sUSDS
        usds.mint(address(this), 1_000_000e18);
        usds.approve(address(sUSDS), 1_000_000e18);
        sUSDS.mint(1_000_000e18, address(trsry));
        // Fund Vault with USDS (for withdrawals)
        usds.mint(address(sUSDS), 1_000_000e18);
    }

    // ========== Helper Functions ========== //

    function _generateLeaf(
        address user,
        uint256 week,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, week, amount))));
    }

    // ========== Test Constructor and State Variables ========== //

    function test_constructor_initializes_correctly() public view {
        assertEq(address(distributor.REWARD_TOKEN_VAULT().asset()), address(usds));
        assertEq(address(distributor.REWARD_TOKEN_VAULT()), address(sUSDS));
        assertEq(distributor.START_TIMESTAMP(), startTimestamp);
        assertEq(distributor.WEEK_DURATION(), WEEK_DURATION);
    }

    function test_constructor_rejects_zero_reward_token_vault() public {
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidAddress.selector);
        new USDSRewardDistributor(address(kernel), address(0), startTimestamp);
    }

    function test_constructor_rejects_zero_start_timestamp() public {
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidAddress.selector);
        new USDSRewardDistributor(address(kernel), address(sUSDS), 0);
    }

    // ========== Test Merkle Root Management ========== //

    function test_setMerkleRoot_success() public {
        vm.warp(startTimestamp + WEEK_DURATION); // End of week 0

        bytes32 root = bytes32(uint256(1));

        vm.prank(admin);
        distributor.setMerkleRoot(0, root);

        assertEq(distributor.weeklyMerkleRoots(0), root);
    }

    function test_setMerkleRoot_reverts_unauthorized() public {
        vm.warp(startTimestamp + WEEK_DURATION);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_MERKLE_UPDATER)
        );
        distributor.setMerkleRoot(0, bytes32(uint256(1)));
    }

    function test_setMerkleRoot_reverts_too_early() public {
        // Still in week 0
        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_WeekTooEarly.selector);
        distributor.setMerkleRoot(0, bytes32(uint256(1)));
    }

    function test_setMerkleRoot_reverts_already_set() public {
        vm.warp(startTimestamp + WEEK_DURATION);

        vm.startPrank(admin);
        distributor.setMerkleRoot(0, bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(IRewardDistributor.RewardDistributor_WeekAlreadySet.selector, 0)
        );
        distributor.setMerkleRoot(0, bytes32(uint256(2)));
        vm.stopPrank();
    }

    // ========== Test Claiming Logic ========== //

    function test_claim_as_underlying() public {
        uint256 amount = 100e18;
        uint40 week = 0;

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, week, amount);
        bytes32[] memory proof = new bytes32[](0); // Single leaf tree, root is leaf

        // Set root
        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(week, leaf);

        // Prepare claim data
        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Claim
        vm.prank(alice);
        distributor.claim(claimWeeks, amounts, proofs, false); // asVaultToken = false

        // Verify
        assertEq(usds.balanceOf(alice), amount);
        assertTrue(distributor.hasClaimed(alice, week));
    }

    function test_claim_as_vault_token() public {
        uint256 amount = 100e18;
        uint40 week = 0;

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, week, amount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(week, leaf);

        // Prepare claim data
        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Claim
        vm.prank(alice);
        distributor.claim(claimWeeks, amounts, proofs, true); // asVaultToken = true

        // Verify
        assertEq(sUSDS.balanceOf(alice), sUSDS.previewWithdraw(amount));
        assertTrue(distributor.hasClaimed(alice, week));
    }

    function test_claim_multiple_weeks() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // Setup week 0
        bytes32 leaf1 = _generateLeaf(alice, 0, amount1);
        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(0, leaf1);

        // Setup week 1
        bytes32 leaf2 = _generateLeaf(alice, 1, amount2);
        vm.warp(startTimestamp + 2 * WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(1, leaf2);

        // Prepare claim data
        uint256[] memory claimWeeks = new uint256[](2);
        claimWeeks[0] = 0;
        claimWeeks[1] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        // Claim
        vm.prank(alice);
        distributor.claim(claimWeeks, amounts, proofs, false);

        // Verify
        assertEq(usds.balanceOf(alice), amount1 + amount2);
        assertTrue(distributor.hasClaimed(alice, 0));
        assertTrue(distributor.hasClaimed(alice, 1));
    }

    function test_claim_skips_already_claimed() public {
        uint256 amount = 100e18;
        uint40 week = 0;
        bytes32 leaf = _generateLeaf(alice, week, amount);

        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(week, leaf);

        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.startPrank(alice);
        distributor.claim(claimWeeks, amounts, proofs, false);

        // Verify previewClaim returns 0 after claiming
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            claimWeeks,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        // Record balance before second claim attempt
        uint256 balanceBefore = usds.balanceOf(alice);

        // Second claim should skip already-claimed week without reverting
        distributor.claim(claimWeeks, amounts, proofs, false);

        // Verify no additional tokens were transferred
        assertEq(usds.balanceOf(alice), balanceBefore);
        vm.stopPrank();
    }

    function test_claim_skips_already_claimed_in_batch() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;
        uint256 amount3 = 300e18;

        // Setup week 0
        bytes32 leaf1 = _generateLeaf(alice, 0, amount1);
        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(0, leaf1);

        // Setup week 1
        bytes32 leaf2 = _generateLeaf(alice, 1, amount2);
        vm.warp(startTimestamp + 2 * WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(1, leaf2);

        // Setup week 2
        bytes32 leaf3 = _generateLeaf(alice, 2, amount3);
        vm.warp(startTimestamp + 3 * WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(2, leaf3);

        // Claim week 1 first
        uint256[] memory claimWeeks1 = new uint256[](1);
        claimWeeks1[0] = 1;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = amount2;
        bytes32[][] memory proofs1 = new bytes32[][](1);
        proofs1[0] = new bytes32[](0);

        vm.prank(alice);
        distributor.claim(claimWeeks1, amounts1, proofs1, false);

        assertEq(usds.balanceOf(alice), amount2);
        assertTrue(distributor.hasClaimed(alice, 1));

        // Now try to claim all three weeks (0, 1, 2) - should skip week 1
        uint256[] memory claimWeeks = new uint256[](3);
        claimWeeks[0] = 0;
        claimWeeks[1] = 1; // Already claimed
        claimWeeks[2] = 2;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;
        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);
        proofs[2] = new bytes32[](0);

        vm.prank(alice);
        distributor.claim(claimWeeks, amounts, proofs, false);

        // Should only receive amount1 + amount3 (week 1 was skipped)
        assertEq(usds.balanceOf(alice), amount1 + amount2 + amount3);
        assertTrue(distributor.hasClaimed(alice, 0));
        assertTrue(distributor.hasClaimed(alice, 1));
        assertTrue(distributor.hasClaimed(alice, 2));
    }

    function test_claim_reverts_invalid_proof() public {
        uint256 amount = 100e18;
        uint40 week = 0;
        bytes32 leaf = _generateLeaf(alice, week, amount);

        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(week, leaf);

        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount + 1; // Wrong amount
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Verify previewClaim returns 0 for invalid proof
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            claimWeeks,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        vm.prank(alice);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidProof.selector);
        distributor.claim(claimWeeks, amounts, proofs, false);
    }

    function test_claim_reverts_merkle_root_not_set() public {
        uint256 amount = 100e18;
        uint40 week = 0;

        // Don't set root

        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Verify previewClaim returns 0 when root not set
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            claimWeeks,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_MerkleRootNotSet.selector,
                week
            )
        );
        distributor.claim(claimWeeks, amounts, proofs, false);
    }

    function test_previewClaim() public {
        uint256 amount = 100e18;
        uint40 week = 0;
        bytes32 leaf = _generateLeaf(alice, week, amount);

        vm.warp(startTimestamp + WEEK_DURATION);
        vm.prank(admin);
        distributor.setMerkleRoot(week, leaf);

        uint256[] memory claimWeeks = new uint256[](1);
        claimWeeks[0] = week;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            claimWeeks,
            amounts,
            proofs
        );

        assertEq(claimable, amount);
        assertEq(shares, sUSDS.previewWithdraw(amount));
    }
}
