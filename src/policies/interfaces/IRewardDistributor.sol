// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title  IRewardDistributor
/// @notice Interface for the Reward Distributor contract
interface IRewardDistributor is IERC165 {
    // ========== EVENTS ========== //

    event MerkleRootSet(uint256 indexed week, bytes32 merkleRoot, address rewardToken);
    event RewardsClaimed(
        address indexed user,
        uint256 totalAmount,
        address rewardToken,
        uint256 weekCount
    );
    event RewardsClaimedViaVault(
        address indexed user,
        uint256 rewardAmount,
        uint256 vaultShares,
        address vaultToken,
        uint256 weekCount
    );

    // ========== ERRORS ========== //

    error DRD_WeekAlreadySet(uint256 week);
    error DRD_AlreadyClaimed(uint256 week);
    error DRD_InvalidProof();
    error DRD_NoWeeksSpecified();
    error DRD_MerkleRootNotSet(uint256 week);
    error DRD_ArrayLengthMismatch();
    error DRD_InvalidAddress();
    error DRD_WeekTooEarly();

    // ========== ADMIN FUNCTIONS ========== //

    function setMerkleRoot(
        uint40 week_,
        bytes32 merkleRoot_
    ) external returns (uint256 timestamp);

    // ========== USER FUNCTIONS ========== //

    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external;

    function claimAsVaultToken(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external;

    // ========== VIEW FUNCTIONS ========== //

    function previewClaim(
        address user_,
        uint256[] calldata claimWeeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares);

    function START_TIMESTAMP() external view returns (uint40);

    function WEEK_DURATION() external view returns (uint256);

    function weeklyMerkleRoots(uint256 week) external view returns (bytes32);

    function hasClaimed(address user, uint256 week) external view returns (bool);
}
