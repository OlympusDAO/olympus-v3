// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {Script} from 'forge-std/Script.sol';
// import {Operator} from "src/policies/Operator.sol";
// import {Kernel} from "src/Kernel.sol";

// /// @notice A very simple deployment script
// contract DeployOperator is Script {

//   /// @notice The main script entrypoint
//   /// @return operator The deployed contract
//   function run() external returns (Operator operator) {
//     string memory seedPhrase = vm.readFile(".secret");
//     uint256 privateKey = vm.deriveKey(seedPhrase, 0);
//     vm.startBroadcast(privateKey);
//     address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
//     Kernel kernel = Kernel(kernel_addr);

//     operator = new Operator(kernel, );

//     vm.stopBroadcast();
//     return operator;
//   }
// }
//     //   Kernel kernel_,
//     //     IBondSDA auctioneer_,
//     //     IBondCallback callback_,
//     //     ERC20[2] memory tokens_, // [gdao, reserve]
//     //     uint32[8] memory configParams // [cushionFactor, cushionDuration, cushionDebtBuffer, cushionDepositInterval, reserveFactor, regenWait, regenThreshold, regenObserve] ensure the following holds: regenWait / PRICE.observationFrequency() >= regenObserve - regenThreshold
    