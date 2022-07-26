// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.11;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {Kernel, Actions} from "src/Kernel.sol";

import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {MockAuthGiver} from "../test/mocks/MockAuthGiver.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy the BondCallback contract in the Olympus Bophades system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract CallbackDeploy is Script {
    using TransferHelper for ERC20;
    Kernel public kernel;

    /// Policies
    Operator public operator;
    BondCallback public callback;
    MockAuthGiver public authGiver;

    /// Construction variables

    /// Mainnet addresses
    // ERC20 public constant ohm =
    //     ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5); // OHM mainnet address
    // ERC20 public constant reserve =
    //     ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI mainnet address
    // ERC20 public constant rewardToken =
    //     ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH mainnet address

    // IBondAuctioneer public constant bondAuctioneer =
    //     IBondAuctioneer(address(0));

    /// Goerli testnet addresses
    ERC20 public constant ohm =
        ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve =
        ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken =
        ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    /// Bond system addresses
    IBondAuctioneer public constant bondAuctioneer =
        IBondAuctioneer(0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b);
    IBondAggregator public constant bondAggregator =
        IBondAggregator(0xB4860B2c12C6B894B64471dFb5a631ff569e220e);

    function deploy() external {
        vm.startBroadcast();

        /// Set addresses for dependencies
        kernel = Kernel(0x64665B0429B21274d938Ed345e4520D1f5ABb9e7);
        address oldCallback = 0x86F5abAE1F72d34C4D475C72483a38699770ED2a;
        operator = Operator(0x0bFFdE707B76Abe13f77f52f6E359c846AE0680d);
        authGiver = MockAuthGiver(0x3714fDFc3b6918923e5b2AbAe0fcD74376Be45fc);

        callback = new BondCallback(kernel, bondAggregator, ohm);

        /// Execute actions on Kernel
        /// Approve policies
        kernel.executeAction(Actions.ApprovePolicy, address(callback));

        // Terminate old callback
        kernel.executeAction(Actions.TerminatePolicy, address(oldCallback));

        /// Set initial access control for policies on the AUTHR module
        /// Set role permissions

        /// Role 1 = Guardian
        authGiver.setRoleCapability(
            uint8(1),
            address(callback),
            callback.setOperator.selector
        );

        /// Role 2 = Policy
        authGiver.setRoleCapability(
            uint8(2),
            address(callback),
            callback.batchToTreasury.selector
        );
        authGiver.setRoleCapability(
            uint8(2),
            address(callback),
            callback.whitelist.selector
        );

        /// Role 3 = Operator
        authGiver.setRoleCapability(
            uint8(3),
            address(callback),
            callback.whitelist.selector
        );

        /// Give roles to users
        authGiver.setUserRole(address(callback), uint8(4));

        vm.stopBroadcast();
    }

    /// @dev should be called by address with the guardian role
    function initialize() external {
        // Set addresses from deployment
        operator = Operator(0x0bFFdE707B76Abe13f77f52f6E359c846AE0680d);
        callback = BondCallback(0x764E6578738E2606DBF3Be47746562F99380905c);

        /// Start broadcasting
        vm.startBroadcast();

        /// Set the operator address on the BondCallback contract
        callback.setOperator(operator);

        /// Set the bond auctioneer and callback on the Operator contract
        operator.setBondContracts(bondAuctioneer, callback);

        /// Stop broadcasting
        vm.stopBroadcast();
    }
}
