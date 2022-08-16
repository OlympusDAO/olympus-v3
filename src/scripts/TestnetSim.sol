// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.0;

import {Script, console2} from "forge-std/Script.sol";

import {WeightedPoolNoAMFactory, IERC20, IVault, IAsset, WeightedPool} from "balancer/pool-weighted/contracts/WeightedPoolNoAMFactory.sol";

/// @notice Script to deploy a Balancer pool for testing the Bophades Range system on testnet
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract WeightedPoolDeploy is Script {
    /// Goerli testnet addresses
    WeightedPoolNoAMFactory public constant wpFactory =
        WeightedPoolNoAMFactory(0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9);
    IERC20 public constant ohm = IERC20(vm.envAddress("OHM")); // OHM goerli address
    IERC20 public constant dai = IERC20(vm.envAddress("DAI")); // DAI goerli address

    function deploy() external {
        vm.startBroadcast();

        // Deploy a weighted DAI-OHM pool
        address pool = wpFactory.create(
            "DAI-OHM Pool",
            "DAI-OHM",
            [dai, ohm],
            [5e17, 5e17],
            3e16, // 0.3% swap fee
            address(0x0) // no owner
        );
        console2.log("Weighted Pool deployed at:", pool);

        // Mint tokens to bootstrap the pool
        uint256 amountOhm = 1_000_000 * 1e9;
        uint256 amountDai = 15_000_000 * 1e18;

        ohm.mint(msg.sender, amountOhm);
        dai.mint(msg.sender, amountDai);

        // Approve the vault
        IVault vault = wpFactory.getVault();
        ohm.approve(vault, amountOhm);
        dai.approve(vault, amountDai);

        // Deposit liquidity to the pool
        // Interface for joinPool:
        // function joinPool(
        //     bytes32 poolId,
        //     address sender,
        //     address recipient,
        //     JoinPoolRequest memory request
        // ) external payable;

        // struct JoinPoolRequest {
        //     IAsset[] assets;
        //     uint256[] maxAmountsIn;
        //     bytes userData;
        //     bool fromInternalBalance;
        // }

        bytes32 poolId = WeightedPool(pool).getPoolId();

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(dai));
        assets[1] = IAsset(address(ohm));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountDai;
        amounts[1] = amountOhm;

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            amounts,
            bytes(0), // no data
            false
        );

        vault.joinPool(poolId, msg.sender, msg.sender, request);

        vm.stopBroadcast();
    }
}
