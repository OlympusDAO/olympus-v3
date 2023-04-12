// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {Script} from 'forge-std/Script.sol';
// import {UniswapV3Factory} from "src/external/UniswapV3Factory.sol";

// /// @notice A very simple deployment script
// contract GdaoDeploy is Script {

//   /// @notice The main script entrypoint
//   /// @return gdao The deployed contract
//   function run() external returns (UniswapV3Factory univ3lp) {
//     // string memory seedPhrase = vm.readFile(".secret");
//     // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
//     uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
//     // vm.startBroadcast(privateKey);
//     vm.startBroadcast(deployerPrivateKey);
    
//     address UniV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

//     address test_gdao = vm.envAddress("SEPOLIA_GDAO");
//     address test_dai = vm.envAddress("SEPOLIA_DAI");
//     univ3lp = new UniswapV3Factory();

//     vm.stopBroadcast();
//     return univ3lp;
//   }
// }