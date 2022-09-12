// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";

import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusHeart} from "policies/Heart.sol";
import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy the Operator contract in the Olympus Bophades system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OperatorDeploy is Script {
    using TransferHelper for ERC20;
    Kernel public kernel;

    /// Policies
    OlympusHeart public heart;
    Operator public operator;
    BondCallback public callback;

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
    ERC20 public constant ohm = ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve = ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken = ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    /// Bond system addresses
    IBondAuctioneer public constant bondAuctioneer =
        IBondAuctioneer(0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b);

    function deploy() external {
        vm.startBroadcast();

        /// Set addresses for dependencies
        kernel = Kernel(0x64665B0429B21274d938Ed345e4520D1f5ABb9e7);
        callback = BondCallback(0x764E6578738E2606DBF3Be47746562F99380905c);
        address oldOperator = 0xD25b0441690BFD7e23Ab8Ee6f636Fce0C638ee32;
        address oldHeart = 0x5B7aF1a298FaC101445a7fE55f2738c071D70e9B;

        operator = new Operator(
            kernel,
            bondAuctioneer,
            callback,
            [ohm, reserve],
            [
                uint32(20_00), // cushionFactor
                uint32(5 days), // cushionDuration
                uint32(100_000), // cushionDebtBuffer
                uint32(4 hours), // cushionDepositInterval
                uint32(10_00), // reserveFactor
                uint32(1 hours), // regenWait
                uint32(18), // regenThreshold
                uint32(21) // regenObserve
                // uint32(8 hours) // observationFrequency
            ] // TODO verify initial parameters
        );
        console2.log("Operator deployed at:", address(operator));

        heart = new OlympusHeart(kernel, operator, rewardToken, 0);
        console2.log("Heart deployed at:", address(heart));

        /// Execute actions on Kernel
        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(operator));
        kernel.executeAction(Actions.ActivatePolicy, address(heart));

        // deactivate old operator
        kernel.executeAction(Actions.DeactivatePolicy, address(oldOperator));
        kernel.executeAction(Actions.DeactivatePolicy, address(oldHeart));

        vm.stopBroadcast();
    }

    /// @dev should be called by address with the guardian role
    function initialize() external {
        // Set addresses from deployment
        operator = Operator(0xD25b0441690BFD7e23Ab8Ee6f636Fce0C638ee32);
        callback = BondCallback(0x764E6578738E2606DBF3Be47746562F99380905c);

        /// Start broadcasting
        vm.startBroadcast();

        /// Set the operator address on the BondCallback contract
        callback.setOperator(operator);

        /// Initialize the Operator policy
        operator.initialize();

        /// Stop broadcasting
        vm.stopBroadcast();
    }
}
