// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {WithEnvironment} from "../WithEnvironment.s.sol";

interface IStaking {
    function setDistributor(address _distributor) external;
}

interface IGohm {
    function transfer(address to, uint256 amount) external;
}

contract SetStakingDistributor is WithEnvironment {
    function setStakingZeroDistributor(string calldata chain_) public {
        _loadEnv(chain_);

        vm.startBroadcast();
        IStaking(_envAddress("olympus.legacy.Staking")).setDistributor(address(0));
        vm.stopBroadcast();
    }
}
