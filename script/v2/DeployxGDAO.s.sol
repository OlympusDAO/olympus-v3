// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";

import {xGDAO} from "src/external/xGDAO.sol";

/// @notice A very simple deployment script
contract xGdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return xgdao The deployed contract
  function run() external returns (xGDAO xgdao) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address migrator = vm.envAddress("GOERLI_DEPLOYER");
    address sGDAO = vm.envAddress("GOERLI_SGDAO"); 

    xgdao = new xGDAO(migrator, sGDAO);

    vm.stopBroadcast();
    return xgdao;
  }
}

    // constructor(address _migrator, address _sGDAO)
