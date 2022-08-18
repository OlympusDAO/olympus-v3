// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
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

/// @notice Script to deploy and initialize the Olympus system on a local node for simulations.
/// @dev    Uses a constructor deploy instead of a forge script to do everything in one transaction.
contract SimDeploy {
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

    /// Goerli testnet addresses
    ERC20 public constant ohm = ERC20(0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b); // OHM goerli address
    ERC20 public constant reserve = ERC20(0x41e38e70a36150D08A8c97aEC194321b5eB545A5); // DAI goerli address
    ERC20 public constant rewardToken = ERC20(0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7); // WETH goerli address

    /// Constructor
    constructor(
        address guardian_,
        address policy_,
        DependencyDeploy dependencies_
    ) {
        // Load dependencies
        AggregatorV2V3Interface ohmEthPriceFeed = AggregatorV2V3Interface(
            dependencies_.ohmEthPriceFeed()
        );
        AggregatorV2V3Interface reserveEthPriceFeed = AggregatorV2V3Interface(
            dependencies_.reserveEthPriceFeed()
        );

        IBondAggregator bondAggregator = IBondAggregator(dependencies_.bondAggregator());
        IBondAuctioneer bondAuctioneer = IBondAuctioneer(dependencies_.bondAuctioneer());

        /// Deploy tokens TODO
        // ERC20 ohm = ERC20(address(new OlympusERC20Token(authority)));

        /// Deploy kernel first
        kernel = new Kernel(); // sender will be executor initially

        /// Deploy modules
        INSTR = new OlympusInstructions(kernel);

        VOTES = new OlympusVotes(kernel);

        TRSRY = new OlympusTreasury(kernel);

        MINTR = new OlympusMinter(kernel, address(ohm));

        PRICE = new OlympusPrice(
            kernel,
            ohmEthPriceFeed,
            reserveEthPriceFeed,
            uint48(8), // 8 hours sim time, 1 second = 1 hour
            uint48(720) // 30 days sim time, 1 second = 1 hour
        );

        /// TODO need to take inputs for configuring for each sim run
        RANGE = new OlympusRange(
            kernel,
            [ohm, reserve],
            [uint256(100), uint256(1200), uint256(3000)]
        );

        /// Deploy policies
        callback = new BondCallback(kernel, bondAggregator, ohm);

        /// TODO need to take inputs for configuring for each sim run
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
            ] // TODO change bond contracts for simulation to be able to run faster
        );

        heart = new OlympusHeart(kernel, operator, rewardToken, 0);

        priceConfig = new OlympusPriceConfig(kernel);

        voterReg = new VoterRegistration(kernel);

        governance = new OlympusGovernance(kernel);

        faucet = new Faucet(
            kernel,
            ohm,
            reserve,
            1 ether,
            1_000_000 * 1e9,
            10_000_000 * 1e18,
            1 hours
        );

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
        /// TODO can potential reduce permission setting here if not needed in simulation

        /// Operator roles
        kernel.grantRole(toRole("operator_operate"), address(heart));
        kernel.grantRole(toRole("operator_operate"), guardian_);
        kernel.grantRole(toRole("operator_reporter"), address(callback));
        kernel.grantRole(toRole("operator_policy"), policy_);
        kernel.grantRole(toRole("operator_admin"), guardian_);
        kernel.grantRole(toRole("operator_admin"), address(this));

        /// Bond callback roles
        kernel.grantRole(toRole("callback_whitelist"), address(operator));
        kernel.grantRole(toRole("callback_whitelist"), guardian_);
        kernel.grantRole(toRole("callback_admin"), guardian_);
        kernel.grantRole(toRole("callback_admin"), address(this));

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

        /// Initialize contracts
        /// Initialize the Price oracle TODO figure this out
        // DONE MANUALLY VIA ETHERSCAN DUE TO DATA INPUT LIMITATIONS
        // priceConfig.initialize(priceObservations, lastObservationTime);

        /// Set the operator address on the BondCallback contract
        callback.setOperator(operator);

        /// Initialize the Operator policy
        operator.initialize();
    }
}

contract DependencyDeploy {
    MockPriceFeed public ohmEthPriceFeed;
    MockPriceFeed public reserveEthPriceFeed;

    // TODO add bond system in here, both can be deployed once and used for a number of sims
    IBondAggregator public bondAggregator;
    IBondAuctioneer public bondAuctioneer;

    // TODO add OlympusAuthority for OHM token

    constructor() {
        // Deploy the price feeds
        ohmEthPriceFeed = new MockPriceFeed();
        reserveEthPriceFeed = new MockPriceFeed();

        // Set the decimals of the price feeds
        ohmEthPriceFeed.setDecimals(18);
        reserveEthPriceFeed.setDecimals(18);
    }
}
