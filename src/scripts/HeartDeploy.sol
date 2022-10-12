// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";

/// @notice Script to deploy and initialize the Heart contract in the Olympus Bophades system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract HeartDeploy is Script {
    Kernel public kernel;

    /// Policies
    Operator public operator;
    OlympusHeart public heart;

    /// Construction variables

    /// Mainnet addresses
    // ERC20 public constant ohm =
    //     ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5); // OHM mainnet address
    // ERC20 public constant reserve =
    //     ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI mainnet address
    // ERC20 public constant rewardToken =
    //     ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH mainnet address

    /// Goerli testnet addresses
    ERC20 public constant ohm = ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve = ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken = ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    function deploy() external {
        vm.startBroadcast();

        /// Set dependency addresses
        kernel = Kernel(0x3B294580Fcf1F60B94eca4f4CE78A2f52D23cC83);
        operator = Operator(0xD25b0441690BFD7e23Ab8Ee6f636Fce0C638ee32);
        address oldHeart = 0x5B7aF1a298FaC101445a7fE55f2738c071D70e9B;

        // Deploy heart and authGiver

        heart = new OlympusHeart(kernel, operator, rewardToken, 0);
        console2.log("Heart deployed at:", address(heart));

        /// Execute actions on Kernel

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(heart));

        /// deactivate old policies
        kernel.executeAction(Actions.DeactivatePolicy, address(oldHeart));

        vm.stopBroadcast();
    }

    /// @dev must call with address which has "heart_admin" role
    function setRewardTokenAndAmount(ERC20 token, uint256 amount) external {
        // Load address from environment
        heart = OlympusHeart(vm.envAddress("HEART"));

        vm.broadcast();
        heart.setRewardTokenAndAmount(token, amount);
    }
}
