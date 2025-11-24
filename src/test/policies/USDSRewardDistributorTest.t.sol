// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {USDSRewardDistributor} from "policies/USDSRewardDistributor.sol";
import {IRewardDistributor} from "policies/interfaces/IRewardDistributor.sol";

/// @notice Simple mock ERC4626 vault for testing
contract MockERC4626 is MockERC20 {
    ERC20 public immutable asset;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address asset_
    ) MockERC20(name_, symbol_, decimals_) {
        asset = ERC20(asset_);
    }

    function previewWithdraw(uint256 assets_) external pure returns (uint256) {
        // 1:1 conversion for simplicity in tests
        return assets_;
    }

    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) external returns (uint256 shares) {
        // Simple 1:1 mock implementation
        shares = assets_;
        asset.transfer(receiver_, assets_);
        _burn(owner_, shares);
    }
}

/// @notice Basic unit tests for USDSRewardDistributor contract
/// Note: Full integration tests require complex Kernel setup. These tests focus on
/// contract initialization, state variables, and event emission.
contract USDSRewardDistributorTest is Test {
    MockERC20 internal usds;
    MockERC4626 internal sUSDS;
    USDSRewardDistributor internal distributor;

    uint40 internal constant WEEK_DURATION = 7 days;
    uint40 internal startTimestamp;

    // Mock Kernel for basic initialization
    address internal mockKernel = address(0x1234);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021
        startTimestamp = uint40(block.timestamp);

        // Deploy mock tokens
        usds = new MockERC20("USDS", "USDS", 18);
        sUSDS = new MockERC4626("Vault Token", "vToken", 18, address(usds));

        // Deploy distributor with mock kernel
        distributor = new USDSRewardDistributor(mockKernel, address(sUSDS), startTimestamp);
    }

    // ========== Test Constructor and State Variables ========== //

    function test_constructor_initializes_correctly() public view {
        assertEq(address(distributor.REWARD_TOKEN_VAULT().asset()), address(usds));
        assertEq(address(distributor.REWARD_TOKEN_VAULT()), address(sUSDS));
        assertEq(distributor.START_TIMESTAMP(), startTimestamp);
        assertEq(distributor.WEEK_DURATION(), WEEK_DURATION);
    }

    function test_constructor_rejects_zero_reward_token_vault() public {
        vm.expectRevert(IRewardDistributor.DRD_InvalidAddress.selector);
        new USDSRewardDistributor(mockKernel, address(0), startTimestamp);
    }

    function test_constructor_rejects_zero_start_timestamp() public {
        vm.expectRevert(IRewardDistributor.DRD_InvalidAddress.selector);
        new USDSRewardDistributor(mockKernel, address(sUSDS), 0);
    }

    // ========== Test State Variables ========== //

    function test_rewardToken_is_immutable() public view {
        assertEq(address(distributor.REWARD_TOKEN()), address(usds));
    }

    function test_vaultToken_is_immutable() public view {
        assertEq(address(distributor.REWARD_TOKEN_VAULT()), address(sUSDS));
    }

    function test_startTimestamp_is_immutable() public view {
        assertEq(distributor.START_TIMESTAMP(), startTimestamp);
    }

    function test_weekDuration_is_constant() public view {
        assertEq(distributor.WEEK_DURATION(), 7 days);
    }

    // ========== Test supportsInterface ========== //

    function test_supportsInterface() public view {
        assertTrue(distributor.supportsInterface(type(IRewardDistributor).interfaceId));
    }

    // ========== Test Merkle Root Mapping ========== //

    function test_weeklyMerkleRoots_initially_empty() public view {
        assertEq(distributor.weeklyMerkleRoots(0), bytes32(0));
        assertEq(distributor.weeklyMerkleRoots(5), bytes32(0));
        assertEq(distributor.weeklyMerkleRoots(100), bytes32(0));
    }

    // ========== Test Claimed Mapping ========== //

    function test_hasClaimed_initially_false() public view {
        address testUser = address(0xABCD);
        assertFalse(distributor.hasClaimed(testUser, 0));
        assertFalse(distributor.hasClaimed(testUser, 5));
    }

    // ========== Test VERSION ========== //

    function test_version() public view {
        (uint8 major, uint8 minor) = distributor.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    // ========== Test Multiple Instances ========== //

    function test_multiple_distributors_independent() public {
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);
        MockERC20 token2 = new MockERC20("Token2", "T2", 18);
        MockERC4626 vault1 = new MockERC4626("Vault1", "V1", 18, address(token1));
        MockERC4626 vault2 = new MockERC4626("Vault2", "V2", 18, address(token2));

        USDSRewardDistributor dist1 = new USDSRewardDistributor(
            mockKernel,
            address(vault1),
            startTimestamp
        );

        USDSRewardDistributor dist2 = new USDSRewardDistributor(
            mockKernel,
            address(vault2),
            startTimestamp + 1 days
        );

        // Verify they have different state
        assertEq(address(dist1.REWARD_TOKEN()), address(token1));
        assertEq(address(dist2.REWARD_TOKEN()), address(token2));
        assertEq(address(dist1.REWARD_TOKEN_VAULT()), address(vault1));
        assertEq(address(dist2.REWARD_TOKEN_VAULT()), address(vault2));
        assertEq(dist1.START_TIMESTAMP(), startTimestamp);
        assertEq(dist2.START_TIMESTAMP(), startTimestamp + 1 days);
    }

    // ========== Test PreviewClaim Function ========== //

    function test_previewClaim_returns_zero_when_no_weeks_specified() public view {
        address testUser = address(0xABCD);
        uint256[] memory claimWeeks = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);

        (uint256 claimableAmount, uint256 vaultShares) = distributor.previewClaim(testUser, claimWeeks, amounts, proofs);
        assertEq(claimableAmount, 0);
        assertEq(vaultShares, 0);
    }

    function test_previewClaim_returns_zero_when_array_lengths_mismatch() public view {
        address testUser = address(0xABCD);
        uint256[] memory claimWeeks = new uint256[](2);
        uint256[] memory amounts = new uint256[](1); // Mismatched length
        bytes32[][] memory proofs = new bytes32[][](2);

        (uint256 claimableAmount, uint256 vaultShares) = distributor.previewClaim(testUser, claimWeeks, amounts, proofs);
        assertEq(claimableAmount, 0);
        assertEq(vaultShares, 0);
    }

    function test_previewClaim_returns_zero_when_merkle_root_not_set() public view {
        address testUser = address(0xABCD);
        uint256[] memory claimWeeks = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

        claimWeeks[0] = 0;
        amounts[0] = 1000e18;
        proofs[0] = new bytes32[](1);

        (uint256 claimableAmount, uint256 vaultShares) = distributor.previewClaim(testUser, claimWeeks, amounts, proofs);
        assertEq(claimableAmount, 0);
        assertEq(vaultShares, 0);
    }

    // ========== Test Claim Error Conditions ========== //
    // Note: These tests require proper Kernel setup with ROLES and TRSRY modules
    // and policy enablement, so are better suited as integration tests.
    // The underlying validation logic (_validateClaimArrays) is tested in preview functions.
}
