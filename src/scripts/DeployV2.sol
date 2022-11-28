// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
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
import {Emergency} from "policies/Emergency.sol";

import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {Faucet} from "test/mocks/Faucet.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy and initialize the Olympus system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OlympusDeploy is Script {
    using stdJson for string;
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
    Emergency public emergency;

    /// Construction variables

    /// Token addresses
    ERC20 public ohm;
    ERC20 public reserve;

    /// Bond system addresses
    IBondSDA public bondAuctioneer;
    IBondAggregator public bondAggregator;

    /// Chainlink price feed addresses
    AggregatorV2V3Interface public ohmEthPriceFeed;
    AggregatorV2V3Interface public reserveEthPriceFeed;

    /// External contracts
    address public staking;

    // Deploy system storage
    mapping(string => bytes4) public selectorMap;
    mapping(string => bytes) public argsMap;
    string[] public deployments;
    mapping(string => address) public deployedTo;

    function _setUp(string calldata chain_) internal {
        // Setup contract -> selector mappings
        selectorMap["OlympusPrice"] = this._deployPrice.selector;
        selectorMap["OlympusRange"] = this._deployRange.selector;
        selectorMap["OlympusTreasury"] = this._deployTreasury.selector;
        selectorMap["OlympusMinter"] = this._deployMinter.selector;
        selectorMap["OlympusRoles"] = this._deployRoles.selector;
        selectorMap["Operator"] = this._deployOperator.selector;
        selectorMap["OlympusHeart"] = this._deployHeart.selector;
        selectorMap["BondCallback"] = this._deployBondCallback.selector;
        selectorMap["OlympusPriceConfig"] = this._deployPriceConfig.selector;
        selectorMap["RolesAdmin"] = this._deployRolesAdmin.selector;
        selectorMap["TreasuryCustodian"] = this._deployTreasuryCustodian.selector;
        selectorMap["Distributor"] = this._deployDistributor.selector;
        selectorMap["Emergency"] = this._deployEmergency.selector;

        // Load environment addresses
        string memory env = vm.readFile("./src/scripts/env.json");

        // Non-bophades contracts
        ohm = ERC20(env.readAddress(string.concat(chain_, ".olympus.legacy.OHM")));
        reserve = ERC20(env.readAddress(string.concat(chain_, ".external.tokens.DAI")));
        bondAuctioneer = IBondSDA(env.readAddress(string.concat(chain_, ".external.bond-protocol.BondFixedTermAuctioneer")));
        bondAggregator = IBondAggregator(env.readAddress(string.concat(chain_, ".external.bond-protocol.BondAggregator")));
        ohmEthPriceFeed = AggregatorV2V3Interface(env.readAddress(string.concat(chain_, ".external.chainlink.ohmEthPriceFeed")));
        reserveEthPriceFeed = AggregatorV2V3Interface(env.readAddress(string.concat(chain_, ".external.chainlink.daiEthPriceFeed")));
        staking = env.readAddress(string.concat(chain_, ".olympus.legacy.Staking"));

        // Bophades contracts
        kernel = Kernel(env.readAddress(string.concat(chain_, ".olympus.Kernel")));
        PRICE = OlympusPrice(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusPrice")));
        RANGE = OlympusRange(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusRange")));
        TRSRY = OlympusTreasury(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusTreasury")));
        MINTR = OlympusMinter(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusMinter")));
        INSTR = OlympusInstructions(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusInstructions")));
        ROLES = OlympusRoles(env.readAddress(string.concat(chain_, ".olympus.modules.OlympusRoles")));
        operator = Operator(env.readAddress(string.concat(chain_, ".olympus.policies.Operator")));
        heart = OlympusHeart(env.readAddress(string.concat(chain_, ".olympus.policies.OlympusHeart")));
        callback = BondCallback(env.readAddress(string.concat(chain_, ".olympus.policies.BondCallback")));
        priceConfig = OlympusPriceConfig(env.readAddress(string.concat(chain_, ".olympus.policies.OlympusPriceConfig")));
        rolesAdmin = RolesAdmin(env.readAddress(string.concat(chain_, ".olympus.policies.RolesAdmin")));
        treasuryCustodian = TreasuryCustodian(env.readAddress(string.concat(chain_, ".olympus.policies.TreasuryCustodian")));
        distributor = Distributor(env.readAddress(string.concat(chain_, ".olympus.policies.Distributor")));
        emergency = Emergency(env.readAddress(string.concat(chain_, ".olympus.policies.Emergency")));

        // Load deployment data
        string memory data = vm.readFile("./src/scripts/deploy.json");

        // Have to use a hack with jq to get the length of the deployment sequence since the json lib used by forge doesn't have a length operation
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = 'jq -c ".sequence | length" ./src/scripts/deploy.json | cast --to-uint256';
        uint256 len = abi.decode(vm.ffi(inputs), (uint256));

        // Forge doesn't correctly parse a string[] from a json array so we have to do it manually
        string[] memory names = abi.decode(bytes.concat(bytes32(uint256(32)),bytes32(len),data.parseRaw("sequence..name")),(string[]));

        // Iterate through deployment sequence and set deployment args
        for (uint256 i = 0; i < len; i++) {
            string memory name = names[i];
            deployments.push(name);

            // Parse and store args if not kernel
            if (keccak256(bytes(name)) != keccak256(bytes("Kernel"))) {
                argsMap[name] = data.parseRaw(string.concat("sequence[?(@.name == '",name,"')].args.[*]"));
            }
           
        }

    }

    /// @dev Installs, upgrades, activations, and deactivations as well as access control settings must be done via olymsig batches since DAO MS is multisig executor on mainnet
    /// @dev If we can get multisig batch functionality in foundry, then we can add to these scripts
    // function _installModule(Module module_) internal {
    //     // Check if module is installed on the kernel and determine which type of install to use
    //     vm.startBroadcast();
    //     if (address(kernel.getModuleForKeycode(module_.KEYCODE())) != address(0)) {
    //         kernel.executeAction(Actions.UpgradeModule, address(module_));
    //     } else {
    //         kernel.executeAction(Actions.InstallModule, address(module_));
    //     }
    //     vm.stopBroadcast();
    // }

    // function _activatePolicy(Policy policy_) internal {
    //     // Check if policy is activated on the kernel and determine which type of activation to use
    //     vm.broadcast();
    //     kernel.executeAction(Actions.ActivatePolicy, address(policy_));
    // }

    function deploy(string calldata chain_, address guardian_, address policy_, address emergency_) external {
        // Setup
        _setUp(chain_);

        // Check that deployments is not empty
        uint256 len = deployments.length;
        require(len > 0, "No deployments");

        // If kernel to be deployed, then it should be first (not included in contract -> selector mappings so it will error out if not first)
        bool deployKernel = keccak256(bytes(deployments[0])) == keccak256(bytes("Kernel"));
        if (deployKernel) {
            vm.broadcast();
            kernel = new Kernel();
            console2.log("Kernel deployed at:", address(kernel));
        }

        // Iterate through deployments
        for (uint256 i = deployKernel ? 1 : 0; i < len; i++) {
            // Get deploy script selector and deploy args from contract name
            string memory name = deployments[i];
            bytes4 selector = selectorMap[name];
            bytes memory args = argsMap[name];

            // Call the deploy function for the contract
            (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(selector, args));
            require(success, string.concat("Failed to deploy ", deployments[i]));

            // Store the deployed contract address for logging
            deployedTo[name] = abi.decode(data, (address));
        }

        // Save deployments to file
        _saveDeployment(chain_);
    }

    // ========== DEPLOYMENT FUNCTIONS ========== //

    // Module deployment functions
    function _deployPrice(bytes memory args) public returns (address) {
        // Decode arguments for Price module
        (
            uint48 ohmEthUpdateThreshold_,
            uint48 reserveEthUpdateThreshold_,
            uint48 observationFrequency_,
            uint48 movingAverageDuration_,
            uint256 minimumTargetPrice_
        ) = abi.decode(args, (uint48, uint48, uint48, uint48, uint256));

        // Deploy Price module
        vm.broadcast();
        PRICE = new OlympusPrice(
            kernel,
            ohmEthPriceFeed,
            ohmEthUpdateThreshold_,
            reserveEthPriceFeed,
            reserveEthUpdateThreshold_,
            observationFrequency_,
            movingAverageDuration_,
            minimumTargetPrice_
        );
        console2.log("Price deployed at:", address(PRICE));

        return address(PRICE);
    }

    function _deployRange(bytes memory args) public returns (address) {
        // Decode arguments for Range module
        (
            uint256 thresholdFactor,
            uint256 cushionSpread,
            uint256 wallSpread
        ) = abi.decode(args, (uint256, uint256, uint256));

        // Deploy Range module
        vm.broadcast();
        RANGE = new OlympusRange(kernel, ohm, reserve, thresholdFactor, cushionSpread, wallSpread);
        console2.log("Range deployed at:", address(RANGE));

        return address(RANGE);
    }

    function _deployTreasury(bytes memory args) public returns (address) {
        // No additional arguments for Treasury module

        // Deploy Treasury module
        vm.broadcast();
        TRSRY = new OlympusTreasury(kernel);
        console2.log("Treasury deployed at:", address(TRSRY));

        return address(TRSRY);
    }

    function _deployMinter(bytes memory args) public returns (address) {
        // Only args are contracts in the environment

        // Deploy Minter module
        vm.broadcast();
        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("Minter deployed at:", address(MINTR));

        return address(MINTR);
    }

    function _deployRoles(bytes memory args) public returns (address) {
        // No additional arguments for Roles module

        // Deploy Roles module
        vm.broadcast();
        ROLES = new OlympusRoles(kernel);
        console2.log("Roles deployed at:", address(ROLES));

        return address(ROLES);
    }

    // Policy deployment functions
    function _deployOperator(bytes memory args) public returns (address) {
        // Decode arguments for Operator policy
        // Must use a dynamic array to parse correctly since the json lib defaults to this
        uint32[] memory configParams_ = abi.decode(args, (uint32[]));
        uint32[8] memory configParams = [
            configParams_[0],
            configParams_[1],
            configParams_[2],
            configParams_[3],
            configParams_[4],
            configParams_[5],
            configParams_[6],
            configParams_[7]
        ];

        // Deploy Operator policy
        vm.broadcast();
        operator = new Operator(
            kernel,
            bondAuctioneer,
            callback,
            [ohm, reserve],
            configParams
        );
        console2.log("Operator deployed at:", address(operator));

        return address(operator);
    }

    function _deployBondCallback(bytes memory args) public returns (address) {
        // No additional arguments for BondCallback policy

        // Deploy BondCallback policy
        vm.broadcast();
        callback = new BondCallback(kernel, bondAggregator, ohm);
        console2.log("BondCallback deployed at:", address(callback));

        return address(callback);
    }

    function _deployHeart(bytes memory args) public returns (address) {
        // Decode arguments for OlympusHeart policy
        uint256 reward = abi.decode(args, (uint256));

        // Deploy OlympusHeart policy
        vm.broadcast();
        heart = new OlympusHeart(kernel, operator, ohm, reward);
        console2.log("OlympusHeart deployed at:", address(heart));

        return address(heart);
    }

    function _deployPriceConfig(bytes memory args) public returns (address) {
        // No additional arguments for PriceConfig policy

        // Deploy PriceConfig policy
        vm.broadcast();
        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        return address(priceConfig);
    }

    function _deployRolesAdmin(bytes memory args) public returns (address) {
        // No additional arguments for RolesAdmin policy

        // Deploy RolesAdmin policy
        vm.broadcast();
        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        return address(rolesAdmin);
    }

    function _deployTreasuryCustodian(bytes memory args) public returns (address) {
        // No additional arguments for TreasuryCustodian policy

        // Deploy TreasuryCustodian policy
        vm.broadcast();
        treasuryCustodian = new TreasuryCustodian(kernel);
        console2.log("TreasuryCustodian deployed at:", address(treasuryCustodian));

        return address(treasuryCustodian);
    }

    function _deployDistributor(bytes memory args) public returns (address) {
        // Decode arguments for Distributor policy
        uint256 initialRate = abi.decode(args, (uint256));

        // Deploy Distributor policy
        vm.broadcast();
        distributor = new Distributor(kernel, address(ohm), staking, initialRate);
        console2.log("Distributor deployed at:", address(distributor));

        return address(distributor);
    }

    function _deployEmergency(bytes memory args) public returns (address) {
        // No additional arguments for Emergency policy

        // Deploy Emergency policy
        vm.broadcast();
        emergency = new Emergency(kernel);
        console2.log("Emergency deployed at:", address(emergency));

        return address(emergency);
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


        /// Push rolesAdmin and Executor
        vm.startBroadcast();
        rolesAdmin.pushNewAdmin(guardian_);
        kernel.executeAction(Actions.ChangeExecutor, guardian_);
        vm.stopBroadcast();
    }

    function _saveDeployment(string memory chain_) internal {
        // Create file path
        string memory file = string.concat("./deployments/", chain_, "-", vm.toString(block.timestamp), ".json");

        // Write deployment info to file in JSON format
        vm.writeLine(file, "{");
        
        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployments.length;
        for (uint256 i; i < len; ++i) {
            vm.writeLine(
                file,
                string.concat('"', deployments[i], '": "', vm.toString(deployedTo[deployments[i]]), '",')
            );
        }
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
