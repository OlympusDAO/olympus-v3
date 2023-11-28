// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

// Bond Protocol
import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondTeller} from "interfaces/IBondTeller.sol";

// Balancer
import {IVault, IBasePool, IBalancerHelper} from "policies/BoostedLiquidity/interfaces/IBalancer.sol";
import {IVault as IBalancerVault} from "src/libraries/Balancer/interfaces/IVault.sol";

// Aura
import {IAuraBooster, IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";

// Bophades
import "src/Kernel.sol";

// Bophades Policies
import {Operator} from "policies/RBS/Operator.sol";
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {OlympusPriceConfig} from "policies/RBS/PriceConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {Distributor} from "policies/Distributor/Distributor.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";
import {Emergency} from "policies/Emergency.sol";
import {BondManager} from "policies/Bonds/BondManager.sol";
import {Burner} from "policies/OHM/Burner.sol";
import {BLVaultManagerLido} from "policies/BoostedLiquidity/BLVaultManagerLido.sol";
import {BLVaultLido} from "policies/BoostedLiquidity/BLVaultLido.sol";
import {BLVaultManagerLusd} from "policies/BoostedLiquidity/BLVaultManagerLusd.sol";
import {BLVaultLusd} from "policies/BoostedLiquidity/BLVaultLusd.sol";
import {IBLVaultManagerLido} from "policies/BoostedLiquidity/interfaces/IBLVaultManagerLido.sol";
import {Bookkeeper} from "policies/OCA/Bookkeeper.sol";
import {IBLVaultManager} from "policies/BoostedLiquidity/interfaces/IBLVaultManager.sol";
import {CrossChainBridge} from "policies/CrossChainBridge.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {Appraiser} from "policies/OCA/Appraiser.sol";

// Bophades Modules
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";

// PRICE Submodules
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {BalancerPoolTokenPrice} from "modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {UniswapV2PoolTokenPrice} from "modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";

// SPPLY Submodules
import {AuraBalancerSupply} from "modules/SPPLY/submodules/AuraBalancerSupply.sol";
import {BLVaultSupply} from "modules/SPPLY/submodules/BLVaultSupply.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";
import {MigrationOffsetSupply} from "modules/SPPLY/submodules/MigrationOffsetSupply.sol";

// External contracts
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// Mocks
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockAuraBooster, MockAuraRewardPool, MockAuraMiningLib, MockAuraVirtualRewardPool, MockAuraStashToken} from "test/mocks/AuraMocks.sol";
import {MockBalancerPool, MockVault} from "test/mocks/BalancerMocks.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Faucet} from "test/mocks/Faucet.sol";

// Libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy and initialize the Olympus system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OlympusDeploy is Script {
    using stdJson for string;
    using TransferHelper for ERC20;
    Kernel public kernel;

    // Modules
    OlympusPrice public PRICE;
    OlympusPricev2 public PRICEv2;
    OlympusRange public RANGE;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    OlympusInstructions public INSTR;
    OlympusRoles public ROLES;
    OlympusBoostedLiquidityRegistry public BLREG;
    OlympusSupply public SPPLY;

    // PRICEv2 Submodules
    SimplePriceFeedStrategy public simplePriceFeedStrategy;
    BalancerPoolTokenPrice public balancerPoolTokenPrice;
    ChainlinkPriceFeeds public chainlinkPriceFeeds;
    UniswapV2PoolTokenPrice public uniswapV2PoolTokenPrice;
    UniswapV3Price public uniswapV3Price;
    BunniPrice public bunniPrice;

    // SPPLY Submodules
    AuraBalancerSupply public auraBalancerSupply;
    BLVaultSupply public blVaultSupply;
    BunniSupply public bunniSupply;
    MigrationOffsetSupply public migrationOffsetSupply;

    // Policies
    Operator public operator;
    OlympusHeart public heart;
    BondCallback public callback;
    OlympusPriceConfig public priceConfig;
    RolesAdmin public rolesAdmin;
    TreasuryCustodian public treasuryCustodian;
    Distributor public distributor;
    ZeroDistributor public zeroDistributor;
    Emergency public emergency;
    BondManager public bondManager;
    Burner public burner;
    BLVaultManagerLido public lidoVaultManager;
    BLVaultLido public lidoVault;
    BLVaultManagerLusd public lusdVaultManager;
    BLVaultLusd public lusdVault;
    CrossChainBridge public bridge;
    Bookkeeper public bookkeeper;
    BunniManager public bunniManager;
    Appraiser public appraiser;

    // External contracts
    BunniHub public bunniHub;
    BunniLens public bunniLens;

    // Construction variables

    // Token addresses
    ERC20 public ohm;
    ERC20 public reserve;
    ERC4626 public wrappedReserve;
    ERC20 public wsteth;
    ERC20 public lusd;
    ERC20 public aura;
    ERC20 public bal;
    ERC20 public gOHM;

    address public migrationContract;

    // Bond system addresses
    IBondSDA public bondAuctioneer;
    IBondSDA public bondFixedExpiryAuctioneer;
    IBondTeller public bondFixedExpiryTeller;
    IBondAggregator public bondAggregator;

    // Chainlink price feed addresses
    AggregatorV2V3Interface public ohmEthPriceFeed;
    AggregatorV2V3Interface public reserveEthPriceFeed;
    AggregatorV2V3Interface public ethUsdPriceFeed;
    AggregatorV2V3Interface public stethUsdPriceFeed;
    AggregatorV2V3Interface public lusdUsdPriceFeed;

    // External contracts
    address public staking;
    address public gnosisEasyAuction;

    // Balancer Contracts
    IVault public balancerVault;
    IBalancerHelper public balancerHelper;
    IBasePool public ohmWstethPool;
    IBasePool public ohmLusdPool;

    // Aura Contracts
    IAuraBooster public auraBooster;
    IAuraMiningLib public auraMiningLib;
    IAuraRewardPool public ohmWstethRewardsPool;
    IAuraRewardPool public ohmLusdRewardsPool;

    // Deploy system storage
    string public chain;
    string public env;
    mapping(string => bytes4) public selectorMap;
    mapping(string => bytes) public argsMap;
    string[] public deployments;
    mapping(string => address) public deployedTo;

    function _setUp(string calldata chain_, string calldata deployFilePath) internal {
        chain = chain_;

        // Setup contract -> selector mappings
        // Modules
        selectorMap["OlympusPrice"] = this._deployPrice.selector;
        selectorMap["OlympusPricev2"] = this._deployPricev2.selector;
        selectorMap["OlympusRange"] = this._deployRange.selector;
        selectorMap["OlympusTreasury"] = this._deployTreasury.selector;
        selectorMap["OlympusMinter"] = this._deployMinter.selector;
        selectorMap["OlympusRoles"] = this._deployRoles.selector;
        selectorMap["OlympusSupply"] = this._deploySupply.selector;

        // Policies
        selectorMap["OlympusBoostedLiquidityRegistry"] = this
            ._deployBoostedLiquidityRegistry
            .selector;
        selectorMap["Operator"] = this._deployOperator.selector;
        selectorMap["OlympusHeart"] = this._deployHeart.selector;
        selectorMap["BondCallback"] = this._deployBondCallback.selector;
        selectorMap["OlympusPriceConfig"] = this._deployPriceConfig.selector;
        selectorMap["RolesAdmin"] = this._deployRolesAdmin.selector;
        selectorMap["TreasuryCustodian"] = this._deployTreasuryCustodian.selector;
        selectorMap["Distributor"] = this._deployDistributor.selector;
        selectorMap["ZeroDistributor"] = this._deployZeroDistributor.selector;
        selectorMap["Emergency"] = this._deployEmergency.selector;
        selectorMap["BondManager"] = this._deployBondManager.selector;
        selectorMap["Burner"] = this._deployBurner.selector;
        selectorMap["BLVaultLido"] = this._deployBLVaultLido.selector;
        selectorMap["BLVaultManagerLido"] = this._deployBLVaultManagerLido.selector;
        selectorMap["CrossChainBridge"] = this._deployCrossChainBridge.selector;
        selectorMap["BLVaultLusd"] = this._deployBLVaultLusd.selector;
        selectorMap["BLVaultManagerLusd"] = this._deployBLVaultManagerLusd.selector;
        selectorMap["Bookkeeper"] = this._deployBookkeeper.selector;
        selectorMap["BunniManager"] = this._deployBunniManagerPolicy.selector;
        selectorMap["Appraiser"] = this._deployAppraiser.selector;

        // PRICE Submodules
        selectorMap["SimplePriceFeedStrategy"] = this._deploySimplePriceFeedStrategy.selector;
        selectorMap["BalancerPoolTokenPrice"] = this._deployBalancerPoolTokenPrice.selector;
        selectorMap["ChainlinkPriceFeeds"] = this._deployChainlinkPriceFeeds.selector;
        selectorMap["UniswapV2PoolTokenPrice"] = this._deployUniswapV2PoolTokenPrice.selector;
        selectorMap["UniswapV3Price"] = this._deployUniswapV3Price.selector;
        selectorMap["BunniPrice"] = this._deployBunniPrice.selector;

        // SPPLY Submodules
        selectorMap["AuraBalancerSupply"] = this._deployAuraBalancerSupply.selector;
        selectorMap["BLVaultSupply"] = this._deployBLVaultSupply.selector;
        selectorMap["BunniSupply"] = this._deployBunniSupply.selector;
        selectorMap["MigrationOffsetSupply"] = this._deployMigrationOffsetSupply.selector;

        // Load environment addresses
        env = vm.readFile("./src/scripts/env.json");

        // Non-bophades contracts
        ohm = ERC20(envAddress("olympus.legacy.OHM"));
        gOHM = ERC20(envAddress("olympus.legacy.gOHM"));
        reserve = ERC20(envAddress("external.tokens.DAI"));
        wrappedReserve = ERC4626(envAddress("external.tokens.sDAI"));
        wsteth = ERC20(envAddress("external.tokens.WSTETH"));
        aura = ERC20(envAddress("external.tokens.AURA"));
        bal = ERC20(envAddress("external.tokens.BAL"));
        migrationContract = envAddress("olympus.legacy.Migration");
        bondAuctioneer = IBondSDA(envAddress("external.bond-protocol.BondFixedTermAuctioneer"));
        bondFixedExpiryAuctioneer = IBondSDA(
            envAddress("external.bond-protocol.BondFixedExpiryAuctioneer")
        );
        bondFixedExpiryTeller = IBondTeller(
            envAddress("external.bond-protocol.BondFixedExpiryTeller")
        );
        bondAggregator = IBondAggregator(envAddress("external.bond-protocol.BondAggregator"));
        ohmEthPriceFeed = AggregatorV2V3Interface(envAddress("external.chainlink.ohmEthPriceFeed"));
        reserveEthPriceFeed = AggregatorV2V3Interface(
            envAddress("external.chainlink.daiEthPriceFeed")
        );
        ethUsdPriceFeed = AggregatorV2V3Interface(envAddress("external.chainlink.ethUsdPriceFeed"));
        stethUsdPriceFeed = AggregatorV2V3Interface(
            envAddress("external.chainlink.stethUsdPriceFeed")
        );
        staking = envAddress("olympus.legacy.Staking");
        gnosisEasyAuction = envAddress("external.gnosis.EasyAuction");
        balancerVault = IVault(envAddress("external.balancer.BalancerVault"));
        balancerHelper = IBalancerHelper(envAddress("external.balancer.BalancerHelper"));
        ohmWstethPool = IBasePool(envAddress("external.balancer.OhmWstethPool"));
        ohmLusdPool = IBasePool(envAddress("external.balancer.OhmLusdPool"));
        auraBooster = IAuraBooster(envAddress("external.aura.AuraBooster"));
        auraMiningLib = IAuraMiningLib(envAddress("external.aura.AuraMiningLib"));
        ohmWstethRewardsPool = IAuraRewardPool(envAddress("external.aura.OhmWstethRewardsPool"));
        ohmLusdRewardsPool = IAuraRewardPool(envAddress("external.aura.OhmLusdRewardsPool"));

        // Bophades contracts
        kernel = Kernel(envAddress("olympus.Kernel"));

        // Bophades Modules
        PRICE = OlympusPrice(envAddress("olympus.modules.OlympusPrice"));
        PRICEv2 = OlympusPricev2(envAddress("olympus.modules.OlympusPricev2"));
        RANGE = OlympusRange(envAddress("olympus.modules.OlympusRange"));
        TRSRY = OlympusTreasury(envAddress("olympus.modules.OlympusTreasury"));
        MINTR = OlympusMinter(envAddress("olympus.modules.OlympusMinter"));
        INSTR = OlympusInstructions(envAddress("olympus.modules.OlympusInstructions"));
        ROLES = OlympusRoles(envAddress("olympus.modules.OlympusRoles"));
        BLREG = OlympusBoostedLiquidityRegistry(
            envAddress("olympus.modules.OlympusBoostedLiquidityRegistry")
        );
        SPPLY = OlympusSupply(envAddress("olympus.modules.OlympusSupply"));

        // Bophades Policies
        operator = Operator(envAddress("olympus.policies.Operator"));
        heart = OlympusHeart(envAddress("olympus.policies.OlympusHeart"));
        callback = BondCallback(envAddress("olympus.policies.BondCallback"));
        priceConfig = OlympusPriceConfig(envAddress("olympus.policies.OlympusPriceConfig"));
        rolesAdmin = RolesAdmin(envAddress("olympus.policies.RolesAdmin"));
        treasuryCustodian = TreasuryCustodian(envAddress("olympus.policies.TreasuryCustodian"));
        distributor = Distributor(envAddress("olympus.policies.Distributor"));
        zeroDistributor = ZeroDistributor(envAddress("olympus.policies.ZeroDistributor"));
        emergency = Emergency(envAddress("olympus.policies.Emergency"));
        bondManager = BondManager(envAddress("olympus.policies.BondManager"));
        burner = Burner(envAddress("olympus.policies.Burner"));
        lidoVaultManager = BLVaultManagerLido(envAddress("olympus.policies.BLVaultManagerLido"));
        lidoVault = BLVaultLido(envAddress("olympus.policies.BLVaultLido"));
        bookkeeper = Bookkeeper(envAddress("olympus.policies.Bookkeeper"));
        bridge = CrossChainBridge(envAddress("olympus.policies.CrossChainBridge"));
        lusdVaultManager = BLVaultManagerLusd(envAddress("olympus.policies.BLVaultManagerLusd"));
        lusdVault = BLVaultLusd(envAddress("olympus.policies.BLVaultLusd"));
        appraiser = Appraiser(envAddress("olympus.policies.Appraiser"));

        // PRICE submodules
        simplePriceFeedStrategy = SimplePriceFeedStrategy(
            envAddress("olympus.submodules.PRICE.SimplePriceFeedStrategy")
        );
        balancerPoolTokenPrice = BalancerPoolTokenPrice(
            envAddress("olympus.submodules.PRICE.BalancerPoolTokenPrice")
        );
        chainlinkPriceFeeds = ChainlinkPriceFeeds(
            envAddress("olympus.submodules.PRICE.ChainlinkPriceFeeds")
        );
        uniswapV2PoolTokenPrice = UniswapV2PoolTokenPrice(
            envAddress("olympus.submodules.PRICE.UniswapV2PoolTokenPrice")
        );
        uniswapV3Price = UniswapV3Price(envAddress("olympus.submodules.PRICE.UniswapV3Price"));
        bunniPrice = BunniPrice(envAddress("olympus.submodules.PRICE.BunniPrice"));

        // SPPLY submodules
        auraBalancerSupply = AuraBalancerSupply(
            envAddress("olympus.submodules.SPPLY.AuraBalancerSupply")
        );
        blVaultSupply = BLVaultSupply(envAddress("olympus.submodules.SPPLY.BLVaultSupply"));
        bunniSupply = BunniSupply(envAddress("olympus.submodules.SPPLY.BunniSupply"));
        migrationOffsetSupply = MigrationOffsetSupply(
            envAddress("olympus.submodules.SPPLY.MigrationOffsetSupply")
        );

        // External contracts
        bunniHub = BunniHub(envAddress("external.UniswapV3.BunniHub"));
        bunniLens = BunniLens(envAddress("external.UniswapV3.BunniLens"));

        // Load deployment data
        string memory data = vm.readFile(deployFilePath);

        // Parse deployment sequence and names
        string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
        uint256 len = names.length;

        // Iterate through deployment sequence and set deployment args
        for (uint256 i = 0; i < len; i++) {
            string memory name = names[i];
            deployments.push(name);
            console2.log("Deploying", name);

            // Parse and store args if not kernel
            // Note: constructor args need to be provided in alphabetical order
            // due to changes with forge-std or a struct needs to be used
            if (keccak256(bytes(name)) != keccak256(bytes("Kernel"))) {
                argsMap[name] = data.parseRaw(
                    string.concat(".sequence[?(@.name == '", name, "')].args")
                );
            }
        }
    }

    function envAddress(string memory key_) internal returns (address) {
        return env.readAddress(string.concat(".current.", chain, ".", key_));
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

    function deploy(string calldata chain_, string calldata deployFilePath) external {
        // Setup
        _setUp(chain_, deployFilePath);

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
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(selector, args)
            );
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
            uint256 highCushionSpread,
            uint256 highWallSpread,
            uint256 lowCushionSpread,
            uint256 lowWallSpread,
            uint256 thresholdFactor
        ) = abi.decode(args, (uint256, uint256, uint256, uint256, uint256));

        console2.log("   highCushionSpread", highCushionSpread);
        console2.log("   highWallSpread", highWallSpread);
        console2.log("   lowCushionSpread", lowCushionSpread);
        console2.log("   lowWallSpread", lowWallSpread);
        console2.log("   thresholdFactor", thresholdFactor);

        // Deploy Range module
        vm.broadcast();
        RANGE = new OlympusRange(
            kernel,
            ohm,
            reserve,
            thresholdFactor,
            [lowCushionSpread, lowWallSpread],
            [highCushionSpread, highWallSpread]
        );
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

    function _deployBoostedLiquidityRegistry(bytes memory args) public returns (address) {
        // No additional arguments for OlympusBoostedLiquidityRegistry module

        // Deploy OlympusBoostedLiquidityRegistry module
        vm.broadcast();
        BLREG = new OlympusBoostedLiquidityRegistry(kernel);
        console2.log("BLREG deployed at:", address(BLREG));

        return address(BLREG);
    }

    function _deployAppraiser(bytes memory) public returns (address) {
        // No additional arguments for Appraiser module

        // Deploy Appraiser module
        vm.broadcast();
        appraiser = new Appraiser(kernel);
        console2.log("Appraiser deployed at:", address(appraiser));

        return address(appraiser);
    }

    // Policy deployment functions
    function _deployOperator(bytes memory args) public returns (address) {
        // Decode arguments for Operator policy
        (
            uint256 cushionDebtBuffer,
            uint256 cushionDepositInterval,
            uint256 cushionDuration,
            uint256 cushionFactor,
            uint256 regenObserve,
            uint256 regenThreshold,
            uint256 regenWait,
            uint256 reserveFactor
        ) = abi.decode(
                args,
                (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
            );

        // Create config params array
        // Order is not alphabetical. Copied from the constructor.
        uint32[8] memory configParams = [
            uint32(cushionFactor),
            uint32(cushionDuration),
            uint32(cushionDebtBuffer),
            uint32(cushionDepositInterval),
            uint32(reserveFactor),
            uint32(regenWait),
            uint32(regenThreshold),
            uint32(regenObserve)
        ];

        // Check that the environment variables are loaded
        if (address(kernel) == address(0)) revert("Kernel address not set");
        if (address(appraiser) == address(0)) revert("Appraiser address not set");
        if (address(bondAuctioneer) == address(0)) revert("BondAuctioneer address not set");
        if (address(callback) == address(0)) revert("Callback address not set");
        if (address(ohm) == address(0)) revert("OHM address not set");
        if (address(reserve) == address(0)) revert("Reserve address not set");

        console2.log("   kernel", address(kernel));
        console2.log("   appraiser", address(appraiser));
        console2.log("   bondAuctioneer", address(bondAuctioneer));
        console2.log("   callback", address(callback));
        console2.log("   ohm", address(ohm));
        console2.log("   reserve", address(reserve));
        console2.log("   wrappedReserve", address(wrappedReserve));
        console2.log("   cushionDebtBuffer", cushionDebtBuffer);
        console2.log("   cushionDepositInterval", cushionDepositInterval);
        console2.log("   cushionDuration", cushionDuration);
        console2.log("   cushionFactor", cushionFactor);
        console2.log("   regenObserve", regenObserve);
        console2.log("   regenThreshold", regenThreshold);
        console2.log("   regenWait", regenWait);
        console2.log("   reserveFactor", reserveFactor);

        // Deploy Operator policy
        vm.broadcast();
        operator = new Operator(
            kernel,
            appraiser,
            bondAuctioneer,
            callback,
            [address(ohm), address(reserve), address(wrappedReserve)],
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
        (uint48 auctionDuration, uint256 maxReward) = abi.decode(args, (uint48, uint256));

        // Check that the environment variables are loaded
        if (address(kernel) == address(0)) revert("Kernel address not set");
        if (address(operator) == address(0)) revert("Operator address not set");
        if (address(appraiser) == address(0)) revert("Appraiser address not set");
        if (address(zeroDistributor) == address(0)) revert("ZeroDistributor address not set");

        // Deploy OlympusHeart policy
        vm.broadcast();
        heart = new OlympusHeart(
            kernel,
            operator,
            appraiser,
            zeroDistributor,
            maxReward,
            auctionDuration
        );
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

    function _deployZeroDistributor(bytes memory args) public returns (address) {
        // Deploy ZeroDistributor policy
        vm.broadcast();
        zeroDistributor = new ZeroDistributor(staking);
        console2.log("ZeroDistributor deployed at:", address(distributor));

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

    function _deployBondManager(bytes memory args) public returns (address) {
        // Deploy BondManager policy
        vm.broadcast();
        bondManager = new BondManager(
            kernel,
            address(bondFixedExpiryAuctioneer),
            address(bondFixedExpiryTeller),
            gnosisEasyAuction,
            address(ohm)
        );
        console2.log("BondManager deployed at:", address(bondManager));

        return address(bondManager);
    }

    function _deployBurner(bytes memory args) public returns (address) {
        // No additional arguments for Burner policy

        // Deploy Burner policy
        vm.broadcast();
        burner = new Burner(kernel, ohm);
        console2.log("Burner deployed at:", address(burner));

        return address(burner);
    }

    function _deployBLVaultLido(bytes memory args) public returns (address) {
        // No additional arguments for BLVaultLido policy

        // Deploy BLVaultLido policy
        vm.broadcast();
        lidoVault = new BLVaultLido();
        console2.log("BLVaultLido deployed at:", address(lidoVault));

        return address(lidoVault);
    }

    // deploy.json was not being parsed correctly, so I had to hardcode most of the deployment arguments
    function _deployBLVaultManagerLido(bytes memory args) public returns (address) {
        console2.log("ohm", address(ohm));
        console2.log("wsteth", address(wsteth));
        console2.log("aura", address(aura));
        console2.log("bal", address(bal));
        console2.log("balancerVault", address(balancerVault));
        console2.log("ohmWstethPool", address(ohmWstethPool));
        console2.log("balancerHelper", address(balancerHelper));
        console2.log("auraBooster", address(auraBooster));
        console2.log("ohmWstethRewardsPool", address(ohmWstethRewardsPool));
        console2.log("ohmEthPriceFeed", address(ohmEthPriceFeed));
        console2.log("ethUsdPriceFeed", address(ethUsdPriceFeed));
        console2.log("stethUsdPriceFeed", address(stethUsdPriceFeed));
        console2.log("implementation", address(lidoVault));

        // Create TokenData object
        IBLVaultManagerLido.TokenData memory tokenData = IBLVaultManagerLido.TokenData({
            ohm: address(ohm),
            pairToken: address(wsteth),
            aura: address(aura),
            bal: address(bal)
        });

        // Create BalancerData object
        IBLVaultManagerLido.BalancerData memory balancerData = IBLVaultManagerLido.BalancerData({
            vault: address(balancerVault),
            liquidityPool: address(ohmWstethPool),
            balancerHelper: address(balancerHelper)
        });

        // Create AuraData object
        IBLVaultManagerLido.AuraData memory auraData = IBLVaultManagerLido.AuraData({
            pid: uint256(73),
            auraBooster: address(auraBooster),
            auraRewardPool: address(ohmWstethRewardsPool)
        });

        // Create OracleFeed objects
        IBLVaultManagerLido.OracleFeed memory ohmEthPriceFeedData = IBLVaultManagerLido.OracleFeed({
            feed: ohmEthPriceFeed,
            updateThreshold: uint48(86400) // needs to be 1 day
        });

        IBLVaultManagerLido.OracleFeed memory ethUsdPriceFeedData = IBLVaultManagerLido.OracleFeed({
            feed: ethUsdPriceFeed,
            updateThreshold: uint48(3600) // needs to be 1 hour
        });

        IBLVaultManagerLido.OracleFeed memory stethUsdPriceFeedData = IBLVaultManagerLido
            .OracleFeed({
                feed: stethUsdPriceFeed,
                updateThreshold: uint48(3600) // needs to be 1 hour
            });

        console2.log("pid: ", auraData.pid);
        console2.log("OHM update threshold: ", ohmEthPriceFeedData.updateThreshold);
        console2.log("ETH update threshold: ", ethUsdPriceFeedData.updateThreshold);
        console2.log("stETH update threshold: ", stethUsdPriceFeedData.updateThreshold);

        // Deploy BLVaultManagerLido policy
        vm.broadcast();
        lidoVaultManager = new BLVaultManagerLido(
            kernel,
            tokenData,
            balancerData,
            auraData,
            address(auraMiningLib),
            ohmEthPriceFeedData,
            ethUsdPriceFeedData,
            stethUsdPriceFeedData,
            address(lidoVault),
            476_000e9, // 476_000e9
            uint64(0), // fee
            uint48(1 days) // withdrawal delay
        );
        console2.log("BLVaultManagerLido deployed at:", address(lidoVaultManager));

        return address(lidoVaultManager);
    }

    function _deployBLVaultLusd(bytes memory args) public returns (address) {
        // No additional arguments for BLVaultLusd policy

        // Deploy BLVaultLusd policy
        vm.broadcast();
        lusdVault = new BLVaultLusd();
        console2.log("BLVaultLusd deployed at:", address(lusdVault));

        return address(lusdVault);
    }

    function _deployBLVaultManagerLusd(bytes memory args) public returns (address) {
        // Decode arguments for BLVaultManagerLusd policy
        // The JSON is encoded by the properties in alphabetical order, so the output tuple must be in alphabetical order, irrespective of the order in the JSON file itself
        (
            uint256 auraPid,
            uint256 ethUsdFeedUpdateThreshold,
            uint256 lusdUsdFeedUpdateThreshold,
            uint256 ohmEthFeedUpdateThreshold
        ) = abi.decode(args, (uint256, uint256, uint256, uint256));

        console2.log("ohm", address(ohm));
        console2.log("lusd", address(lusd));
        console2.log("aura", address(aura));
        console2.log("bal", address(bal));
        console2.log("balancerVault", address(balancerVault));
        console2.log("ohmLusdPool", address(ohmLusdPool));
        console2.log("balancerHelper", address(balancerHelper));
        console2.log("auraBooster", address(auraBooster));
        console2.log("ohmLusdRewardsPool", address(ohmLusdRewardsPool));
        console2.log("ohmEthPriceFeed", address(ohmEthPriceFeed));
        console2.log("ethUsdPriceFeed", address(ethUsdPriceFeed));
        console2.log("lusdUsdPriceFeed", address(lusdUsdPriceFeed));
        console2.log("BLV LUSD implementation", address(lusdVault));

        // Create TokenData object
        IBLVaultManager.TokenData memory tokenData = IBLVaultManager.TokenData({
            ohm: address(ohm),
            pairToken: address(lusd),
            aura: address(aura),
            bal: address(bal)
        });

        // Create BalancerData object
        IBLVaultManager.BalancerData memory balancerData = IBLVaultManager.BalancerData({
            vault: address(balancerVault),
            liquidityPool: address(ohmLusdPool),
            balancerHelper: address(balancerHelper)
        });

        // Create AuraData object
        IBLVaultManager.AuraData memory auraData = IBLVaultManager.AuraData({
            pid: uint256(auraPid),
            auraBooster: address(auraBooster),
            auraRewardPool: address(ohmLusdRewardsPool) // determined by calling poolInfo(auraPid) on the booster contract
        });

        // Create OracleFeed objects
        IBLVaultManager.OracleFeed memory ohmEthPriceFeedData = IBLVaultManager.OracleFeed({
            feed: ohmEthPriceFeed,
            updateThreshold: uint48(ohmEthFeedUpdateThreshold)
        });

        IBLVaultManager.OracleFeed memory ethUsdPriceFeedData = IBLVaultManager.OracleFeed({
            feed: ethUsdPriceFeed,
            updateThreshold: uint48(ethUsdFeedUpdateThreshold)
        });

        IBLVaultManager.OracleFeed memory lusdUsdPriceFeedData = IBLVaultManager.OracleFeed({
            feed: lusdUsdPriceFeed,
            updateThreshold: uint48(lusdUsdFeedUpdateThreshold)
        });

        console2.log("pid: ", auraData.pid);
        console2.log("OHM update threshold: ", ohmEthPriceFeedData.updateThreshold);
        console2.log("ETH update threshold: ", ethUsdPriceFeedData.updateThreshold);
        console2.log("LUSD update threshold: ", lusdUsdPriceFeedData.updateThreshold);

        // Deploy BLVaultManagerLusd policy
        vm.broadcast();
        lusdVaultManager = new BLVaultManagerLusd(
            kernel,
            tokenData,
            balancerData,
            auraData,
            address(auraMiningLib),
            ohmEthPriceFeedData,
            ethUsdPriceFeedData,
            lusdUsdPriceFeedData,
            address(lusdVault),
            // 2500000 cap/$10.84 = 230,627.3062730627 OHM
            230_627e9, // max OHM minted
            uint64(500), // fee // 10_000 = 1 = 100%, 500 / 1e4 = 0.05 = 5%
            uint48(1 days) // withdrawal delay
        );
        console2.log("BLVaultManagerLusd deployed at:", address(lusdVaultManager));

        return address(lusdVaultManager);
    }

    function _deployCrossChainBridge(bytes memory args) public returns (address) {
        address lzEndpoint = abi.decode(args, (address));

        // Deploy CrossChainBridge policy
        vm.broadcast();
        bridge = new CrossChainBridge(kernel, lzEndpoint);
        console2.log("Bridge deployed at:", address(bridge));

        return address(bridge);
    }

    function _deployBookkeeper(bytes memory args) public returns (address) {
        // No additional arguments for Bookkeeper policy

        // Deploy Bookkeeper policy
        vm.broadcast();
        bookkeeper = new Bookkeeper(kernel);
        console2.log("Bookkeeper deployed at:", address(bookkeeper));

        return address(bookkeeper);
    }

    function _deployPricev2(bytes memory args) public returns (address) {
        // Decode arguments for PRICEv2 module
        (uint8 decimals, uint32 observationFrequency) = abi.decode(args, (uint8, uint32));

        console2.log("decimals", decimals);
        console2.log("observationFrequency", observationFrequency);

        // Deploy V2 Price module
        vm.broadcast();
        PRICEv2 = new OlympusPricev2(kernel, decimals, observationFrequency);
        console2.log("OlympusPricev2 deployed at:", address(PRICEv2));

        return address(PRICEv2);
    }

    function _deployBunniManagerPolicy(bytes memory args) public returns (address) {
        // Arguments
        // The JSON is encoded by the properties in alphabetical order, so the output tuple must be in alphabetical order, irrespective of the order in the JSON file itself
        (
            uint48 harvestFrequency,
            uint16 harvestRewardFee,
            uint256 harvestRewardMax,
            address uniswapFactory
        ) = abi.decode(args, (uint48, uint16, uint256, address));

        console2.log("harvestFrequency", harvestFrequency);
        console2.log("harvestRewardFee", harvestRewardFee);
        console2.log("harvestRewardMax", harvestRewardMax);
        console2.log("uniswapFactory", uniswapFactory);

        // Check that the environment variables are loaded
        if (address(kernel) == address(0)) revert("Kernel address not set");

        // Deployment steps
        vm.broadcast();

        // Deploy the policy
        bunniManager = new BunniManager(
            kernel,
            harvestRewardMax,
            harvestRewardFee,
            harvestFrequency
        );
        console2.log("BunniManager deployed at:", address(bunniManager));

        // Deploy the BunniHub
        bunniHub = new BunniHub(
            IUniswapV3Factory(uniswapFactory),
            address(bunniManager),
            0 // No protocol fee
        );
        console2.log("BunniHub deployed at:", address(bunniHub));

        // Deploy the BunniLens
        bunniLens = new BunniLens(bunniHub);
        console2.log("BunniLens deployed at:", address(bunniLens));

        // Post-deployment steps (requiring permissions):
        // - Call BunniManager.setBunniLens
        // - Create the "bunni_admin" role and assign it
        // - Activate the BunniManager policy
    }

    function _deploySupply(bytes memory args) public returns (address) {
        // Arguments
        // The JSON is encoded by the properties in alphabetical order, so the output tuple must be in alphabetical order, irrespective of the order in the JSON file itself
        uint256 initialCrossChainSupply = abi.decode(args, (uint256));

        // TODO fill in the initialCrossChainSupply value

        console2.log("initialCrossChainSupply", initialCrossChainSupply);

        // Check that environment variables are loaded
        if (address(kernel) == address(0)) revert("Kernel address not set");
        if (address(ohm) == address(0)) revert("OHM address not set");
        if (address(gOHM) == address(0)) revert("gOHM address not set");

        address[2] memory tokens = [address(ohm), address(gOHM)];

        // Deployment steps
        vm.broadcast();

        // Deploy the module
        SPPLY = new OlympusSupply(kernel, tokens, initialCrossChainSupply);

        console2.log("SPPLY deployed at:", address(SPPLY));

        return address(SPPLY);
    }

    // ========== PRICE SUBMODULES ========== //

    function _deploySimplePriceFeedStrategy(bytes memory args) public returns (address) {
        // No additional arguments for SimplePriceFeedStrategy submodule

        // Check that environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");

        // Deploy SimplePriceFeedStrategy submodule
        vm.broadcast();
        simplePriceFeedStrategy = new SimplePriceFeedStrategy(PRICEv2);
        console2.log("SimplePriceFeedStrategy deployed at:", address(simplePriceFeedStrategy));

        return address(simplePriceFeedStrategy);
    }

    function _deployBalancerPoolTokenPrice(bytes memory args) public returns (address) {
        // No additional arguments for BalancerPoolTokenPrice submodule

        // Check that environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");
        if (address(balancerVault) == address(0)) revert("balancerVault address not set");

        // Deploy BalancerPoolTokenPrice submodule
        vm.broadcast();
        balancerPoolTokenPrice = new BalancerPoolTokenPrice(
            PRICEv2,
            IBalancerVault(address(balancerVault))
        );
        console2.log("BalancerPoolTokenPrice deployed at:", address(balancerPoolTokenPrice));

        return address(balancerPoolTokenPrice);
    }

    function _deployChainlinkPriceFeeds(bytes memory args) public returns (address) {
        // No additional arguments for ChainlinkPriceFeeds submodule

        // Check that environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");

        // Deploy ChainlinkPriceFeeds submodule
        vm.broadcast();
        chainlinkPriceFeeds = new ChainlinkPriceFeeds(PRICEv2);
        console2.log("ChainlinkPriceFeeds deployed at:", address(chainlinkPriceFeeds));

        return address(chainlinkPriceFeeds);
    }

    function _deployUniswapV2PoolTokenPrice(bytes memory args) public returns (address) {
        // No additional arguments for UniswapV2PoolTokenPrice submodule

        // Check that environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");

        // Deploy UniswapV2PoolTokenPrice submodule
        vm.broadcast();
        uniswapV2PoolTokenPrice = new UniswapV2PoolTokenPrice(PRICEv2);
        console2.log("UniswapV2PoolTokenPrice deployed at:", address(uniswapV2PoolTokenPrice));

        return address(uniswapV2PoolTokenPrice);
    }

    function _deployUniswapV3Price(bytes memory args) public returns (address) {
        // No additional arguments for UniswapV3Price submodule

        // Check that environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");

        // Deploy UniswapV3Price submodule
        vm.broadcast();
        uniswapV3Price = new UniswapV3Price(PRICEv2);
        console2.log("UniswapV3Price deployed at:", address(uniswapV3Price));

        return address(uniswapV3Price);
    }

    function _deployBunniPrice(bytes memory) public returns (address) {
        // No additional arguments for BunniPrice submodule

        // Check that the environment variables are loaded
        if (address(PRICEv2) == address(0)) revert("PRICEv2 address not set");

        // Deploy BunniPrice submodule
        vm.broadcast();
        bunniPrice = new BunniPrice(PRICEv2);
        console2.log("BunniPrice deployed at:", address(bunniPrice));

        return address(bunniPrice);
    }

    // ========== SPPLY SUBMODULES ========== //

    function _deployAuraBalancerSupply(bytes memory) public returns (address) {
        // No additional arguments for AuraBalancerSupply submodule

        // Check that the environment variables are loaded
        if (address(SPPLY) == address(0)) revert("SPPLY address not set");
        if (address(TRSRY) == address(0)) revert("TRSRY address not set");
        if (address(balancerVault) == address(0)) revert("balancerVault address not set");

        AuraBalancerSupply.Pool[] memory pools = new AuraBalancerSupply.Pool[](0);

        // Deploy AuraBalancerSupply submodule
        vm.broadcast();
        auraBalancerSupply = new AuraBalancerSupply(
            SPPLY,
            address(TRSRY),
            address(balancerVault),
            pools
        );
        console2.log("AuraBalancerSupply deployed at:", address(auraBalancerSupply));

        return address(auraBalancerSupply);
    }

    function _deployBLVaultSupply(bytes memory) public returns (address) {
        // No additional arguments for BLVaultSupply submodule

        // Check that the environment variables are loaded
        if (address(SPPLY) == address(0)) revert("SPPLY address not set");
        if (address(lidoVaultManager) == address(0)) revert("lidoVaultManager address not set");
        if (address(lusdVaultManager) == address(0)) revert("lusdVaultManager address not set");

        address[] memory vaultManagers = new address[](2);
        vaultManagers[0] = address(lidoVaultManager);
        vaultManagers[1] = address(lusdVaultManager);

        // Deploy BLVaultSupply submodule
        vm.broadcast();
        blVaultSupply = new BLVaultSupply(SPPLY, vaultManagers);
        console2.log("BLVaultSupply deployed at:", address(blVaultSupply));

        return address(blVaultSupply);
    }

    function _deployBunniSupply(bytes memory) public returns (address) {
        // No additional arguments for BunniSupply submodule

        // Check that the environment variables are loaded
        if (address(SPPLY) == address(0)) revert("SPPLY address not set");

        // Deploy BunniSupply submodule
        vm.broadcast();
        bunniSupply = new BunniSupply(SPPLY);
        console2.log("BunniSupply deployed at:", address(bunniSupply));

        return address(bunniSupply);
    }

    function _deployMigrationOffsetSupply(bytes memory args) public returns (address) {
        // Decode arguments for MigrationOffsetSupply submodule
        uint256 migrationOffset = abi.decode(args, (uint256));

        console2.log("migrationOffset", migrationOffset);

        // Check that the environment variables are loaded
        if (address(SPPLY) == address(0)) revert("SPPLY address not set");
        if (migrationContract == address(0)) revert("migrationContract address not set");

        // Deploy MigrationOffsetSupply submodule
        vm.broadcast();
        migrationOffsetSupply = new MigrationOffsetSupply(
            SPPLY,
            migrationContract,
            migrationOffset
        );
        console2.log("MigrationOffsetSupply deployed at:", address(migrationOffsetSupply));

        return address(migrationOffsetSupply);
    }

    // ========== VERIFICATION ========== //

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

    /// @dev Should be called by the deployer address after deployment
    function verifyAuth(address guardian_, address policy_, address emergency_) external {
        ROLES = OlympusRoles(vm.envAddress("ROLES"));
        heart = OlympusHeart(vm.envAddress("HEART"));
        callback = BondCallback(vm.envAddress("CALLBACK"));
        operator = Operator(vm.envAddress("OPERATOR"));
        rolesAdmin = RolesAdmin(vm.envAddress("ROLESADMIN"));
        kernel = Kernel(vm.envAddress("KERNEL"));
        bondManager = BondManager(vm.envAddress("BONDMANAGER"));
        burner = Burner(vm.envAddress("BURNER"));

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

        /// Burner Roles
        require(ROLES.hasRole(guardian_, "burner_admin"));
    }

    function _saveDeployment(string memory chain_) internal {
        // Create file path
        string memory file = string.concat(
            "./deployments/",
            ".",
            chain_,
            "-",
            vm.toString(block.timestamp),
            ".json"
        );

        // Write deployment info to file in JSON format
        vm.writeLine(file, "{");

        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployments.length;
        for (uint256 i; i < len; ++i) {
            vm.writeLine(
                file,
                string.concat(
                    '"',
                    deployments[i],
                    '": "',
                    vm.toString(deployedTo[deployments[i]]),
                    '",'
                )
            );
        }
        vm.writeLine(file, "}");
    }
}

/// @notice Deploys mock Balancer and Aura contracts for testing on Goerli
// contract DependencyDeployLido is Script {
//     using stdJson for string;

//     // MockPriceFeed public ohmEthPriceFeed;
//     // MockPriceFeed public reserveEthPriceFeed;
//     ERC20 public bal;
//     ERC20 public aura;
//     ERC20 public ldo;
//     MockAuraStashToken public ldoStash;

//     IBasePool public ohmWstethPool;
//     MockAuraBooster public auraBooster;
//     MockAuraMiningLib public auraMiningLib;
//     MockAuraRewardPool public ohmWstethRewardPool;
//     MockAuraVirtualRewardPool public ohmWstethExtraRewardPool;

//     function deploy(string calldata chain_) external {
//         // Load environment addresses
//         string memory env = vm.readFile("./src/scripts/env.json");
//         bal = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.BAL")));
//         aura = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.AURA")));
//         ldo = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.LDO")));
//         ohmWstethPool = IBasePool(
//             env.readAddress(string.concat(".", chain_, ".external.balancer.OhmWstethPool"))
//         );

//         vm.startBroadcast();

//         // Deploy the mock tokens
//         // bal = new MockERC20("Balancer", "BAL", 18);
//         // console2.log("BAL deployed to:", address(bal));

//         // aura = new MockERC20("Aura", "AURA", 18);
//         // console2.log("AURA deployed to:", address(aura));

//         // ldo = new MockERC20("Lido", "LDO", 18);
//         // console2.log("LDO deployed to:", address(ldo));

//         // Deploy the Aura Reward Pools for OHM-wstETH
//         ohmWstethRewardPool = new MockAuraRewardPool(
//             address(ohmWstethPool), // Goerli OHM-wstETH LP
//             address(bal), // Goerli BAL
//             address(aura) // Goerli AURA
//         );
//         console2.log("OHM-WSTETH Reward Pool deployed to:", address(ohmWstethRewardPool));

//         // Deploy the extra rewards pool
//         ldoStash = new MockAuraStashToken("Lido-Stash", "LDOSTASH", 18, address(ldo));
//         console2.log("Lido Stash deployed to:", address(ldoStash));

//         ohmWstethExtraRewardPool = new MockAuraVirtualRewardPool(
//             address(ohmWstethPool), // Goerli OHM-wstETH LP
//             address(ldoStash)
//         );
//         console2.log(
//             "OHM-WSTETH Extra Reward Pool deployed to:",
//             address(ohmWstethExtraRewardPool)
//         );

//         ohmWstethRewardPool.addExtraReward(address(ohmWstethExtraRewardPool));
//         console2.log("Added OHM-WSTETH Extra Reward Pool to OHM-WSTETH Reward Pool");

//         // Deploy Aura Booster
//         auraBooster = new MockAuraBooster(address(ohmWstethRewardPool));
//         console2.log("Aura Booster deployed to:", address(auraBooster));

//         // Deploy the Aura Mining Library
//         // auraMiningLib = new MockAuraMiningLib();
//         // console2.log("Aura Mining Library deployed to:", address(auraMiningLib));

//         // // Deploy the price feeds
//         // ohmEthPriceFeed = new MockPriceFeed();
//         // console2.log("OHM-ETH Price Feed deployed to:", address(ohmEthPriceFeed));
//         // reserveEthPriceFeed = new MockPriceFeed();
//         // console2.log("RESERVE-ETH Price Feed deployed to:", address(reserveEthPriceFeed));

//         // // Set the decimals of the price feeds
//         // ohmEthPriceFeed.setDecimals(18);
//         // reserveEthPriceFeed.setDecimals(18);

//         vm.stopBroadcast();
//     }
// }

// contract DependencyDeployLusd is Script {
//     using stdJson for string;

//     ERC20 public bal;
//     ERC20 public aura;
//     ERC20 public ldo;
//     ERC20 public lusd;

//     MockAuraBooster public auraBooster;

//     MockPriceFeed public lusdUsdPriceFeed;
//     IBasePool public ohmLusdPool;
//     MockAuraRewardPool public ohmLusdRewardPool;

//     MockAuraMiningLib public auraMiningLib;

//     function deploy(string calldata chain_) external {
//         // Load environment addresses
//         string memory env = vm.readFile("./src/scripts/env.json");
//         bal = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.BAL")));
//         aura = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.AURA")));
//         ldo = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.LDO")));
//         lusd = ERC20(env.readAddress(string.concat(".", chain_, ".external.tokens.LUSD"))); // Requires the address of LUSD to be less than the address of OHM, in order to reflect the conditions on mainnet
//         ohmLusdPool = IBasePool(
//             env.readAddress(string.concat(".", chain_, ".external.balancer.OhmLusdPool"))
//         ); // Real pool, deployed separately as it's a little more complicated
//         auraBooster = MockAuraBooster(
//             env.readAddress(string.concat(".", chain_, ".external.aura.AuraBooster"))
//         ); // Requires DependencyDeployLido to be run first

//         vm.startBroadcast();

//         // Deploy the LUSD price feed
//         lusdUsdPriceFeed = new MockPriceFeed();
//         lusdUsdPriceFeed.setDecimals(8);
//         lusdUsdPriceFeed.setLatestAnswer(1e8);
//         lusdUsdPriceFeed.setRoundId(1);
//         lusdUsdPriceFeed.setAnsweredInRound(1);
//         lusdUsdPriceFeed.setTimestamp(block.timestamp); // Will be good for 1 year from now
//         console2.log("LUSD-USD Price Feed deployed to:", address(lusdUsdPriceFeed));

//         // Deploy the Aura Reward Pools for OHM-LUSD
//         ohmLusdRewardPool = new MockAuraRewardPool(
//             address(ohmLusdPool), // OHM-LUSD LP
//             address(bal), // BAL
//             address(aura) // AURA
//         );
//         console2.log("OHM-LUSD LP reward pool deployed to: ", address(ohmLusdRewardPool));

//         // Add the pool to the aura booster
//         auraBooster.addPool(address(ohmLusdRewardPool));
//         console2.log("Added ohmLusdRewardPool to Aura Booster");

//         vm.stopBroadcast();
//     }
// }
