// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {RewardDistributorUSDS} from "policies/RewardDistributorUSDS.sol";
import {IRewardDistributor} from "policies/interfaces/IRewardDistributor.sol";
import {Kernel, toKeycode, Actions} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract RewardDistributorUSDSTest is Test {
    MockERC20 internal usds;
    MockERC4626 internal sUSDS;
    RewardDistributorUSDS internal distributor;
    Kernel internal kernel;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;

    uint40 internal constant EPOCH_DURATION = 7 days;
    uint40 internal startTimestamp; // Midnight UTC (00:00:00)

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal admin = address(0x3);

    bytes32 internal constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

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

        // Deploy distributor with startTimestamp (midnight UTC)
        distributor = new RewardDistributorUSDS(address(kernel), address(sUSDS), startTimestamp);

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
        uint256 epochEndDate,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, epochEndDate, amount))));
    }

    /// @notice Helper to get the first epoch end date (23:59:59 UTC of start day)
    function _firstEpochEndDate() internal view returns (uint40) {
        return startTimestamp + 1 days - 1;
    }

    // ========== Test Constructor and State Variables ========== //

    function test_constructor_initializes_correctly() public view {
        assertEq(address(distributor.REWARD_TOKEN_VAULT().asset()), address(usds));
        assertEq(address(distributor.REWARD_TOKEN_VAULT()), address(sUSDS));
        assertEq(distributor.EPOCH_START_DATE(), startTimestamp);
    }

    function test_constructor_rejects_zero_reward_token_vault() public {
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidAddress.selector);
        new RewardDistributorUSDS(address(kernel), address(0), startTimestamp);
    }

    function test_constructor_rejects_zero_start_timestamp() public {
        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochIsZero.selector);
        new RewardDistributorUSDS(address(kernel), address(sUSDS), 0);
    }

    function test_constructor_rejects_epoch_not_start_of_day() public {
        uint256 notStartOfDay = startTimestamp + 12 hours; // Not at midnight
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidEpochTimestamp.selector);
        new RewardDistributorUSDS(address(kernel), address(sUSDS), notStartOfDay);
    }

    // ========== Test Merkle Root Management ========== //

    function test_endEpoch_success() public {
        uint40 epochEndDate = _firstEpochEndDate(); // 23:59:59 UTC of first day

        bytes32 root = bytes32(uint256(1));

        vm.prank(admin);
        distributor.endEpoch(epochEndDate, root);

        assertEq(distributor.epochMerkleRoots(epochEndDate), root);
        assertEq(distributor.lastEpochEndDate(), epochEndDate);
    }

    function testFuzz_endEpoch_success_any_valid_epoch(uint8 n) public {
        // Bound n to reasonable range (1 to 100 epochs)
        vm.assume(n >= 1 && n <= 100);

        // Calculate valid epoch end date: startTimestamp + n * 1 days - 1
        // This gives us 23:59:59 UTC of day n
        uint40 epochEndDate = startTimestamp + uint40(n) * 1 days - 1;

        bytes32 root = bytes32(uint256(n));

        vm.prank(admin);
        distributor.endEpoch(epochEndDate, root);

        assertEq(distributor.epochMerkleRoots(epochEndDate), root);
        assertEq(distributor.lastEpochEndDate(), epochEndDate);
    }

    function test_endEpoch_multiple_epochs_sequential() public {
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 1 days;
        uint40 epoch3EndDate = epoch2EndDate + 1 days;

        bytes32 root1 = bytes32(uint256(1));
        bytes32 root2 = bytes32(uint256(2));
        bytes32 root3 = bytes32(uint256(3));

        vm.startPrank(admin);

        // End epoch 1
        distributor.endEpoch(epoch1EndDate, root1);
        assertEq(distributor.epochMerkleRoots(epoch1EndDate), root1);
        assertEq(distributor.lastEpochEndDate(), epoch1EndDate);

        // End epoch 2
        distributor.endEpoch(epoch2EndDate, root2);
        assertEq(distributor.epochMerkleRoots(epoch2EndDate), root2);
        assertEq(distributor.lastEpochEndDate(), epoch2EndDate);

        // End epoch 3
        distributor.endEpoch(epoch3EndDate, root3);
        assertEq(distributor.epochMerkleRoots(epoch3EndDate), root3);
        assertEq(distributor.lastEpochEndDate(), epoch3EndDate);

        vm.stopPrank();

        // Verify all roots are still set correctly
        assertEq(distributor.epochMerkleRoots(epoch1EndDate), root1);
        assertEq(distributor.epochMerkleRoots(epoch2EndDate), root2);
        assertEq(distributor.epochMerkleRoots(epoch3EndDate), root3);
    }

    function testFuzz_endEpoch_reverts_unauthorized(address caller) public {
        // Skip if caller has the merkle updater role
        vm.assume(caller != admin);

        uint40 epochEndDate = _firstEpochEndDate();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ROLE_MERKLE_UPDATER)
        );
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)));
    }

    function testFuzz_endEpoch_reverts_too_early(uint40 secondEpochEndDate) public {
        uint40 firstEpochEndDate = _firstEpochEndDate();

        // Bound the fuzzed input to be:
        // - At least 1 second (non-zero and reasonable)
        // - Less than firstEpochEndDate + 1 days (to trigger the revert)
        vm.assume(secondEpochEndDate > 0);
        vm.assume(secondEpochEndDate < firstEpochEndDate + 1 days);

        // Align to end of day (23:59:59 UTC) to avoid InvalidEpochTimestamp error
        secondEpochEndDate = uint40((secondEpochEndDate / 1 days) * 1 days + 1 days - 1);

        // Skip if the aligned value equals firstEpochEndDate (already set)
        vm.assume(secondEpochEndDate != firstEpochEndDate);

        vm.startPrank(admin);
        distributor.endEpoch(firstEpochEndDate, bytes32(uint256(1)));

        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochTooEarly.selector);
        distributor.endEpoch(secondEpochEndDate, bytes32(uint256(2)));
        vm.stopPrank();
    }

    function test_endEpoch_reverts_not_end_of_day() public {
        uint40 epochEndDate = startTimestamp + 12 hours; // Not at end of day

        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidEpochTimestamp.selector);
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)));
    }

    function test_endEpoch_reverts_already_set() public {
        uint40 epochEndDate = _firstEpochEndDate();

        vm.startPrank(admin);
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_EpochAlreadySet.selector,
                epochEndDate
            )
        );
        distributor.endEpoch(epochEndDate, bytes32(uint256(2)));
        vm.stopPrank();
    }

    function test_endEpoch_reverts_epoch_before_first_valid_epoch() public {
        // The first valid epoch end date is EPOCH_START_DATE + 1 days - 1
        // Try to end an epoch before that (23:59:59 of day before EPOCH_START_DATE)
        uint40 epochEndDate = startTimestamp - 1; // 23:59:59 UTC of day before

        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochTooEarly.selector);
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)));
    }

    // ========== Test Claiming Logic ========== //

    function test_claim_as_underlying() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);
        bytes32[] memory proof = new bytes32[](0); // Single leaf tree, root is leaf

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Verify previewClaim before claiming
        (uint256 previewAmount, uint256 previewShares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(previewAmount, amount);
        assertEq(previewShares, sUSDS.previewWithdraw(amount));

        // Claim
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, false); // asVaultToken = false

        // Verify
        assertEq(usds.balanceOf(alice), amount);
        assertTrue(distributor.hasClaimed(alice, epochEndDate));
    }

    function test_claim_as_vault_token() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Verify previewClaim before claiming
        (uint256 previewAmount, uint256 previewShares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(previewAmount, amount);
        assertEq(previewShares, sUSDS.previewWithdraw(amount));

        // Claim
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, true); // asVaultToken = true

        // Verify (uses convertToShares which rounds down)
        assertEq(sUSDS.balanceOf(alice), sUSDS.convertToShares(amount));
        assertTrue(distributor.hasClaimed(alice, epochEndDate));
    }

    function test_claim_multiple_epochs() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        uint40 epoch0EndDate = _firstEpochEndDate();
        uint40 epoch1EndDate = epoch0EndDate + EPOCH_DURATION;

        // Setup first epoch
        bytes32 leaf1 = _generateLeaf(alice, epoch0EndDate, amount1);
        vm.warp(startTimestamp + EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epoch0EndDate, leaf1);

        // Setup epoch 1
        bytes32 leaf2 = _generateLeaf(alice, epoch1EndDate, amount2);
        vm.warp(startTimestamp + 2 * EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epoch1EndDate, leaf2);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch0EndDate;
        epochEndDates[1] = epoch1EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        // Verify previewClaim before claiming
        (uint256 previewAmount, uint256 previewShares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(previewAmount, amount1 + amount2);
        assertEq(previewShares, sUSDS.previewWithdraw(amount1 + amount2));

        // Claim
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, false);

        // Verify
        assertEq(usds.balanceOf(alice), amount1 + amount2);
        assertTrue(distributor.hasClaimed(alice, epoch0EndDate));
        assertTrue(distributor.hasClaimed(alice, epoch1EndDate));
    }

    function test_claim_reverts_when_already_claimed() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);

        vm.warp(startTimestamp + EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.startPrank(alice);
        distributor.claim(epochEndDates, amounts, proofs, false);

        // Verify previewClaim returns 0 after claiming
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        // Second claim should revert with AlreadyClaimed error
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, proofs, false);
        vm.stopPrank();
    }

    function test_claim_reverts_already_claimed_in_batch() public {
        uint40 epoch0EndDate = _firstEpochEndDate();

        // Setup first epoch (100e18)
        vm.warp(startTimestamp + EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epoch0EndDate, _generateLeaf(alice, epoch0EndDate, 100e18));

        // Setup epoch 1 (200e18)
        vm.warp(startTimestamp + 2 * EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(
            epoch0EndDate + EPOCH_DURATION,
            _generateLeaf(alice, epoch0EndDate + EPOCH_DURATION, 200e18)
        );

        // Setup epoch 2 (300e18)
        vm.warp(startTimestamp + 3 * EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(
            epoch0EndDate + 2 * EPOCH_DURATION,
            _generateLeaf(alice, epoch0EndDate + 2 * EPOCH_DURATION, 300e18)
        );

        // Claim epoch 1 first
        {
            uint256[] memory epochEndDates1 = new uint256[](1);
            epochEndDates1[0] = epoch0EndDate + EPOCH_DURATION;
            uint256[] memory amounts1 = new uint256[](1);
            amounts1[0] = 200e18;
            bytes32[][] memory proofs1 = new bytes32[][](1);
            proofs1[0] = new bytes32[](0);

            vm.prank(alice);
            distributor.claim(epochEndDates1, amounts1, proofs1, false);
        }

        assertEq(usds.balanceOf(alice), 200e18);
        assertTrue(distributor.hasClaimed(alice, epoch0EndDate + EPOCH_DURATION));

        // Now try to claim all three epochs (0, 1, 2) - should revert on epoch 1
        {
            uint256[] memory epochEndDates = new uint256[](3);
            epochEndDates[0] = epoch0EndDate;
            epochEndDates[1] = epoch0EndDate + EPOCH_DURATION; // Already claimed
            epochEndDates[2] = epoch0EndDate + 2 * EPOCH_DURATION;
            uint256[] memory amounts = new uint256[](3);
            amounts[0] = 100e18;
            amounts[1] = 200e18;
            amounts[2] = 300e18;
            bytes32[][] memory proofs = new bytes32[][](3);
            proofs[0] = new bytes32[](0);
            proofs[1] = new bytes32[](0);
            proofs[2] = new bytes32[](0);

            vm.prank(alice);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                    epoch0EndDate + EPOCH_DURATION
                )
            );
            distributor.claim(epochEndDates, amounts, proofs, false);
        }

        // Balance should remain unchanged (only the first claim of 200e18)
        assertEq(usds.balanceOf(alice), 200e18);
        // Only epoch 1 should be claimed
        assertFalse(distributor.hasClaimed(alice, epoch0EndDate));
        assertTrue(distributor.hasClaimed(alice, epoch0EndDate + EPOCH_DURATION));
        assertFalse(distributor.hasClaimed(alice, epoch0EndDate + 2 * EPOCH_DURATION));
    }

    function test_claim_reverts_duplicate_epoch_in_same_call() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Prepare claim data with duplicate epoch
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epochEndDate;
        epochEndDates[1] = epochEndDate; // Duplicate!
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = proof;
        proofs[1] = proof;

        // Should revert with AlreadyClaimed on the second occurrence
        // (the first occurrence marks it as claimed within the same tx)
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, proofs, false);

        // Verify nothing was claimed (tx reverted)
        assertEq(usds.balanceOf(alice), 0);
        assertFalse(distributor.hasClaimed(alice, epochEndDate));
    }

    function test_claim_reverts_invalid_proof() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);

        vm.warp(startTimestamp + EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount + 1; // Wrong amount
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Verify previewClaim returns 0 for invalid proof
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        vm.prank(alice);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidProof.selector);
        distributor.claim(epochEndDates, amounts, proofs, false);
    }

    function test_claim_reverts_using_another_users_proof() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf for Alice
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);
        bytes32[] memory proof = new bytes32[](0); // Single leaf tree

        vm.warp(startTimestamp + EPOCH_DURATION);
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Prepare claim data using Alice's proof
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Verify previewClaim returns 0 for Bob using Alice's proof
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            bob,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        // Bob tries to claim using Alice's proof - should fail
        vm.prank(bob);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidProof.selector);
        distributor.claim(epochEndDates, amounts, proofs, false);

        // Verify Bob received nothing
        assertEq(usds.balanceOf(bob), 0);
        assertFalse(distributor.hasClaimed(bob, epochEndDate));

        // Verify Alice can still claim with her proof
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, false);
        assertEq(usds.balanceOf(alice), amount);
        assertTrue(distributor.hasClaimed(alice, epochEndDate));
    }

    function test_claim_reverts_merkle_root_not_set() public {
        uint256 amount = 100e18;
        uint40 epochEndDate = _firstEpochEndDate();

        // Don't set root

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Verify previewClaim returns 0 when root not set
        (uint256 claimable, uint256 shares) = distributor.previewClaim(
            alice,
            epochEndDates,
            amounts,
            proofs
        );
        assertEq(claimable, 0);
        assertEq(shares, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_MerkleRootNotSet.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, proofs, false);
    }

    function test_claim_zero_rewards_reverts() public {
        uint256 amount = 0; // Zero rewards
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf for 0 rewards
        bytes32 leaf = _generateLeaf(alice, epochEndDate, amount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Claim should revert with 0 rewards
        vm.prank(alice);
        vm.expectRevert(IRewardDistributor.RewardDistributor_NothingToClaim.selector);
        distributor.claim(epochEndDates, amounts, proofs, false);
    }

    function test_endEpoch_zero_rewards_merkle_root_succeeds() public {
        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf for 0 rewards
        bytes32 leaf = _generateLeaf(alice, epochEndDate, 0);

        // Should succeed - setting root is valid even for zero rewards
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        assertEq(distributor.epochMerkleRoots(epochEndDate), leaf);
        assertEq(distributor.lastEpochEndDate(), epochEndDate);
    }

    // ========== Fuzz Tests for Yield Accrual ========== //

    function testFuzz_claim_as_underlying_with_yield(
        uint256 yieldAmount,
        uint256 claimAmount
    ) public {
        // Bound inputs to reasonable ranges
        claimAmount = bound(claimAmount, 1e18, 100_000e18);
        yieldAmount = bound(yieldAmount, 0, 1_000_000e18);

        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, epochEndDate, claimAmount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Simulate yield accruing to the vault by minting additional USDS
        usds.mint(address(sUSDS), yieldAmount);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Claim as underlying
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, false);

        // Verify user receives exactly the claim amount (not more due to rounding)
        assertEq(usds.balanceOf(alice), claimAmount);
        assertTrue(distributor.hasClaimed(alice, epochEndDate));
    }

    function testFuzz_claim_as_vault_token_with_yield(
        uint256 yieldAmount,
        uint256 claimAmount
    ) public {
        // Bound inputs to reasonable ranges
        claimAmount = bound(claimAmount, 1e18, 100_000e18);
        yieldAmount = bound(yieldAmount, 0, 1_000_000e18);

        uint40 epochEndDate = _firstEpochEndDate();

        // Generate leaf and proof
        bytes32 leaf = _generateLeaf(alice, epochEndDate, claimAmount);
        bytes32[] memory proof = new bytes32[](0);

        // Set root
        vm.prank(admin);
        distributor.endEpoch(epochEndDate, leaf);

        // Simulate yield accruing to the vault by minting additional USDS
        usds.mint(address(sUSDS), yieldAmount);

        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        // Claim as vault token
        vm.prank(alice);
        distributor.claim(epochEndDates, amounts, proofs, true);

        // Get the shares received
        uint256 sharesReceived = sUSDS.balanceOf(alice);

        // Convert shares back to underlying value
        uint256 underlyingValue = sUSDS.convertToAssets(sharesReceived);

        // Verify user receives shares worth at most the claim amount (rounding down)
        // Due to convertToShares rounding down, user should never get more than entitled
        assertLe(underlyingValue, claimAmount, "User received more than entitled due to rounding");
        assertTrue(distributor.hasClaimed(alice, epochEndDate));
    }
}
