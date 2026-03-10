// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

interface IStaking {
    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 end;
        uint256 distribute;
    }

    function OHM() external view returns (address);

    function sOHM() external view returns (address);

    function gOHM() external view returns (address);

    function index() external view returns (uint256);

    function supplyInWarmup() external view returns (uint256);

    function rebase() external returns (uint256);

    function stake(
        address to_,
        uint256 amount_,
        bool rebasing_,
        bool claim_
    ) external returns (uint256);

    function unstake(
        address to_,
        uint256 amount_,
        bool trigger_,
        bool rebasing_
    ) external returns (uint256);

    function setDistributor(address _distributor) external;

    function secondsToNextEpoch() external view returns (uint256);

    function epoch() external view returns (uint256, uint256, uint256, uint256);
}
