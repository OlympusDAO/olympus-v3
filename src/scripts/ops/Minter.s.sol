// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {Minter} from "src/policies/Minter.sol";

contract MinterScript is WithEnvironment {
    function addCategory(string calldata chain_, string calldata category_) external {
        _loadEnv(chain_);

        console2.log("Adding Minter category", category_);

        vm.startBroadcast();
        Minter(_envAddressNotZero("olympus.policies.Minter")).addCategory(
            bytes32(bytes(category_))
        );
        vm.stopBroadcast();

        console2.log("Category added");
    }

    function removeCategory(string calldata chain_, string calldata category_) external {
        _loadEnv(chain_);

        console2.log("Removing Minter category", category_);

        vm.startBroadcast();
        Minter(_envAddressNotZero("olympus.policies.Minter")).removeCategory(
            bytes32(bytes(category_))
        );
        vm.stopBroadcast();

        console2.log("Category removed");
    }

    function mint(
        string calldata chain_,
        string calldata category_,
        address to_,
        uint256 amount_
    ) external {
        _loadEnv(chain_);

        console2.log("Minting ", amount_, " to ", to_);

        vm.startBroadcast();
        Minter(_envAddressNotZero("olympus.policies.Minter")).mint(
            to_,
            amount_,
            bytes32(bytes(category_))
        );
        vm.stopBroadcast();

        console2.log("Minted");
    }
}
