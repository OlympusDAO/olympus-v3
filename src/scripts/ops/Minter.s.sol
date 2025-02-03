// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "forge-std/console2.sol";

import {Minter} from "src/policies/Minter.sol";

contract MinterScript is WithEnvironment {
    function addCategory(string calldata chain_, string calldata category_) external {
        _loadEnv(chain_);

        console2.log("Adding Minter category", category_);

        Minter(_envAddressNotZero("olympus.policies.minter")).addCategory(
            bytes32(bytes(category_))
        );

        console2.log("Category added");
    }

    function removeCategory(string calldata chain_, string calldata category_) external {
        _loadEnv(chain_);

        console2.log("Removing Minter category", category_);

        Minter(_envAddressNotZero("olympus.policies.minter")).removeCategory(
            bytes32(bytes(category_))
        );

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

        Minter(_envAddressNotZero("olympus.policies.minter")).mint(
            to_,
            amount_,
            bytes32(bytes(category_))
        );

        console2.log("Minted");
    }
}
