// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IAuraRewardPool {
    function earned(address account_) external view returns (uint256);

    function getReward(address account_, bool claimExtras_) external;

    function withdrawAndUnwrap(uint256 amount_, bool claim_) external;
}
