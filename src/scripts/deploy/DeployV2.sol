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

// Aura
import {IAuraBooster, IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";

import {OlympusAuthority} from "src/external/OlympusAuthority.sol";

// Cooler Loans
import {CoolerFactory, Cooler} from "src/external/cooler/CoolerFactory.sol";

// Governance
import {Timelock} from "src/external/governance/Timelock.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {Distributor} from "policies/Distributor/Distributor.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";
import {Emergency} from "policies/Emergency.sol";
import {BondManager} from "policies/BondManager.sol";
import {Burner} from "policies/Burner.sol";
import {BLVaultManagerLido} from "policies/BoostedLiquidity/BLVaultManagerLido.sol";
import {BLVaultLido} from "policies/BoostedLiquidity/BLVaultLido.sol";
import {BLVaultManagerLusd} from "policies/BoostedLiquidity/BLVaultManagerLusd.sol";
import {BLVaultLusd} from "policies/BoostedLiquidity/BLVaultLusd.sol";
import {IBLVaultManagerLido} from "policies/BoostedLiquidity/interfaces/IBLVaultManagerLido.sol";
import {IBLVaultManager} from "policies/BoostedLiquidity/interfaces/IBLVaultManager.sol";
import {CrossChainBridge} from "policies/CrossChainBridge.sol";
import {LegacyBurner} from "policies/LegacyBurner.sol";
import {pOLY} from "policies/pOLY.sol";
import {ClaimTransfer} from "src/external/ClaimTransfer.sol";
import {Clearinghouse} from "policies/Clearinghouse.sol";
import {YieldRepurchaseFacility} from "policies/YieldRepurchaseFacility.sol";
import {OlympusContractRegistry} from "modules/RGSTY/OlympusContractRegistry.sol";
import {ContractRegistryAdmin} from "policies/ContractRegistryAdmin.sol";

import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockAuraBooster, MockAuraRewardPool, MockAuraMiningLib, MockAuraVirtualRewardPool, MockAuraStashToken} from "test/mocks/AuraMocks.sol";
import {MockBalancerPool, MockVault} from "test/mocks/BalancerMocks.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Faucet} from "test/mocks/Faucet.sol";
import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

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
    OlympusBoostedLiquidityRegistry public BLREG;
    OlympusClearinghouseRegistry public CHREG;
    OlympusContractRegistry public RGSTY;

    /// Policies
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
    LegacyBurner public legacyBurner;
    ContractRegistryAdmin public contractRegistryAdmin;
    LoanConsolidator public loanConsolidator;

    /// Other Olympus contracts
    OlympusAuthority public burnerReplacementAuthority;

    /// Legacy Olympus contracts
    address public inverseBondDepository;
    pOLY public poly;
    Clearinghouse public clearinghouse;
    YieldRepurchaseFacility public yieldRepo;

    // Governance
    Timelock public timelock;
    GovernorBravoDelegate public governorBravoDelegate;
    GovernorBravoDelegator public governorBravoDelegator;

    /// Construction variables

    /// Token addresses
    ERC20 public ohm;
    ERC20 public gohm;
    ERC20 public reserve;
    ERC4626 public wrappedReserve;
    ERC20 public wsteth;
    ERC20 public lusd;
    ERC20 public aura;
    ERC20 public bal;

    /// Bond system addresses
    IBondSDA public bondAuctioneer;
    IBondSDA public bondFixedExpiryAuctioneer;
    IBondTeller public bondFixedExpiryTeller;
    IBondTeller public bondFixedTermTeller;
    IBondAggregator public bondAggregator;

    /// Chainlink price feed addresses
    AggregatorV2V3Interface public ohmEthPriceFeed;
    AggregatorV2V3Interface public reserveEthPriceFeed;
    AggregatorV2V3Interface public ethUsdPriceFeed;
    AggregatorV2V3Interface public stethUsdPriceFeed;
    AggregatorV2V3Interface public lusdUsdPriceFeed;

    /// External contracts
    address public staking;
    address public gnosisEasyAuction;
    address public previousPoly;
    address public previousGenesis;
    ClaimTransfer public claimTransfer;

    /// Balancer Contracts
    IVault public balancerVault;
    IBalancerHelper public balancerHelper;
    IBasePool public ohmWstethPool;
    IBasePool public ohmLusdPool;

    /// Aura Contracts
    IAuraBooster public auraBooster;
    IAuraMiningLib public auraMiningLib;
    IAuraRewardPool public ohmWstethRewardsPool;
    IAuraRewardPool public ohmLusdRewardsPool;

    // Cooler Loan contracts
    CoolerFactory public coolerFactory;

    // Deploy system storage
    string public chain;
    string public env;
    mapping(string => bytes4) public selectorMap;
    mapping(string => bytes) public argsMap;
    string[] public deployments;
    mapping(string => address) public deployedTo;

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal {
        chain = chain_;

        // Setup contract -> selector mappings
        // Modules
        selectorMap["OlympusPrice"] = this._deployPrice.selector;
        selectorMap["OlympusRange"] = this._deployRange.selector;
        selectorMap["OlympusTreasury"] = this._deployTreasury.selector;
        selectorMap["OlympusMinter"] = this._deployMinter.selector;
        selectorMap["OlympusRoles"] = this._deployRoles.selector;
        selectorMap["OlympusBoostedLiquidityRegistry"] = this
            ._deployBoostedLiquidityRegistry
            .selector;
        selectorMap["OlympusClearinghouseRegistry"] = this._deployClearinghouseRegistry.selector;
        selectorMap["OlympusContractRegistry"] = this._deployContractRegistry.selector;
        // Policies
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
        selectorMap["LegacyBurner"] = this._deployLegacyBurner.selector;
        selectorMap["ReplacementAuthority"] = this._deployReplacementAuthority.selector;
        selectorMap["pOLY"] = this._deployPoly.selector;
        selectorMap["ClaimTransfer"] = this._deployClaimTransfer.selector;
        selectorMap["Clearinghouse"] = this._deployClearinghouse.selector;
        selectorMap["LoanConsolidator"] = this._deployLoanConsolidator.selector;
        selectorMap["YieldRepurchaseFacility"] = this._deployYieldRepurchaseFacility.selector;
        selectorMap["ContractRegistryAdmin"] = this._deployContractRegistryAdmin.selector;

        // Governance
        selectorMap["Timelock"] = this._deployTimelock.selector;
        selectorMap["GovernorBravoDelegator"] = this._deployGovernorBravoDelegator.selector;
        selectorMap["GovernorBravoDelegate"] = this._deployGovernorBravoDelegate.selector;

        // Load environment addresses
        env = vm.readFile("./src/scripts/env.json");

        // Non-bophades contracts
        ohm = ERC20(envAddress("olympus.legacy.OHM"));
        gohm = ERC20(envAddress("olympus.legacy.gOHM"));
        reserve = ERC20(envAddress("external.tokens.DAI"));
        wrappedReserve = ERC4626(envAddress("external.tokens.sDAI"));
        wsteth = ERC20(envAddress("external.tokens.WSTETH"));
        aura = ERC20(envAddress("external.tokens.AURA"));
        bal = ERC20(envAddress("external.tokens.BAL"));
        wrappedReserve = ERC4626(envAddress("external.tokens.sDAI"));
        bondAuctioneer = IBondSDA(envAddress("external.bond-protocol.BondFixedTermAuctioneer"));
        bondFixedExpiryAuctioneer = IBondSDA(
            envAddress("external.bond-protocol.BondFixedExpiryAuctioneer")
        );
        bondFixedExpiryTeller = IBondTeller(
            envAddress("external.bond-protocol.BondFixedExpiryTeller")
        );
        bondFixedTermTeller = IBondTeller(envAddress("external.bond-protocol.BondFixedTermTeller"));
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
        previousPoly = envAddress("olympus.legacy.OldPOLY");
        previousGenesis = envAddress("olympus.legacy.GenesisClaim");
        balancerVault = IVault(envAddress("external.balancer.BalancerVault"));
        balancerHelper = IBalancerHelper(envAddress("external.balancer.BalancerHelper"));
        ohmWstethPool = IBasePool(envAddress("external.balancer.OhmWstethPool"));
        ohmLusdPool = IBasePool(envAddress("external.balancer.OhmLusdPool"));
        auraBooster = IAuraBooster(envAddress("external.aura.AuraBooster"));
        auraMiningLib = IAuraMiningLib(envAddress("external.aura.AuraMiningLib"));
        ohmWstethRewardsPool = IAuraRewardPool(envAddress("external.aura.OhmWstethRewardsPool"));
        ohmLusdRewardsPool = IAuraRewardPool(envAddress("external.aura.OhmLusdRewardsPool"));
        inverseBondDepository = envAddress("olympus.legacy.InverseBondDepository");
        burnerReplacementAuthority = OlympusAuthority(
            envAddress("olympus.legacy.LegacyBurnerReplacementAuthority")
        );
        coolerFactory = CoolerFactory(envAddress("external.cooler.CoolerFactory"));

        // Bophades contracts
        kernel = Kernel(envAddress("olympus.Kernel"));
        // Modules
        PRICE = OlympusPrice(envAddress("olympus.modules.OlympusPriceV2"));
        RANGE = OlympusRange(envAddress("olympus.modules.OlympusRangeV2"));
        TRSRY = OlympusTreasury(envAddress("olympus.modules.OlympusTreasury"));
        MINTR = OlympusMinter(envAddress("olympus.modules.OlympusMinter"));
        INSTR = OlympusInstructions(envAddress("olympus.modules.OlympusInstructions"));
        ROLES = OlympusRoles(envAddress("olympus.modules.OlympusRoles"));
        BLREG = OlympusBoostedLiquidityRegistry(
            envAddress("olympus.modules.OlympusBoostedLiquidityRegistry")
        );
        RGSTY = OlympusContractRegistry(envAddress("olympus.modules.OlympusContractRegistry"));
        // Policies
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
        bridge = CrossChainBridge(envAddress("olympus.policies.CrossChainBridge"));
        lusdVaultManager = BLVaultManagerLusd(envAddress("olympus.policies.BLVaultManagerLusd"));
        lusdVault = BLVaultLusd(envAddress("olympus.policies.BLVaultLusd"));
        legacyBurner = LegacyBurner(envAddress("olympus.policies.LegacyBurner"));
        poly = pOLY(envAddress("olympus.policies.pOLY"));
        claimTransfer = ClaimTransfer(envAddress("olympus.claim.ClaimTransfer"));
        clearinghouse = Clearinghouse(envAddress("olympus.policies.Clearinghouse"));
        yieldRepo = YieldRepurchaseFacility(envAddress("olympus.policies.YieldRepurchaseFacility"));
        contractRegistryAdmin = ContractRegistryAdmin(
            envAddress("olympus.policies.ContractRegistryAdmin")
        );
        loanConsolidator = LoanConsolidator(envAddress("olympus.policies.LoanConsolidator"));

        // Governance
        timelock = Timelock(payable(envAddress("olympus.governance.Timelock")));
        governorBravoDelegator = GovernorBravoDelegator(
            payable(envAddress("olympus.governance.GovernorBravoDelegator"))
        );
        governorBravoDelegate = GovernorBravoDelegate(
            envAddress("olympus.governance.GovernorBravoDelegate")
        );

        // Load deployment data
        string memory data = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(data.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(data.parseRaw(".sequence..name"), (string));
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
        } else {
            // More than one deployment
            string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
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
    }

    function envAddress(string memory key_) internal returns (address) {
        return env.readAddress(string.concat(".current.", chain, ".", key_));
    }

    function deploy(string calldata chain_, string calldata deployFilePath_) external {
        // Setup
        _setUp(chain_, deployFilePath_);

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

        console2.log("   kernel", address(kernel));
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

        // Log heart parameters
        console2.log("OlympusHeart parameters:");
        console2.log("   kernel", address(kernel));
        console2.log("   operator", address(operator));
        console2.log("   zeroDistributor", address(zeroDistributor));
        console2.log("   yieldRepo", address(yieldRepo));
        console2.log("   maxReward", maxReward);
        console2.log("   auctionDuration", auctionDuration);

        // Deploy OlympusHeart policy
        vm.broadcast();
        heart = new OlympusHeart(
            kernel,
            operator,
            zeroDistributor,
            yieldRepo,
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

    function _deployLegacyBurner(bytes memory args) public returns (address) {
        uint256 reward = abi.decode(args, (uint256));

        console2.log("kernel", address(kernel));
        console2.log("ohm", address(ohm));
        console2.log("bondManager", address(bondManager));
        console2.log("inverseBondDepository", inverseBondDepository);
        console2.log("reward", reward / 1e9);

        // Deploy LegacyBurner policy
        vm.broadcast();
        legacyBurner = new LegacyBurner(
            kernel,
            address(ohm),
            address(bondManager),
            inverseBondDepository,
            reward
        );
        console2.log("LegacyBurner deployed at:", address(legacyBurner));

        return address(legacyBurner);
    }

    function _deployReplacementAuthority(bytes memory args) public returns (address) {
        // No additional arguments for ReplacementAuthority policy

        console2.log("legacyBurner", address(legacyBurner));
        console2.log("MINTR", address(MINTR));

        // Deploy ReplacementAuthority policy
        vm.broadcast();
        burnerReplacementAuthority = new OlympusAuthority(
            0x245cc372C84B3645Bf0Ffe6538620B04a217988B,
            0x245cc372C84B3645Bf0Ffe6538620B04a217988B,
            address(legacyBurner),
            address(MINTR)
        );
        console2.log("ReplacementAuthority deployed at:", address(burnerReplacementAuthority));

        return address(burnerReplacementAuthority);
    }

    function _deployPoly(bytes memory args) public returns (address) {
        // Decode arguments for pOLY policy
        (address dao, uint256 maximumAllocated) = abi.decode(args, (address, uint256));

        console2.log("kernel", address(kernel));
        console2.log("previousPoly", address(previousPoly));
        console2.log("previousGenesis", address(previousGenesis));
        console2.log("ohm", address(ohm));
        console2.log("gohm", address(gohm));
        console2.log("reserve", address(reserve));
        console2.log("dao", dao);
        console2.log("maximumAllocated", maximumAllocated);

        // Deploy pOLY policy
        vm.broadcast();
        poly = new pOLY(
            kernel,
            previousPoly,
            previousGenesis,
            address(ohm),
            address(gohm),
            address(reserve),
            dao,
            maximumAllocated
        );
        console2.log("pOLY deployed at:", address(poly));

        return address(poly);
    }

    function _deployClaimTransfer(bytes memory args) public returns (address) {
        // Doesn't need extra args

        console2.log("poly", address(poly));
        console2.log("ohm", address(ohm));
        console2.log("reserve", address(reserve));
        console2.log("gohm", address(gohm));

        // Validate that the addresses are set
        require(address(poly) != address(0), "poly is not set");
        require(address(ohm) != address(0), "ohm is not set");
        require(address(reserve) != address(0), "reserve is not set");
        require(address(gohm) != address(0), "gohm is not set");

        // Deploy ClaimTransfer contract
        vm.broadcast();
        claimTransfer = new ClaimTransfer(
            address(poly),
            address(ohm),
            address(reserve),
            address(gohm)
        );
        console2.log("ClaimTransfer deployed at:", address(claimTransfer));

        return address(claimTransfer);
    }

    function _deployClearinghouse(bytes memory args) public returns (address) {
        if (address(coolerFactory) == address(0)) {
            // Deploy a new Cooler Factory implementation
            vm.broadcast();
            coolerFactory = new CoolerFactory();
            console2.log("Cooler Factory deployed at:", address(coolerFactory));
        } else {
            // Use the input Cooler Factory implmentation
            console2.log("Input Factory Implementation:", address(coolerFactory));
        }

        // Deploy Clearinghouse policy
        vm.broadcast();
        clearinghouse = new Clearinghouse({
            ohm_: address(ohm),
            gohm_: address(gohm),
            staking_: address(staking),
            sdai_: address(wrappedReserve),
            coolerFactory_: address(coolerFactory),
            kernel_: address(kernel)
        });
        console2.log("Clearinghouse deployed at:", address(clearinghouse));

        return address(clearinghouse);
    }

    function _deployClearinghouseRegistry(bytes calldata args) public returns (address) {
        // Necessary to truncate the first word (32 bytes) of args due to a potential bug in the JSON parser.
        address[] memory inactive = abi.decode(args[32:], (address[]));

        // Deploy Clearinghouse Registry module
        vm.broadcast();
        CHREG = new OlympusClearinghouseRegistry(kernel, address(clearinghouse), inactive);
        console2.log("CHREG deployed at:", address(CHREG));

        return address(CHREG);
    }

    function _deployContractRegistry(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Print the arguments
        console2.log("  Kernel:", address(kernel));

        // Deploy OlympusContractRegistry
        vm.broadcast();
        RGSTY = new OlympusContractRegistry(address(kernel));
        console2.log("ContractRegistry deployed at:", address(RGSTY));

        return address(RGSTY);
    }

    function _deployContractRegistryAdmin(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Print the arguments
        console2.log("  Kernel:", address(kernel));

        // Deploy ContractRegistryAdmin
        vm.broadcast();
        contractRegistryAdmin = new ContractRegistryAdmin(address(kernel));
        console2.log("ContractRegistryAdmin deployed at:", address(contractRegistryAdmin));

        return address(contractRegistryAdmin);
    }

    function _deployLoanConsolidator(bytes calldata args_) public returns (address) {
        // Decode arguments from the sequence file
        uint256 feePercentage = abi.decode(args_, (uint256));

        // Print the arguments
        console2.log("  Fee Percentage:", feePercentage);
        console2.log("  Kernel:", address(kernel));

        // Deploy LoanConsolidator
        vm.broadcast();
        loanConsolidator = new LoanConsolidator(address(kernel), feePercentage);
        console2.log("  LoanConsolidator deployed at:", address(loanConsolidator));

        return address(loanConsolidator);
    }

    // ========== GOVERNANCE ========== //

    function _deployTimelock(bytes calldata args) public returns (address) {
        (address admin, uint256 delay) = abi.decode(args, (address, uint256));

        console2.log("Timelock admin:", admin);
        console2.log("Timelock delay:", delay);

        // Deploy Timelock
        vm.broadcast();
        timelock = new Timelock(admin, delay);
        console2.log("Timelock deployed at:", address(timelock));

        return address(timelock);
    }

    function _deployGovernorBravoDelegate(bytes calldata args) public returns (address) {
        // No additional arguments for Governor Bravo Delegate

        // Deploy Governor Bravo Delegate
        vm.broadcast();
        governorBravoDelegate = new GovernorBravoDelegate();
        console2.log("Governor Bravo Delegate deployed at:", address(governorBravoDelegate));

        return address(governorBravoDelegate);
    }

    function _deployGovernorBravoDelegator(bytes calldata args) public returns (address) {
        (
            uint256 activationGracePeriod,
            uint256 proposalThreshold,
            address vetoGuardian,
            uint256 votingDelay,
            uint256 votingPeriod
        ) = abi.decode(args, (uint256, uint256, address, uint256, uint256));

        console2.log("Governor Bravo Delegator vetoGuardian:", vetoGuardian);
        console2.log("Governor Bravo Delegator votingPeriod:", votingPeriod);
        console2.log("Governor Bravo Delegator votingDelay:", votingDelay);
        console2.log("Governor Bravo Delegator activationGracePeriod:", activationGracePeriod);
        console2.log("Governor Bravo Delegator proposalThreshold:", proposalThreshold);

        // Deploy Governor Bravo Delegator
        vm.broadcast();
        governorBravoDelegator = new GovernorBravoDelegator(
            address(timelock),
            address(gohm),
            address(kernel),
            vetoGuardian,
            address(governorBravoDelegate),
            votingPeriod,
            votingDelay,
            activationGracePeriod,
            proposalThreshold
        );
        console2.log("Governor Bravo Delegator deployed at:", address(governorBravoDelegator));

        return address(governorBravoDelegator);
    }

    // ========== YIELD REPURCHASE FACILITY ========== //

    function _deployYieldRepurchaseFacility(bytes calldata args) public returns (address) {
        // No additional arguments for YieldRepurchaseFacility

        // Log dependencies
        console2.log("YieldRepurchaseFacility parameters:");
        console2.log("   kernel", address(kernel));
        console2.log("   ohm", address(ohm));
        console2.log("   reserve", address(reserve));
        console2.log("   wrappedReserve", address(wrappedReserve));
        console2.log("   teller", address(bondFixedTermTeller));
        console2.log("   auctioneer", address(bondAuctioneer));
        console2.log("   clearinghouse", address(clearinghouse));

        // Deploy YieldRepurchaseFacility
        vm.broadcast();
        yieldRepo = new YieldRepurchaseFacility(
            kernel,
            address(ohm),
            address(reserve),
            address(wrappedReserve),
            address(bondFixedTermTeller),
            address(bondAuctioneer),
            address(clearinghouse)
        );

        console2.log("YieldRepurchaseFacility deployed at:", address(yieldRepo));

        return address(yieldRepo);
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
