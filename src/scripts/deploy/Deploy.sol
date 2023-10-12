// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondSDA} from "interfaces/IBondSDA.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {Distributor} from "policies/Distributor.sol";
import {Emergency} from "policies/Emergency.sol";
import {BondManager} from "policies/BondManager.sol";

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
    OlympusRoles public ROLES;

    /// Policies
    Operator public operator;
    OlympusHeart public heart;
    BondCallback public callback;
    OlympusPriceConfig public priceConfig;
    RolesAdmin public rolesAdmin;
    TreasuryCustodian public treasuryCustodian;
    Distributor public distributor;
    Emergency public emergency;
    BondManager public bondManager;

    /// Construction variables

    /// Token addresses
    ERC20 public ohm;
    ERC20 public reserve;
    ERC4626 public wrappedReserve;
    ERC20 public rewardToken;

    /// Bond system addresses
    IBondSDA public bondAuctioneer;
    IBondAggregator public bondAggregator;

    /// Chainlink price feed addresses
    AggregatorV2V3Interface public ohmEthPriceFeed;
    AggregatorV2V3Interface public reserveEthPriceFeed;

    /// External contracts
    address public staking;

    function deploy(
        string memory chain_,
        address guardian_,
        address policy_,
        address emergency_
    ) external {
        /// Token addresses
        ohm = ERC20(vm.envAddress("OHM_ADDRESS"));
        reserve = ERC20(vm.envAddress("DAI_ADDRESS"));
        wrappedReserve = ERC4626(vm.envAddress("SDAI_ADDRESS"));
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
            uint48(30 days),
            10 * 1e18 // TODO placeholder for liquid backing
        );
        console2.log("Price module deployed at:", address(PRICE));

        RANGE = new OlympusRange(
            kernel,
            ohm,
            reserve,
            uint256(100),
            [uint256(1675), uint256(2950)],
            [uint256(1675), uint256(2950)]
        );
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
            [address(ohm), address(reserve), address(wrappedReserve)],
            [
                uint32(3075), // cushionFactor
                uint32(3 days), // cushionDuration
                uint32(100_000), // cushionDebtBuffer
                uint32(4 hours), // cushionDepositInterval
                uint32(950), // reserveFactor
                uint32(6 days), // regenWait
                uint32(18), // regenThreshold
                uint32(21) // regenObserve
            ]
        );
        console2.log("Operator deployed at:", address(operator));

        heart = new OlympusHeart(kernel, operator, 10 * 1e9, uint48(12 * 25)); // TODO verify initial keeper reward and auction duration
        console2.log("Heart deployed at:", address(heart));

        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        treasuryCustodian = new TreasuryCustodian(kernel);
        console2.log("TreasuryCustodian deployed at:", address(treasuryCustodian));

        distributor = new Distributor(kernel, address(ohm), staking, vm.envUint("REWARD_RATE"));
        console2.log("Distributor deployed at:", address(distributor));

        emergency = new Emergency(kernel);
        console2.log("Emergency deployed at:", address(emergency));

        /// Execute actions on Kernel
        /// Install modules
        // kernel.executeAction(Actions.InstallModule, address(INSTR));
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
        kernel.executeAction(Actions.ActivatePolicy, address(emergency));

        /// Configure access control for policies

        /// Operator roles
        rolesAdmin.grantRole("operator_operate", address(heart));
        rolesAdmin.grantRole("operator_operate", guardian_);
        rolesAdmin.grantRole("operator_reporter", address(callback));
        rolesAdmin.grantRole("operator_policy", policy_);
        rolesAdmin.grantRole("operator_admin", guardian_);

        /// Bond callback roles
        rolesAdmin.grantRole("callback_whitelist", address(operator));
        rolesAdmin.grantRole("callback_whitelist", policy_);
        rolesAdmin.grantRole("callback_admin", guardian_);

        /// Heart roles
        rolesAdmin.grantRole("heart_admin", policy_);

        /// PriceConfig roles
        rolesAdmin.grantRole("price_admin", guardian_);
        rolesAdmin.grantRole("price_admin", policy_);

        /// TreasuryCustodian roles
        rolesAdmin.grantRole("custodian", guardian_);

        /// Distributor roles
        rolesAdmin.grantRole("distributor_admin", policy_);

        /// Emergency roles
        rolesAdmin.grantRole("emergency_shutdown", emergency_);
        rolesAdmin.grantRole("emergency_restart", guardian_);

        vm.stopBroadcast();

        // Save deployment information for the chain being deployed to
        _saveDeployment(chain_);
    }

    /// @dev should be called by address with the guardian role
    function initializeOperator() external {
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

    /// @dev Verifies that the environment variable addresses were set correctly following deployment
    /// @dev Should be called prior to verifyAndPushAuth()
    function verifyKernelInstallation() external {
        kernel = Kernel(vm.envAddress("KERNEL"));

        /// Modules
        PRICE = OlympusPrice(vm.envAddress("PRICE"));
        RANGE = OlympusRange(vm.envAddress("RANGE"));
        TRSRY = OlympusTreasury(vm.envAddress("TRSRY"));
        MINTR = OlympusMinter(vm.envAddress("MINTR"));
        ROLES = OlympusRoles(vm.envAddress("ROLES"));

        /// Policies
        operator = Operator(vm.envAddress("OPERATOR"));
        heart = OlympusHeart(vm.envAddress("HEART"));
        callback = BondCallback(vm.envAddress("CALLBACK"));
        priceConfig = OlympusPriceConfig(vm.envAddress("PRICECONFIG"));
        rolesAdmin = RolesAdmin(vm.envAddress("ROLESADMIN"));
        treasuryCustodian = TreasuryCustodian(vm.envAddress("TRSRYCUSTODIAN"));
        distributor = Distributor(vm.envAddress("DISTRIBUTOR"));
        emergency = Emergency(vm.envAddress("EMERGENCY"));
        bondManager = BondManager(vm.envAddress("BONDMANAGER"));

        /// Check that Modules are installed
        /// PRICE
        Module priceModule = kernel.getModuleForKeycode(toKeycode("PRICE"));
        Keycode priceKeycode = kernel.getKeycodeForModule(PRICE);
        require(priceModule == PRICE);
        require(fromKeycode(priceKeycode) == "PRICE");

        /// RANGE
        Module rangeModule = kernel.getModuleForKeycode(toKeycode("RANGE"));
        Keycode rangeKeycode = kernel.getKeycodeForModule(RANGE);
        require(rangeModule == RANGE);
        require(fromKeycode(rangeKeycode) == "RANGE");

        /// TRSRY
        Module trsryModule = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        Keycode trsryKeycode = kernel.getKeycodeForModule(TRSRY);
        require(trsryModule == TRSRY);
        require(fromKeycode(trsryKeycode) == "TRSRY");

        /// MINTR
        Module mintrModule = kernel.getModuleForKeycode(toKeycode("MINTR"));
        Keycode mintrKeycode = kernel.getKeycodeForModule(MINTR);
        require(mintrModule == MINTR);
        require(fromKeycode(mintrKeycode) == "MINTR");

        /// ROLES
        Module rolesModule = kernel.getModuleForKeycode(toKeycode("ROLES"));
        Keycode rolesKeycode = kernel.getKeycodeForModule(ROLES);
        require(rolesModule == ROLES);
        require(fromKeycode(rolesKeycode) == "ROLES");

        /// Policies
        require(kernel.isPolicyActive(operator));
        require(kernel.isPolicyActive(heart));
        require(kernel.isPolicyActive(callback));
        require(kernel.isPolicyActive(priceConfig));
        require(kernel.isPolicyActive(rolesAdmin));
        require(kernel.isPolicyActive(treasuryCustodian));
        require(kernel.isPolicyActive(distributor));
        require(kernel.isPolicyActive(emergency));
        require(kernel.isPolicyActive(bondManager));
    }

    /// @dev Should be called by the deployer address after deployment
    function verifyAndPushAuth(address guardian_, address policy_, address emergency_) external {
        ROLES = OlympusRoles(vm.envAddress("ROLES"));
        heart = OlympusHeart(vm.envAddress("HEART"));
        callback = BondCallback(vm.envAddress("CALLBACK"));
        operator = Operator(vm.envAddress("OPERATOR"));
        rolesAdmin = RolesAdmin(vm.envAddress("ROLESADMIN"));
        kernel = Kernel(vm.envAddress("KERNEL"));

        /// Operator Roles
        require(ROLES.hasRole(address(heart), "operator_operate"));
        require(ROLES.hasRole(guardian_, "operator_operate"));
        require(ROLES.hasRole(address(callback), "operator_reporter"));
        require(ROLES.hasRole(policy_, "operator_policy"));
        require(ROLES.hasRole(guardian_, "operator_admin"));

        /// Callback Roles
        require(ROLES.hasRole(address(operator), "callback_whitelist"));
        require(ROLES.hasRole(policy_, "callback_whitelist"));
        require(ROLES.hasRole(guardian_, "callback_admin"));

        /// Heart Roles
        require(ROLES.hasRole(policy_, "heart_admin"));

        /// PriceConfig Roles
        require(ROLES.hasRole(guardian_, "price_admin"));
        require(ROLES.hasRole(policy_, "price_admin"));

        /// TreasuryCustodian Roles
        require(ROLES.hasRole(guardian_, "custodian"));

        /// Distributor Roles
        require(ROLES.hasRole(policy_, "distributor_admin"));

        /// Emergency Roles
        require(ROLES.hasRole(emergency_, "emergency_shutdown"));
        require(ROLES.hasRole(guardian_, "emergency_restart"));

        /// BondManager Roles
        require(ROLES.hasRole(policy_, "bondmanager_admin"));

        /// Push rolesAdmin and Executor
        vm.startBroadcast();
        rolesAdmin.pushNewAdmin(guardian_);
        kernel.executeAction(Actions.ChangeExecutor, guardian_);
        vm.stopBroadcast();
    }

    function _saveDeployment(string memory chain_) internal {
        // Create file path
        string memory file = string.concat(
            "./deployments/",
            chain_,
            "-",
            vm.toString(block.timestamp),
            ".json"
        );

        // Write deployment info to file in JSON format
        vm.writeLine(file, "{");
        vm.writeLine(
            file,
            string.concat('"', type(Kernel).name, '": "', vm.toString(address(kernel)), '",')
        );
        vm.writeLine(
            file,
            string.concat('"', type(OlympusPrice).name, '": "', vm.toString(address(PRICE)), '",')
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(OlympusTreasury).name,
                '": "',
                vm.toString(address(TRSRY)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat('"', type(OlympusMinter).name, '": "', vm.toString(address(MINTR)), '",')
        );
        vm.writeLine(
            file,
            string.concat('"', type(OlympusRange).name, '": "', vm.toString(address(RANGE)), '",')
        );
        vm.writeLine(
            file,
            string.concat('"', type(OlympusRoles).name, '": "', vm.toString(address(ROLES)), '",')
        );
        vm.writeLine(
            file,
            string.concat('"', type(Operator).name, '": "', vm.toString(address(operator)), '",')
        );
        vm.writeLine(
            file,
            string.concat('"', type(OlympusHeart).name, '": "', vm.toString(address(heart)), '",')
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(BondCallback).name,
                '": "',
                vm.toString(address(callback)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(OlympusPriceConfig).name,
                '": "',
                vm.toString(address(priceConfig)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(RolesAdmin).name,
                '": "',
                vm.toString(address(rolesAdmin)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(TreasuryCustodian).name,
                '": "',
                vm.toString(address(treasuryCustodian)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat(
                '"',
                type(Distributor).name,
                '": "',
                vm.toString(address(distributor)),
                '",'
            )
        );
        vm.writeLine(
            file,
            string.concat('"', type(Emergency).name, '": "', vm.toString(address(emergency)), '",')
        );
        vm.writeLine(file, "}");
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
