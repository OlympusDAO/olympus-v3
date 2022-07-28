// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.11;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IWETH9} from "interfaces/IWETH9.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusAuthority} from "modules/AUTHR.sol";
import {OlympusPrice} from "modules/PRICE.sol";
import {OlympusRange} from "modules/RANGE.sol";
import {OlympusTreasury} from "modules/TRSRY.sol";
import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusInstructions} from "modules/INSTR.sol";
import {OlympusVotes} from "modules/VOTES.sol";

import {Operator} from "policies/Operator.sol";
import {Heart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {VoterRegistration} from "policies/VoterRegistration.sol";
import {Governance} from "policies/Governance.sol";
import {MockAuthGiver} from "test/mocks/MockAuthGiver.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy and initialize the Olympus system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OlympusDeploy is Script {
    using TransferHelper for ERC20;
    Kernel public kernel;

    /// Modules
    OlympusAuthority public AUTHR;
    OlympusPrice public PRICE;
    OlympusRange public RANGE;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    OlympusInstructions public INSTR;
    OlympusVotes public VOTES;

    /// Policies
    Operator public operator;
    Heart public heart;
    BondCallback public callback;
    OlympusPriceConfig public priceConfig;
    VoterRegistration public voterReg;
    Governance public governance;
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
    // IBondAggregator public constant bondAggregator =
    //     IBondAggregator(address(0));

    // AggregatorV2V3Interface public constant ohmEthPriceFeed =
    //     AggregatorV2V3Interface(0x9a72298ae3886221820B1c878d12D872087D3a23); // OHM/ETH chainlink address
    // AggregatorV2V3Interface public constant reserveEthPriceFeed =
    //     AggregatorV2V3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4); // DAI/ETH chainlink address

    /// Goerli testnet addresses
    ERC20 public constant ohm =
        ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve =
        ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken =
        ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    /// Bond system addresses
    IBondAuctioneer public constant bondAuctioneer =
        IBondAuctioneer(0x85A41eCdefAA441C71C94a47FDD04e4509a2944a);
    IBondAggregator public constant bondAggregator =
        IBondAggregator(0x2B33ABcb816AeE1BB38fa84537329955f79d900e);

    /// Mock Price Feed addresses
    AggregatorV2V3Interface public constant ohmEthPriceFeed =
        AggregatorV2V3Interface(0x022710a589C9796dce59A0C52cA4E36f0a5e991A); // OHM/ETH chainlink address
    AggregatorV2V3Interface public constant reserveEthPriceFeed =
        AggregatorV2V3Interface(0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233); // DAI/ETH chainlink address

    function deploy(address guardian_, address policy_) external {
        vm.startBroadcast();

        /// Deploy kernel first
        kernel = new Kernel(); // sender will be executor initially
        console2.log("Kernel deployed at:", address(kernel));

        /// Deploy modules
        INSTR = new OlympusInstructions(kernel);
        console2.log("Instructions module deployed at:", address(INSTR));

        VOTES = new OlympusVotes(kernel);
        console2.log("Votes module deployed at:", address(INSTR));

        AUTHR = new OlympusAuthority(kernel);
        console2.log("Authority module deployed at:", address(AUTHR));

        TRSRY = new OlympusTreasury(kernel);
        console2.log("Treasury module deployed at:", address(TRSRY));

        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("Minter module deployed at:", address(MINTR));

        PRICE = new OlympusPrice(
            kernel,
            ohmEthPriceFeed,
            reserveEthPriceFeed,
            uint48(8 hours),
            uint48(30 days)
        );
        console2.log("Price module deployed at:", address(PRICE));

        RANGE = new OlympusRange(
            kernel,
            [ohm, reserve],
            [uint256(100), uint256(1000), uint256(2000)]
        );
        console2.log("Range module deployed at:", address(RANGE));

        /// Deploy policies
        callback = new BondCallback(kernel, bondAggregator, ohm);
        console2.log("Bond Callback deployed at:", address(callback));

        operator = new Operator(
            kernel,
            bondAuctioneer,
            callback,
            [ohm, reserve],
            [
                uint32(2000), // cushionFactor
                uint32(5 days), // cushionDuration
                uint32(100_000), // cushionDebtBuffer
                uint32(4 hours), // cushionDepositInterval
                uint32(1000), // reserveFactor
                uint32(1 hours), // regenWait
                uint32(18), // regenThreshold
                uint32(21) // regenObserve
            ] // TODO verify initial parameters
        );
        console2.log("Operator deployed at:", address(operator));

        heart = new Heart(kernel, operator, rewardToken, 0);
        console2.log("Heart deployed at:", address(heart));

        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        voterReg = new VoterRegistration(kernel);
        console2.log("VoterRegistration deployed at:", address(voterReg));

        governance = new Governance(kernel);
        console2.log("Governance deployed at:", address(governance));

        authGiver = new MockAuthGiver(kernel);
        console2.log("Auth Giver deployed at:", address(authGiver));

        /// Execute actions on Kernel
        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(INSTR));
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.InstallModule, address(AUTHR));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.InstallModule, address(RANGE));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));

        /// Approve policies
        kernel.executeAction(Actions.ApprovePolicy, address(callback));
        kernel.executeAction(Actions.ApprovePolicy, address(operator));
        kernel.executeAction(Actions.ApprovePolicy, address(heart));
        kernel.executeAction(Actions.ApprovePolicy, address(priceConfig));
        kernel.executeAction(Actions.ApprovePolicy, address(voterReg));
        kernel.executeAction(Actions.ApprovePolicy, address(governance));
        /// TODO likely to change with the auth system upgrades, using as a placeholder to enable auth setting on deployment
        kernel.executeAction(Actions.ApprovePolicy, address(authGiver));

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
        authGiver.setRoleCapability(
            uint8(1),
            address(heart),
            heart.resetBeat.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(heart),
            heart.toggleBeat.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(heart),
            heart.setRewardTokenAndAmount.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(heart),
            heart.withdrawUnspentRewards.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(priceConfig),
            priceConfig.initialize.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(priceConfig),
            priceConfig.changeMovingAverageDuration.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(priceConfig),
            priceConfig.changeObservationFrequency.selector
        );
        authGiver.setRoleCapability(
            uint8(1),
            address(callback),
            callback.setOperator.selector
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

        /// Role 4 = Callback
        authGiver.setRoleCapability(
            uint8(4),
            address(operator),
            operator.bondPurchase.selector
        );

        /// Give roles to users
        authGiver.setUserRole(address(heart), uint8(0));
        authGiver.setUserRole(guardian_, uint8(1));
        authGiver.setUserRole(policy_, uint8(2));
        authGiver.setUserRole(address(operator), uint8(3));
        authGiver.setUserRole(address(callback), uint8(4));

        /// Terminate mock auth giver
        kernel.executeAction(Actions.TerminatePolicy, address(authGiver));

        // /// Transfer executor powers to INSTR
        // kernel.executeAction(Actions.ChangeExecutor, address(INSTR));

        vm.stopBroadcast();
    }

    /// @dev should be called by address with the guardian role
    function initialize() external {
        // Set addresses from deployment
        // priceConfig = OlympusPriceConfig();
        operator = Operator(0x84F334bf268821C5A8DB931105088f0369288B4c);
        callback = BondCallback(0x76775f07B0dCd21DB304b6c5b14d57A2954ddAC6);

        /// Start broadcasting
        vm.startBroadcast();

        /// Initialize the Price oracle
        // DONE MANUALLY VIA ETHERSCAN DUE TO DATA INPUT LIMITATIONS
        // priceConfig.initialize(priceObservations, lastObservationTime);

        /// Set the operator address on the BondCallback contract
        callback.setOperator(operator);

        /// Initialize the Operator policy
        operator.initialize();

        // /// Deposit msg.value in WETH contract and deposit in heart
        // IWETH9(address(rewardToken)).deposit{value: msg.value}();
        // rewardToken.safeTransfer(address(heart), msg.value);

        /// Stop broadcasting
        vm.stopBroadcast();
    }
}

contract DependencyDeploy is Script {
    MockPriceFeed public ohmEthPriceFeed;
    MockPriceFeed public reserveEthPriceFeed;

    function deploy() external {
        vm.startBroadcast();

        // Deploy the price feeds
        ohmEthPriceFeed = new MockPriceFeed();
        console2.log(
            "OHM-ETH Price Feed deployed to:",
            address(ohmEthPriceFeed)
        );
        reserveEthPriceFeed = new MockPriceFeed();
        console2.log(
            "RESERVE-ETH Price Feed deployed to:",
            address(reserveEthPriceFeed)
        );

        // Set the decimals of the price feeds
        ohmEthPriceFeed.setDecimals(18);
        reserveEthPriceFeed.setDecimals(18);

        vm.stopBroadcast();
    }
}
