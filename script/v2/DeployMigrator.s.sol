// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.15;

// import {Script} from "forge-std/Script.sol";
// import {GdaoTokenMigrator} from "src/external/Migrator.sol";

// /// @notice A very simple deployment script
// contract MigratorDeploy is Script {

//   /// @notice The main script entrypoint
//   /// @return migrator The deployed contract
//   function run() external returns (GdaoTokenMigrator migrator) {
//     uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
//     // vm.startBroadcast(privateKey);
//     vm.startBroadcast(deployerPrivateKey);
//     address oldGDAO = vm.envAddress("GOERLI_TGD");
//     address oldsGDAO = vm.envAddress("GOERLI_SGDAO");
//     address oldTreasury = vm.envAddress("GOERLI_TREASURY");
//     address oldStaking = vm.envAddress("GOERLI_STAKING");
//     address oldwsOHM = vm.envAddress("GOERLI_WSOHM");
//     address sushi = vm.envAddress("GOERLI_SUSHI");
//     address uni = vm.envAddress("GOERLI_UNI");
//     uint256 timelock = 7000;
//     address authority = vm.envAddress("GOERLI_AUTHORITY");

//     migrator = new GdaoTokenMigrator(oldGDAO, oldsGDAO, oldTreasury, oldStaking, oldwsOHM, sushi, uni, timelock, authority);

//     vm.stopBroadcast();
//     return migrator;
//   }
// }


//         // address _oldGDAO,
//         // address _oldsGDAO,
//         // address _oldTreasury,
//         // address _oldStaking,
//         // address _oldwsOHM,
//         // address _sushi,
//         // address _uni,
//         // uint256 _timelock,
//         // address _authority
