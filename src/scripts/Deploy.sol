// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondSDA} from "interfaces/IBondSDA.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {Distributor} from "policies/Distributor.sol";

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
    OlympusRoles public ROLES;

    /// Policies
    Operator public operator;
    OlympusHeart public heart;
    BondCallback public callback;
    OlympusPriceConfig public priceConfig;
    RolesAdmin public rolesAdmin;
    TreasuryCustodian public treasuryCustodian;
    Distributor public distributor;

    /// Construction variables

    /// Token addresses
    ERC20 public ohm;
    ERC20 public reserve;
    ERC20 public rewardToken;

    /// Bond system addresses
    IBondSDA public bondAuctioneer;
    IBondAggregator public bondAggregator;

    /// Chainlink price feed addresses
    AggregatorV2V3Interface public ohmEthPriceFeed;
    AggregatorV2V3Interface public reserveEthPriceFeed;

    /// External contracts
    address public staking;

    function deploy(address guardian_, address policy_) external {
        /// Token addresses
        ohm = ERC20(vm.envAddress("OHM_ADDRESS"));
        reserve = ERC20(vm.envAddress("DAI_ADDRESS"));
        rewardToken = ERC20(vm.envAddress("OHM_ADDRESS"));

        /// Bond system addresses
        bondAuctioneer = IBondSDA(vm.envAddress("BOND_SDA_ADDRESS"));
        bondAggregator = IBondAggregator(vm.envAddress("BOND_AGGREGATOR_ADDRESS"));

        /// Chainlink price feed addresses
        ohmEthPriceFeed = AggregatorV2V3Interface(vm.envAddress("OHM_ETH_FEED"));
        reserveEthPriceFeed = AggregatorV2V3Interface(vm.envAddress("DAI_ETH_FEED"));

        /// External Olympus contract addresses
        staking = vm.envAddress("STAKING_ADDRESS");

        vm.startBroadcast();

        /// Deploy kernel first
        kernel = new Kernel(); // sender will be executor initially
        console2.log("Kernel deployed at:", address(kernel));

        /// Deploy modules
        INSTR = new OlympusInstructions(kernel);
        console2.log("Instructions module deployed at:", address(INSTR));

        TRSRY = new OlympusTreasury(kernel);
        console2.log("Treasury module deployed at:", address(TRSRY));

        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("Minter module deployed at:", address(MINTR));

        PRICE = new OlympusPrice(
            kernel,
            ohmEthPriceFeed,
            uint48(24 hours),
            reserveEthPriceFeed,
            uint48(24 hours),
            uint48(8 hours),
            uint48(30 days)
        );
        console2.log("Price module deployed at:", address(PRICE));

        RANGE = new OlympusRange(kernel, ohm, reserve, uint256(100), uint256(1500), uint256(2800));
        console2.log("Range module deployed at:", address(RANGE));

        ROLES = new OlympusRoles(kernel);
        console2.log("Roles module deployed at:", address(ROLES));

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
                uint32(4 hours), // cushionDepositInterval
                uint32(1000), // reserveFactor
                uint32(6 days), // regenWait
                uint32(18), // regenThreshold // 18
                uint32(21) // regenObserve    // 21
            ] // TODO verify initial parameters
        );
        console2.log("Operator deployed at:", address(operator));

        heart = new OlympusHeart(kernel, operator, rewardToken, 5 * 1e9); // TODO verify initial keeper reward
        console2.log("Heart deployed at:", address(heart));

        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        treasuryCustodian = new TreasuryCustodian(kernel);
        console2.log("TreasuryCustodian deployed at:", address(treasuryCustodian));

        distributor = new Distributor(kernel, address(ohm), staking, vm.envUint("REWARD_RATE")); // TODO verify reward rate
        console2.log("Distributor deployed at:", address(distributor));

        /// Execute actions on Kernel
        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(INSTR));
        kernel.executeAction(Actions.InstallModule, address(PRICE));
        kernel.executeAction(Actions.InstallModule, address(RANGE));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(callback));
        kernel.executeAction(Actions.ActivatePolicy, address(operator));
        kernel.executeAction(Actions.ActivatePolicy, address(heart));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryCustodian));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));

        /// Configure access control for policies

        /// Operator roles
        rolesAdmin.grantRole("operator_operate", address(heart));
        rolesAdmin.grantRole("operator_operate", guardian_);
        rolesAdmin.grantRole("operator_reporter", address(callback));
        rolesAdmin.grantRole("operator_policy", policy_);
        rolesAdmin.grantRole("operator_admin", guardian_);

        /// Bond callback roles
        rolesAdmin.grantRole("callback_whitelist", address(operator));
        rolesAdmin.grantRole("callback_whitelist", guardian_);
        rolesAdmin.grantRole("callback_admin", guardian_);

        /// Heart roles
        rolesAdmin.grantRole("heart_admin", policy_);

        /// PriceConfig roles
        rolesAdmin.grantRole("price_admin", guardian_);

        /// TreasuryCustodian roles
        rolesAdmin.grantRole("custodian", guardian_);

        /// Distributor roles
        rolesAdmin.grantRole("distributor_admin", policy_);

        // /// Transfer executor powers to INSTR
        // kernel.executeAction(Actions.ChangeExecutor, address(INSTR));

        vm.stopBroadcast();
    }

    /// @dev should be called by address with the guardian role
    function initialize() external {
        // Set addresses from deployment
        // priceConfig = OlympusPriceConfig();
        operator = Operator(vm.envAddress("OPERATOR"));
        callback = BondCallback(vm.envAddress("CALLBACK"));

        /// Start broadcasting
        vm.startBroadcast();

        /// Initialize the Price oracle
        // DONE MANUALLY VIA ETHERSCAN DUE TO DATA INPUT LIMITATIONS
        // priceConfig.initialize(priceObservations, lastObservationTime);

        /// Set the operator address on the BondCallback contract
        callback.setOperator(operator);

        /// Initialize the Operator policy
        operator.initialize();

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
