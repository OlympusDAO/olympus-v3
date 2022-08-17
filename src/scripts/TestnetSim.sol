// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "balancer-v2/solidity-utils/contracts/openzeppelin/ERC20.sol";

import {WeightedPoolNoAMFactory, IVault, IERC20, IAsset, WeightedPool} from "balancer/pool-weighted/contracts/WeightedPoolNoAMFactory.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory name_, string memory symbol) ERC20(name_, symbol) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

/// @notice Script to deploy a Balancer pool for testing the Bophades Range system on testnet
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract WeightedPoolDeploy is Script {
    /// Goerli testnet addresses
    WeightedPoolNoAMFactory public constant wpFactory =
        WeightedPoolNoAMFactory(0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9);

    function deploy() external {
        vm.startBroadcast();

        // Get token addresses
        ERC20Mintable ohm = ERC20Mintable(vm.envAddress("OHM_ADDRESS")); // OHM goerli address
        ERC20Mintable dai = ERC20Mintable(vm.envAddress("DAI_ADDRESS")); // DAI goerli address

        // Create arrays to deploy pool
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = ohm;
        tokens[1] = dai;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;

        // Deploy a weighted DAI-OHM pool
        address pool = wpFactory.create(
            "DAI-OHM Pool",
            "DAI-OHM",
            tokens,
            weights,
            uint256(3e16), // 0.3% swap fee
            msg.sender
        );
        console2.log("Weighted Pool deployed at:", pool);

        // Mint tokens to bootstrap the pool
        uint256 amountOhm = 1_000_000 * 1e9;
        uint256 amountDai = 15_000_000 * 1e18;

        ohm.mint(msg.sender, amountOhm);
        dai.mint(msg.sender, amountDai);

        // Approve the vault
        IVault vault = wpFactory.getVault();
        ohm.approve(address(vault), amountOhm);
        dai.approve(address(vault), amountDai);

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
        assets[0] = IAsset(address(ohm));
        assets[1] = IAsset(address(dai));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountOhm;
        amounts[1] = amountDai;

        bytes memory data = abi.encode(uint256(0), amounts); // JoinKind.INIT

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            amounts,
            data,
            false
        );

        vault.joinPool(poolId, msg.sender, msg.sender, request);

        vm.stopBroadcast();
    }
}
