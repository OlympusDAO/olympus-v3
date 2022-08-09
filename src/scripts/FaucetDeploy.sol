// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/Kernel.sol";
import {Faucet} from "test/mocks/Faucet.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy a faucet for testing the Bophades Range system on testnet
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract FaucetDeploy is Script {
    using TransferHelper for ERC20;
    Kernel public kernel;

    /// Policies
    Faucet public faucet;
    address public oldFaucet;

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

        kernel = Kernel(0x773fa2A1399A413a878ff8f0266B9b5E9d0068d6);
        oldFaucet = 0xf670b97C2B040e10E203b99a75fE71198B00c773;

        /// Deploy new faucet
        faucet = new Faucet(
            kernel,
            ohm,
            reserve,
            1 ether,
            1_000_000 * 1e9,
            10_000_000 * 1e18,
            1 hours
        );
        console2.log("Faucet deployed at:", address(faucet));

        /// Execute actions on Kernel

        /// Approve policies
        kernel.executeAction(Actions.DeactivatePolicy, oldFaucet);
        kernel.executeAction(Actions.ActivatePolicy, address(faucet));

        vm.stopBroadcast();
    }
}
