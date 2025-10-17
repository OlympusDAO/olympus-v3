// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

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

    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256);

    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256);

    /* ========== ADMIN FUNCTIONS ========== */

    function setDistributor(address _distributor) external;

    /* ========== VIEW FUNCTIONS ========== */

    function secondsToNextEpoch() external view returns (uint256);

    function epoch() external view returns (uint256, uint256, uint256, uint256);

    function warmupPeriod() external view returns (uint256);

    function OHM() external view returns (address);

    function gOHM() external view returns (address);
}
