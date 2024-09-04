// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {IStaking} from "interfaces/IStaking.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";

contract MockStakingZD is IStaking {
    Epoch public epoch;
    ZeroDistributor public distributor;

    constructor(uint256 _epochLength, uint256 _firstEpochNumber, uint256 _firstEpochTime) {
        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            end: _firstEpochTime,
            distribute: 0
        });
    }

    function rebase() public returns (uint256) {
        uint256 bounty;
        if (epoch.end <= block.timestamp) {
            epoch.end += epoch.length;
            epoch.number++;

            if (address(distributor) != address(0)) {
                distributor.distribute();
                bounty = distributor.retrieveBounty();
            }
        }
        return bounty;
    }

    function unstake(address, uint256, bool trigger_, bool) external returns (uint256 bounty) {
        if (trigger_) bounty = rebase();
    }

    function setDistributor(address _distributor) external {
        distributor = ZeroDistributor(_distributor);
    }

    function secondsToNextEpoch() external view returns (uint256) {
        return epoch.end > block.timestamp ? epoch.end - block.timestamp : 0;
    }
}
