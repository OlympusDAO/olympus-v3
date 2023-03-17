// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {Script} from 'forge-std/Script.sol';
// import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
// import {GoerliDaoRange} from "src/modules/RANGE/GoerliDaoRange.sol";
// import {Kernel} from "src/Kernel.sol";

// /// @notice A very simple deployment script
// contract DeployRange is Script {

//   /// @notice The main script entrypoint
//   /// @return range The deployed contract
//   function run() external returns (GoerliDaoRange range) {
//     string memory seedPhrase = vm.readFile(".secret");
//     uint256 privateKey = vm.deriveKey(seedPhrase, 0);
//     vm.startBroadcast(privateKey);
//     address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
//     address gdao_erc20 = ;
//     address reserve_addr = ;
//     uint256 thresholdFactor = 1000000000000000000; // 1
//     uint256 cushionSpread = 1000000000000000000; // 1
//     uint256 wallSpread = 1000000000000000000; // 1
    
//     Kernel kernel = Kernel(kernel_addr);

//     range = new GoerliDaoRange(kernel, gdao_erc20, reserve_addr, thresholdFactor, cushionSpread, wallSpread);

//     vm.stopBroadcast();
//     return range;
//   }
// }

//         // Kernel kernel_,
//         // ERC20 gdao_,
//         // ERC20 reserve_,
//         // uint256 thresholdFactor_,
//         // uint256 cushionSpread_,
//         // uint256 wallSpread_