// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondAuctioneer} from "interfaces/IBondAuctioneer.sol";
import {IWETH9} from "interfaces/IWETH9.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE.sol";
import {OlympusRange} from "modules/RANGE.sol";
import {OlympusTreasury} from "modules/TRSRY.sol";
import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusInstructions} from "modules/INSTR.sol";
import {OlympusVotes} from "modules/VOTES.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {VoterRegistration} from "policies/VoterRegistration.sol";
import {OlympusGovernance} from "policies/Governance.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {Faucet} from "test/mocks/Faucet.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy and initialize the Olympus system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OlympusDeploy is Script {
    using TransferHelper for ERC20;
    Kernel public kernel;

    /// Modules
    OlympusPrice public PRICE;
    OlympusRange public RANGE;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    OlympusInstructions public INSTR;
    OlympusVotes public VOTES;

    /// Policies
    Operator public operator;
    OlympusHeart public heart;
    BondCallback public callback;
    OlympusPriceConfig public priceConfig;
    VoterRegistration public voterReg;
    OlympusGovernance public governance;
    Faucet public faucet;

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
    ERC20 public constant ohm = ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve = ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken = ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    /// Bond system addresses
    IBondAuctioneer public constant bondAuctioneer =
        IBondAuctioneer(0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b);
    IBondAggregator public constant bondAggregator =
        IBondAggregator(0xB4860B2c12C6B894B64471dFb5a631ff569e220e);

    /// Mock Price Feed addresses
    AggregatorV2V3Interface public constant ohmEthPriceFeed =
        AggregatorV2V3Interface(0x022710a589C9796dce59A0C52cA4E36f0a5e991A); // OHM/ETH
    AggregatorV2V3Interface public constant reserveEthPriceFeed =
        AggregatorV2V3Interface(0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233); // DAI/ETH

    function deploy(address guardian_, address policy_) external {
        vm.startBroadcast();

        /// Deploy kernel first
        kernel = new Kernel(); // sender will be executor initially
        console2.log("Kernel deployed at:", address(kernel));

        /// Deploy modules
        INSTR = new OlympusInstructions(kernel);
        console2.log("Instructions module deployed at:", address(INSTR));

        VOTES = new OlympusVotes(kernel);
        console2.log("Votes module deployed at:", address(VOTES));

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
            [uint256(100), uint256(1200), uint256(3000)]
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
                uint32(3000), // cushionFactor
                uint32(3 days), // cushionDuration
                uint32(100_000), // cushionDebtBuffer
                uint32(1 hours), // cushionDepositInterval
                uint32(800), // reserveFactor
                uint32(1 hours), // regenWait
                uint32(5), // regenThreshold // 18
                uint32(7) // regenObserve    // 21
            ] // TODO verify initial parameters
        );
        console2.log("Operator deployed at:", address(operator));

        heart = new OlympusHeart(kernel, operator, rewardToken, 0);
        console2.log("Heart deployed at:", address(heart));

        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        voterReg = new VoterRegistration(kernel);
        console2.log("VoterRegistration deployed at:", address(voterReg));

        governance = new OlympusGovernance(kernel);
        console2.log("Governance deployed at:", address(governance));

        faucet = new Faucet(
            kernel,
            ohm,
            reserve,
            1 ether,
            1_000_000 * 1e9,
            10_000_000 * 1e18,
            1 hours
        );
        console2.log("Faucet deployed at:", address(faucet));

        /// Execute actions on Kernel
        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(INSTR));
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.InstallModule, address(RANGE));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(callback));
        kernel.executeAction(Actions.ActivatePolicy, address(operator));
        kernel.executeAction(Actions.ActivatePolicy, address(heart));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(voterReg));
        kernel.executeAction(Actions.ActivatePolicy, address(governance));
        kernel.executeAction(Actions.ActivatePolicy, address(faucet));

        /// Configure access control for policies

        /// Operator roles
        kernel.grantRole(toRole("operator_operate"), address(heart));
        kernel.grantRole(toRole("operator_operate"), guardian_);
        kernel.grantRole(toRole("operator_reporter"), address(callback));
        kernel.grantRole(toRole("operator_policy"), policy_);
        kernel.grantRole(toRole("operator_admin"), guardian_);

        /// Bond callback roles
        kernel.grantRole(toRole("callback_whitelist"), address(operator));
        kernel.grantRole(toRole("callback_whitelist"), guardian_);
        kernel.grantRole(toRole("callback_admin"), guardian_);

        /// Heart roles
        kernel.grantRole(toRole("heart_admin"), guardian_);

        /// VoterRegistration roles
        kernel.grantRole(toRole("voter_admin"), guardian_);

        /// PriceConfig roles
        kernel.grantRole(toRole("price_admin"), guardian_);

        /// TreasuryCustodian roles
        kernel.grantRole(toRole("custodian"), guardian_);

        /// Faucet roles
        kernel.grantRole(toRole("faucet_admin"), guardian_);

        // /// Transfer executor powers to INSTR
        // kernel.executeAction(Actions.ChangeExecutor, address(INSTR));

        vm.stopBroadcast();
    }

    /// @dev should be called by address with the guardian role
    function initialize() external {
        // Set addresses from deployment
        // priceConfig = OlympusPriceConfig();
        operator = Operator(0x532AC8804b233846645C1Cd53D3005604F5eC1c3);
        callback = BondCallback(0xdff3e45D4BE6B354384D770Fd63DDF90eA788d13);

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
        console2.log("OHM-ETH Price Feed deployed to:", address(ohmEthPriceFeed));
        reserveEthPriceFeed = new MockPriceFeed();
        console2.log("RESERVE-ETH Price Feed deployed to:", address(reserveEthPriceFeed));

        // Set the decimals of the price feeds
        ohmEthPriceFeed.setDecimals(18);
        reserveEthPriceFeed.setDecimals(18);

        vm.stopBroadcast();
    }
}
