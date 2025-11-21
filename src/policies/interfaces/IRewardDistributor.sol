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

    // ========== ERRORS ========== //

    error DRD_InvalidWeek(uint256 week);
    error DRD_AlreadyClaimed(uint256 week);
    error DRD_InvalidProof();
    error DRD_NoWeeksSpecified();
    error DRD_MerkleRootNotSet(uint256 week);
    error DRD_ArrayLengthMismatch();
    error DRD_InvalidAddress();
    error DRD_InsufficientApproval();
    error DRD_WeekTooEarly();

    // ========== ADMIN FUNCTIONS ========== //

    function setMerkleRoot(
        uint40 rewardWeek_,
        bytes32 merkleRoot_,
        address rewardToken_
    ) external returns (uint256 week, uint256 timestamp);

    // ========== USER FUNCTIONS ========== //

    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external;

    // ========== VIEW FUNCTIONS ========== //

    function currentWeek() external view returns (uint40);

    function startTimestamp() external view returns (uint40);

    function WEEK_DURATION() external view returns (uint256);

    function weeklyMerkleRoots(uint256 week) external view returns (bytes32);

    function hasClaimed(address user, uint256 week) external view returns (bool);

    function weeklyRewardTokens(uint256 week) external view returns (address);
}
