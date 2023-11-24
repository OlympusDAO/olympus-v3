// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IStaking {
    /* ========== DATA STRUCTURES ========== */

    struct Epoch {
        uint256 length; // in seconds
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function rebase() external returns (uint256);

    function unstake(address, uint256, bool _trigger, bool) external returns (uint256);

    /* ========== ADMIN FUNCTIONS ========== */

    function setDistributor(address _distributor) external;

    /* ========== VIEW FUNCTIONS ========== */

    function secondsToNextEpoch() external view returns (uint256);
}
