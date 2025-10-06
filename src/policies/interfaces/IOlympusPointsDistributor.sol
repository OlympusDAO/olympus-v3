// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title  IOlympusPointsDistributor
/// @notice Interface for the Olympus Points Distributor contract
interface IOlympusPointsDistributor is IERC165 {
    // ========== EVENTS ========== //

    event MerkleRootSet(uint256 indexed week, bytes32 merkleRoot, address rewardToken, string ipfsHash);
    event RewardsClaimed(
        address indexed user,
        uint256 totalAmount,
        address rewardToken,
        uint256 weekCount
    );
    event WeekAdvanced(uint256 indexed newWeek);
    event RewardTokenUpdated(uint256 indexed week, address indexed oldToken, address indexed newToken);

    // ========== ERRORS ========== //

    error OPD_InvalidWeek(uint256 week);
    error OPD_AlreadyClaimed(uint256 week);
    error OPD_InvalidProof();
    error OPD_NoWeeksSpecified();
    error OPD_MerkleRootNotSet(uint256 week);
    error OPD_ArrayLengthMismatch();
    error OPD_InvalidAddress();
    error OPD_ZeroAmount();
    error OPD_InsufficientApproval();

    // ========== ADMIN FUNCTIONS ========== //

    function setMerkleRoot(
        uint256 week_,
        bytes32 merkleRoot_,
        address rewardToken_,
        string calldata ipfsHash_
    ) external;

    function setMerkleRootBatch(
        uint256[] calldata weeks_,
        bytes32[] calldata merkleRoots_,
        address[] calldata rewardTokens_,
        string[] calldata ipfsHashes_
    ) external;

    function advanceWeek() external;

    function updateRewardToken(uint256 week_, address rewardToken_) external;

    // ========== USER FUNCTIONS ========== //

    function claimWeek(uint256 week_, uint256 amount_, bytes32[] calldata proof_) external;

    function claimMultipleWeeks(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external;

    function claimMultipleWeeksMultiToken(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external;

    // ========== VIEW FUNCTIONS ========== //

    function hasUserClaimedWeek(address user_, uint256 week_) external view returns (bool);

    function getMerkleRoot(uint256 week_) external view returns (bytes32);

    function getRewardToken(uint256 week_) external view returns (address);

    function getTotalClaimed(address user_, address token_) external view returns (uint256);

    function getWeeklyDistributed(uint256 week_) external view returns (uint256);

    function getWeeklyMetadata(uint256 week_) external view returns (string memory);

    function previewClaim(
        address user_,
        uint256 week_
    ) external view returns (bool canClaim, string memory reason);

    function currentWeek() external view returns (uint256);

    function weeklyMerkleRoots(uint256 week) external view returns (bytes32);

    function hasClaimed(address user, uint256 week) external view returns (bool);

    function weeklyRewardTokens(uint256 week) external view returns (address);

    function totalClaimed(address user, address token) external view returns (uint256);

    function weeklyRewardsDistributed(uint256 week) external view returns (uint256);

    function weeklyMetadata(uint256 week) external view returns (string memory);
}

