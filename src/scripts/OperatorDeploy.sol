// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.11;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAuctioneer} from "../interfaces/IBondAuctioneer.sol";

import {Kernel, Actions} from "../Kernel.sol";

import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {MockAuthGiver} from "../test/mocks/MockAuthGiver.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy the Operator contract in the Olympus Bophades system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OperatorDeploy is Script {
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
        IBondAuctioneer(0x130a364655c5889D665caBa74FbD3bFa1448b99B);

    function deploy() external {
        vm.startBroadcast();

        /// Set addresses for dependencies
        kernel = Kernel(0x3B294580Fcf1F60B94eca4f4CE78A2f52D23cC83);
        callback = BondCallback(0x308fD958B191fdAEa000a1c0c5A2EB6FceB31DeD);
        address oldOperator = 0xc67733c29960e2c534949fB1795caEf353aC262F;

        operator = new Operator(
            kernel,
            bondAuctioneer,
            callback,
            [ohm, reserve],
            [
                uint32(20_00), // cushionFactor
                uint32(5 days), // cushionDuration
                uint32(100_000), // cushionDebtBuffer
                uint32(2 hours), // cushionDepositInterval
                uint32(10_00), // reserveFactor
                uint32(1 hours), // regenWait
                uint32(8), // regenThreshold
                uint32(11) // regenObserve
            ] // TODO verify initial parameters
        );
        console2.log("Operator deployed at:", address(operator));

        // Deploy auth giver to set Operator roles

        authGiver = new MockAuthGiver(kernel);
        console2.log("Auth Giver deployed at:", address(authGiver));

        /// Execute actions on Kernel
        /// Approve policies
        kernel.executeAction(Actions.ApprovePolicy, address(operator));
        kernel.executeAction(Actions.ApprovePolicy, address(authGiver));

        // Terminate old operator
        kernel.executeAction(Actions.TerminatePolicy, address(oldOperator));

        /// Set initial access control for policies on the AUTHR module
        /// Set role permissions

        /// Role 0 = Heart
        authGiver.setRoleCapability(
            uint8(0),
            address(operator),
            operator.operate.selector
        );

        /// Role 1 = Guardian
        authGiver.setRoleCapability(
            uint8(1),
            address(operator),
            operator.operate.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(operator),
            operator.setBondContracts.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(operator),
            operator.initialize.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(operator),
            operator.regenerate.selector
        );

        /// Role 2 = Policy
        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setSpreads.selector
        );

        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setThresholdFactor.selector
        );

        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setCushionFactor.selector
        );
        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setCushionParams.selector
        );
        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setReserveFactor.selector
        );
        authGiver.setRoleCapability(
            uint8(2),
            address(operator),
            operator.setRegenParams.selector
        );

        /// Give role to operator
        authGiver.setUserRole(address(operator), uint8(3));

        /// Terminate mock auth giver
        kernel.executeAction(Actions.TerminatePolicy, address(authGiver));

        vm.stopBroadcast();
    }
}
