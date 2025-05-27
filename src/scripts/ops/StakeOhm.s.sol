// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {WithEnvironment} from "../WithEnvironment.s.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {console2} from "forge-std/console2.sol";

interface IStaking {
    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256);
}

// solhint-disable gas-custom-errors
contract StakeOhmScript is WithEnvironment {
    function stakeOhm(string calldata chain_, address to_, uint256 amount_) public {
        _loadEnv(chain_);

        address staking = _envAddress("olympus.legacy.Staking");

        vm.startBroadcast();

        // Check the recipient
        address deployer = msg.sender;
        if (deployer == address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38)) {
            revert("Cannot use the default foundry deployer address, specify using --sender");
        } else {
            console2.log("Deployer", deployer);
        }

        // Approve spending of OHM
        ERC20(_envAddress("olympus.legacy.OHM")).approve(staking, amount_);
        // Mint GOhm
        IStaking(staking).stake(to_, amount_, false, true);
        vm.stopBroadcast();
    }
}
