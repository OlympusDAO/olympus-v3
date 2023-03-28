// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {Script} from 'forge-std/Script.sol';
// import {GoerliDaoVotes} from "src/modules/VOTES/GoerliDaoVotes.sol";
// import {Kernel} from "src/Kernel.sol";
// import {XGDAO} from "solmate/tokens/ERC20.sol";

// /// @notice A very simple deployment script
// contract Deployvotes is Script {

//   /// @notice The main script entrypoint
//   /// @return votes The deployed contract
//   function run() external returns (GoerliDaoVotes votes) {
//     string memory seedPhrase = vm.readFile(".secret");
//     uint256 privateKey = vm.deriveKey(seedPhrase, 0);
//     vm.startBroadcast(privateKey);
//     address kernel_addr = vm.envAddress("LOCAL_KERNEL");
//     address xgdao_addr = vm.envAddress("LOCAL_XGDAO_ADDR");

//     ERC20 xgdao = new ERC20(xgdao_addr);

//     Kernel kernel = Kernel(kernel_addr);

//     votes = new GoerliDaoVotes(kernel, xgdao);

//     vm.stopBroadcast();
//     return votes;
//   }
// }

//         // Module(kernel_)
//         // ERC4626(xGDAO_, "Goerli DAO Votes", "xGDAO")