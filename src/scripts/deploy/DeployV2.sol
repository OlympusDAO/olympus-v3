// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

// Forge
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";

// Chainlink
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";

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
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

// Governance
import {Timelock} from "src/external/governance/Timelock.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";

// Bophades
import {Actions, fromKeycode, Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

// Bophades Modules
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusBoostedLiquidityRegistry} from "modules/BLREG/OlympusBoostedLiquidityRegistry.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusConvertibleDepositPositionManager} from "modules/CDPOS/OlympusConvertibleDepositPositionManager.sol";

// Bophades Policies
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
import {ReserveMigrator} from "policies/ReserveMigrator.sol";
import {EmissionManager} from "policies/EmissionManager.sol";
import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {CoolerLtvOracle} from "policies/cooler/CoolerLtvOracle.sol";
import {CoolerTreasuryBorrower} from "policies/cooler/CoolerTreasuryBorrower.sol";
import {MonoCooler} from "policies/cooler/MonoCooler.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {CoolerComposites} from "src/periphery/CoolerComposites.sol";
import {CoolerV2Migrator} from "src/periphery/CoolerV2Migrator.sol";

import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";
import {MockAuraBooster, MockAuraRewardPool, MockAuraMiningLib, MockAuraVirtualRewardPool, MockAuraStashToken} from "src/test/mocks/AuraMocks.sol";
import {MockBalancerPool, MockVault} from "src/test/mocks/BalancerMocks.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Faucet} from "src/test/mocks/Faucet.sol";
import {LoanConsolidator} from "src/policies/LoanConsolidator.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {SafeCast} from "libraries/SafeCast.sol";

// import {DepositManager} from "policies/DepositManager.sol";
// import {CDAuctioneer} from "policies/CDAuctioneer.sol";
// import {CDFacility} from "policies/CDFacility.sol";

/// @notice Script to deploy and initialize the Olympus system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
// solhint-disable max-states-count
// solhint-disable gas-custom-errors
contract OlympusDeploy is Script {
    using stdJson for string;
    using TransferHelper for ERC20;
    using SafeCast for uint256;
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
    OlympusConvertibleDepositPositionManager public CDPOS;
    OlympusGovDelegation public DLGTE;

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
    YieldRepurchaseFacility public yieldRepo;
    ReserveMigrator public reserveMigrator;
    EmissionManager public emissionManager;
    // CDAuctioneer public cdAuctioneer;
    // CDFacility public cdFacility;
    // DepositManager public cdTokenManager;
    CoolerLtvOracle public coolerV2LtvOracle;
    CoolerTreasuryBorrower public coolerV2TreasuryBorrower;
    MonoCooler public coolerV2;
    CoolerComposites public coolerV2Composites;
    CoolerV2Migrator public coolerV2Migrator;

    /// Other Olympus contracts
    OlympusAuthority public burnerReplacementAuthority;
    DelegateEscrowFactory public delegateEscrowFactory;

    /// Legacy Olympus contracts
    address public inverseBondDepository;
    pOLY public poly;
    Clearinghouse public clearinghouse;

    // Governance
    Timelock public timelock;
    GovernorBravoDelegate public governorBravoDelegate;
    GovernorBravoDelegator public governorBravoDelegator;

    /// Construction variables

    /// Token addresses
    ERC20 public ohm;
    ERC20 public gohm;
    ERC20 public oldReserve;
    ERC4626 public oldSReserve;
    ERC20 public reserve;
    ERC4626 public sReserve;
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
    address public externalMigrator;

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

    /// @notice Stores the contents of the deployment JSON file as a string
    /// @dev    Individual deployment args can be accessed using the _readDeploymentArgString and _readDeploymentArgAddress functions
    string public deploymentFileJson;

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
        // selectorMap["OlympusConvertibleDepositPositionManager"] = this
        //     ._deployConvertibleDepositPositionManager
        //     .selector;
        selectorMap["OlympusGovDelegation"] = this._deployGovDelegation.selector;
        selectorMap["DelegateEscrowFactory"] = this._deployDelegateEscrowFactory.selector;
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
        selectorMap["ReserveMigrator"] = this._deployReserveMigrator.selector;
        selectorMap["EmissionManager"] = this._deployEmissionManager.selector;
        // selectorMap["ConvertibleDepositAuctioneer"] = this
        //     ._deployConvertibleDepositAuctioneer
        //     .selector;
        // selectorMap["ConvertibleDepositFacility"] = this._deployConvertibleDepositFacility.selector;
        // selectorMap["ConvertibleDepositTokenManager"] = this
        //     ._deployConvertibleDepositTokenManager
        //     .selector;

        // Cooler Loans V2
        selectorMap["CoolerV2LtvOracle"] = this._deployCoolerV2LtvOracle.selector;
        selectorMap["CoolerV2TreasuryBorrower"] = this._deployCoolerV2TreasuryBorrower.selector;
        selectorMap["CoolerV2"] = this._deployCoolerV2.selector;
        selectorMap["CoolerV2Composites"] = this._deployCoolerV2Composites.selector;
        selectorMap["CoolerV2Migrator"] = this._deployCoolerV2Migrator.selector;

        // Governance
        selectorMap["Timelock"] = this._deployTimelock.selector;
        selectorMap["GovernorBravoDelegator"] = this._deployGovernorBravoDelegator.selector;
        selectorMap["GovernorBravoDelegate"] = this._deployGovernorBravoDelegate.selector;

        // Load environment addresses
        env = vm.readFile("./src/scripts/env.json");

        // Non-bophades contracts
        ohm = ERC20(envAddress("olympus.legacy.OHM"));
        gohm = ERC20(envAddress("olympus.legacy.gOHM"));
        reserve = ERC20(envAddress("external.tokens.USDS"));
        sReserve = ERC4626(envAddress("external.tokens.sUSDS"));
        oldReserve = ERC20(envAddress("external.tokens.DAI"));
        oldSReserve = ERC4626(envAddress("external.tokens.sDAI"));
        wsteth = ERC20(envAddress("external.tokens.WSTETH"));
        aura = ERC20(envAddress("external.tokens.AURA"));
        bal = ERC20(envAddress("external.tokens.BAL"));
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
        externalMigrator = envAddress("external.maker.daiUsdsMigrator");

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
        DLGTE = OlympusGovDelegation(envAddress("olympus.modules.OlympusGovDelegation"));
        delegateEscrowFactory = DelegateEscrowFactory(
            envAddress("olympus.periphery.DelegateEscrowFactory")
        );
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
        reserveMigrator = ReserveMigrator(envAddress("olympus.policies.ReserveMigrator"));
        emissionManager = EmissionManager(envAddress("olympus.policies.EmissionManager"));
        // cdAuctioneer = CDAuctioneer(envAddress("olympus.policies.ConvertibleDepositAuctioneer"));
        // cdFacility = CDFacility(envAddress("olympus.policies.ConvertibleDepositFacility"));
        // cdTokenManager = DepositManager(
        //     envAddress("olympus.policies.ConvertibleDepositTokenManager")
        // );

        // Cooler Loans V2
        coolerV2LtvOracle = CoolerLtvOracle(envAddress("olympus.policies.CoolerV2LtvOracle"));
        coolerV2TreasuryBorrower = CoolerTreasuryBorrower(
            envAddress("olympus.policies.CoolerV2TreasuryBorrower")
        );
        coolerV2 = MonoCooler(envAddress("olympus.policies.CoolerV2"));

        // Governance
        timelock = Timelock(payable(envAddress("olympus.governance.Timelock")));
        governorBravoDelegator = GovernorBravoDelegator(
            payable(envAddress("olympus.governance.GovernorBravoDelegator"))
        );
        governorBravoDelegate = GovernorBravoDelegate(
            envAddress("olympus.governance.GovernorBravoDelegate")
        );

        // Load deployment data
        deploymentFileJson = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(deploymentFileJson.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(
                deploymentFileJson.parseRaw(".sequence..name"),
                (string)
            );
            deployments.push(name);
            console2.log("Deploying", name);
            // Parse and store args if not kernel
            // Note: constructor args need to be provided in alphabetical order
            // due to changes with forge-std or a struct needs to be used
            if (keccak256(bytes(name)) != keccak256(bytes("Kernel"))) {
                argsMap[name] = deploymentFileJson.parseRaw(
                    string.concat(".sequence[?(@.name == '", name, "')].args")
                );
            }
        } else {
            // More than one deployment
            string[] memory names = abi.decode(
                deploymentFileJson.parseRaw(".sequence..name"),
                (string[])
            );
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);
                console2.log("Deploying", name);

                // Parse and store args if not kernel
                // Note: constructor args need to be provided in alphabetical order
                // due to changes with forge-std or a struct needs to be used
                if (keccak256(bytes(name)) != keccak256(bytes("Kernel"))) {
                    argsMap[name] = deploymentFileJson.parseRaw(
                        string.concat(".sequence[?(@.name == '", name, "')].args")
                    );
                }
            }
        }
    }

    function envAddress(string memory key_) internal view returns (address) {
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

    function _deployTreasury(bytes memory) public returns (address) {
        // No additional arguments for Treasury module

        // Deploy Treasury module
        vm.broadcast();
        TRSRY = new OlympusTreasury(kernel);
        console2.log("Treasury deployed at:", address(TRSRY));

        return address(TRSRY);
    }

    function _deployMinter(bytes memory) public returns (address) {
        // Only args are contracts in the environment

        // Deploy Minter module
        vm.broadcast();
        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("Minter deployed at:", address(MINTR));

        return address(MINTR);
    }

    function _deployRoles(bytes memory) public returns (address) {
        // No additional arguments for Roles module

        // Deploy Roles module
        vm.broadcast();
        ROLES = new OlympusRoles(kernel);
        console2.log("Roles deployed at:", address(ROLES));

        return address(ROLES);
    }

    function _deployBoostedLiquidityRegistry(bytes memory) public returns (address) {
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
        console2.log("   sReserve", address(sReserve));
        console2.log("   oldReserve", address(oldReserve));
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
            [address(ohm), address(reserve), address(sReserve), address(oldReserve)],
            configParams
        );
        console2.log("Operator deployed at:", address(operator));

        return address(operator);
    }

    function _deployBondCallback(bytes memory) public returns (address) {
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
        console2.log("   reserveMigrator", address(reserveMigrator));
        console2.log("   emissionManager", address(emissionManager));
        console2.log("   maxReward", maxReward);
        console2.log("   auctionDuration", auctionDuration);

        // Deploy OlympusHeart policy
        vm.broadcast();
        heart = new OlympusHeart(
            kernel,
            operator,
            zeroDistributor,
            yieldRepo,
            reserveMigrator,
            emissionManager,
            maxReward,
            auctionDuration
        );
        console2.log("OlympusHeart deployed at:", address(heart));

        return address(heart);
    }

    function _deployPriceConfig(bytes memory) public returns (address) {
        // No additional arguments for PriceConfig policy

        // Deploy PriceConfig policy
        vm.broadcast();
        priceConfig = new OlympusPriceConfig(kernel);
        console2.log("PriceConfig deployed at:", address(priceConfig));

        return address(priceConfig);
    }

    function _deployRolesAdmin(bytes memory) public returns (address) {
        // No additional arguments for RolesAdmin policy

        // Deploy RolesAdmin policy
        vm.broadcast();
        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        return address(rolesAdmin);
    }

    function _deployTreasuryCustodian(bytes memory) public returns (address) {
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

    function _deployZeroDistributor(bytes memory) public returns (address) {
        // Validate that staking is deployed
        require(address(staking) != address(0), "Staking not deployed");

        // Deploy ZeroDistributor policy
        vm.broadcast();
        zeroDistributor = new ZeroDistributor(staking);
        console2.log("ZeroDistributor deployed at:", address(zeroDistributor));

        return address(zeroDistributor);
    }

    function _deployEmergency(bytes memory) public returns (address) {
        // No additional arguments for Emergency policy

        // Deploy Emergency policy
        vm.broadcast();
        emergency = new Emergency(kernel);
        console2.log("Emergency deployed at:", address(emergency));

        return address(emergency);
    }

    function _deployBondManager(bytes memory) public returns (address) {
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

    function _deployBurner(bytes memory) public returns (address) {
        // No additional arguments for Burner policy

        // Deploy Burner policy
        vm.broadcast();
        burner = new Burner(kernel, ohm);
        console2.log("Burner deployed at:", address(burner));

        return address(burner);
    }

    function _deployBLVaultLido(bytes memory) public returns (address) {
        // No additional arguments for BLVaultLido policy

        // Deploy BLVaultLido policy
        vm.broadcast();
        lidoVault = new BLVaultLido();
        console2.log("BLVaultLido deployed at:", address(lidoVault));

        return address(lidoVault);
    }

    // deploy.json was not being parsed correctly, so I had to hardcode most of the deployment arguments
    function _deployBLVaultManagerLido(bytes memory) public returns (address) {
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

    function _deployBLVaultLusd(bytes memory) public returns (address) {
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

    function _deployReplacementAuthority(bytes memory) public returns (address) {
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

    function _deployClaimTransfer(bytes memory) public returns (address) {
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

    function _deployClearinghouse(bytes memory) public returns (address) {
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
            sReserve_: address(sReserve),
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

    // ========== COOLER LOANS V2 ========== //

    function _deployDelegateEscrowFactory(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Dependencies
        require(address(gohm) != address(0), "gohm is not set");

        // Print the arguments
        console2.log("  gOHM:", address(gohm));

        // Deploy DelegateEscrowFactory
        vm.broadcast();
        delegateEscrowFactory = new DelegateEscrowFactory(address(gohm));
        console2.log("DelegateEscrowFactory deployed at:", address(delegateEscrowFactory));

        return address(delegateEscrowFactory);
    }

    function _deployGovDelegation(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Dependencies
        require(address(kernel) != address(0), "kernel is not set");
        require(address(gohm) != address(0), "gohm is not set");
        require(address(delegateEscrowFactory) != address(0), "delegateEscrowFactory is not set");

        // Print the arguments
        console2.log("  Kernel:", address(kernel));
        console2.log("  gOHM:", address(gohm));
        console2.log("  DelegateEscrowFactory:", address(delegateEscrowFactory));

        // Deploy OlympusGovDelegation
        vm.broadcast();
        DLGTE = new OlympusGovDelegation(kernel, address(gohm), delegateEscrowFactory);
        console2.log("OlympusGovDelegation deployed at:", address(DLGTE));

        return address(DLGTE);
    }

    function _deployCoolerV2LtvOracle(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        uint96 initialOriginationLtv = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "initialOriginationLtv"
        ).encodeUInt96();
        uint96 maxOriginationLtvDelta = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "maxOriginationLtvDelta"
        ).encodeUInt96();
        uint32 minOriginationLtvTargetTimeDelta = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "minOriginationLtvTargetTimeDelta"
        ).encodeUInt32();
        uint96 maxOriginationLtvRateOfChange = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "maxOriginationLtvRateOfChange"
        ).encodeUInt96();
        uint16 maxLiquidationLtvPremiumBps = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "maxLiquidationLtvPremiumBps"
        ).encodeUInt16();
        uint16 liquidationLtvPremiumBps = _readDeploymentArgUint256(
            "CoolerV2LtvOracle",
            "liquidationLtvPremiumBps"
        ).encodeUInt16();

        // Dependencies
        require(address(kernel) != address(0), "kernel is not set");
        require(address(gohm) != address(0), "gohm is not set");
        require(address(reserve) != address(0), "reserve is not set");
        require(initialOriginationLtv > 0, "initialOriginationLtv is not set");
        require(maxOriginationLtvDelta > 0, "maxOriginationLtvDelta is not set");
        require(
            minOriginationLtvTargetTimeDelta > 0,
            "minOriginationLtvTargetTimeDelta is not set"
        );
        require(maxOriginationLtvRateOfChange > 0, "maxOriginationLtvRateOfChange is not set");
        require(maxLiquidationLtvPremiumBps > 0, "maxLiquidationLtvPremiumBps is not set");
        require(liquidationLtvPremiumBps > 0, "liquidationLtvPremiumBps is not set");

        // Print the arguments
        console2.log("  Kernel:", address(kernel));
        console2.log("  gOHM:", address(gohm));
        console2.log("  Reserve:", address(reserve));
        console2.log("  Initial Origination LTV:", initialOriginationLtv);
        console2.log("  Max Origination LTV Delta:", maxOriginationLtvDelta);
        console2.log("  Min Origination LTV Target Time Delta:", minOriginationLtvTargetTimeDelta);
        console2.log("  Max Origination LTV Rate Of Change:", maxOriginationLtvRateOfChange);
        console2.log("  Max Liquidation LTV Premium Bps:", maxLiquidationLtvPremiumBps);
        console2.log("  Liquidation LTV Premium Bps:", liquidationLtvPremiumBps);

        // Deploy CoolerLtvOracle
        vm.broadcast();
        coolerV2LtvOracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(reserve),
            initialOriginationLtv,
            maxOriginationLtvDelta,
            minOriginationLtvTargetTimeDelta,
            maxOriginationLtvRateOfChange,
            maxLiquidationLtvPremiumBps,
            liquidationLtvPremiumBps
        );
        console2.log("CoolerLtvOracle deployed at:", address(coolerV2LtvOracle));

        return address(coolerV2LtvOracle);
    }

    function _deployCoolerV2TreasuryBorrower(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Dependencies
        require(address(kernel) != address(0), "kernel is not set");
        require(address(sReserve) != address(0), "sReserve is not set");

        // Print the arguments
        console2.log("  Kernel:", address(kernel));
        console2.log("  sReserve:", address(sReserve));

        // Deploy CoolerV2TreasuryBorrower
        vm.broadcast();
        coolerV2TreasuryBorrower = new CoolerTreasuryBorrower(address(kernel), address(sReserve));
        console2.log("CoolerV2TreasuryBorrower deployed at:", address(coolerV2TreasuryBorrower));

        return address(coolerV2TreasuryBorrower);
    }

    function _deployCoolerV2(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        uint96 interestRateWad = _readDeploymentArgUint256("CoolerV2", "interestRateWad")
            .encodeUInt96();
        uint256 minDebtRequired = _readDeploymentArgUint256("CoolerV2", "minDebtRequired");

        // Dependencies
        require(address(ohm) != address(0), "ohm is not set");
        require(address(gohm) != address(0), "gohm is not set");
        require(address(staking) != address(0), "staking is not set");
        require(address(kernel) != address(0), "kernel is not set");
        require(address(coolerV2LtvOracle) != address(0), "coolerV2LtvOracle is not set");
        require(interestRateWad > 0, "interestRateWad is not set");
        require(minDebtRequired > 0, "minDebtRequired is not set");

        // Print the arguments
        console2.log("  OHM:", address(ohm));
        console2.log("  gOHM:", address(gohm));
        console2.log("  Staking:", address(staking));
        console2.log("  Kernel:", address(kernel));
        console2.log("  CoolerV2LtvOracle:", address(coolerV2LtvOracle));
        console2.log("  Interest Rate Wad:", interestRateWad);
        console2.log("  Min Debt Required:", minDebtRequired);

        // Deploy CoolerV2
        vm.broadcast();
        coolerV2 = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(kernel),
            address(coolerV2LtvOracle),
            interestRateWad,
            minDebtRequired
        );
        console2.log("CoolerV2 deployed at:", address(coolerV2));

        // Next steps:
        // - Execute the governance proposal to activate the Cooler V2 contracts. This should also set the treasury borrower.

        return address(coolerV2);
    }

    function _deployCoolerV2Composites(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        // Dependencies
        require(address(coolerV2) != address(0), "coolerV2 is not set");
        address owner = envAddress("olympus.multisig.dao");

        // Print the arguments
        console2.log("  CoolerV2:", address(coolerV2));
        console2.log("  Owner:", owner);

        // Deploy CoolerV2Composites
        vm.broadcast();
        coolerV2Composites = new CoolerComposites(coolerV2, owner);
        console2.log("CoolerV2Composites deployed at:", address(coolerV2Composites));

        return address(coolerV2Composites);
    }

    function _deployCoolerV2Migrator(bytes calldata) public returns (address) {
        // Decode arguments from the sequence file
        // None

        address daoMS = envAddress("olympus.multisig.dao");
        address flashLender = envAddress("external.maker.flash");
        CHREG = OlympusClearinghouseRegistry(
            envAddress("olympus.modules.OlympusClearinghouseRegistry")
        );

        // Dependencies
        require(address(daoMS) != address(0), "daoMS is not set");
        require(address(coolerV2) != address(0), "coolerV2 is not set");
        require(address(reserve) != address(0), "reserve is not set");
        require(address(sReserve) != address(0), "sReserve is not set");
        require(address(gohm) != address(0), "gohm is not set");
        require(address(externalMigrator) != address(0), "externalMigrator is not set");
        require(address(flashLender) != address(0), "flashLender is not set");
        require(address(CHREG) != address(0), "CHREG is not set");
        require(address(coolerFactory) != address(0), "coolerFactory is not set");

        // Print the arguments
        console2.log("  DAO MS:", address(daoMS));
        console2.log("  CoolerV2:", address(coolerV2));
        console2.log("  Reserve:", address(reserve));
        console2.log("  sReserve:", address(sReserve));
        console2.log("  gOHM:", address(gohm));
        console2.log("  DAI-USDS Migrator:", address(externalMigrator));
        console2.log("  Flash:", address(flashLender));
        console2.log("  CHREG:", address(CHREG));
        console2.log("  CoolerFactory:", address(coolerFactory));

        // Deploy CoolerV2Migrator
        address[] memory coolerFactories = new address[](1);
        coolerFactories[0] = address(coolerFactory);

        vm.broadcast();
        coolerV2Migrator = new CoolerV2Migrator(
            address(daoMS),
            address(coolerV2),
            address(oldReserve),
            address(reserve),
            address(gohm),
            address(externalMigrator),
            address(flashLender),
            address(CHREG),
            coolerFactories
        );
        console2.log("CoolerV2Migrator deployed at:", address(coolerV2Migrator));

        return address(coolerV2Migrator);
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

    function _deployGovernorBravoDelegate(bytes calldata) public returns (address) {
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

    function _deployYieldRepurchaseFacility(bytes calldata) public returns (address) {
        // No additional arguments for YieldRepurchaseFacility

        // Log dependencies
        console2.log("YieldRepurchaseFacility parameters:");
        console2.log("   kernel", address(kernel));
        console2.log("   ohm", address(ohm));
        console2.log("   sReserve", address(sReserve));
        console2.log("   teller", address(bondFixedTermTeller));
        console2.log("   auctioneer", address(bondAuctioneer));

        // Deploy YieldRepurchaseFacility
        vm.broadcast();
        yieldRepo = new YieldRepurchaseFacility(
            kernel,
            address(ohm),
            address(sReserve),
            address(bondFixedTermTeller),
            address(bondAuctioneer)
        );

        console2.log("YieldRepurchaseFacility deployed at:", address(yieldRepo));

        return address(yieldRepo);
    }

    // ========== RESERVE MIGRATION ========== //

    function _deployReserveMigrator(bytes calldata) public returns (address) {
        // No additional arguments for ReserveMigrator

        // Log dependencies
        console2.log("ReserveMigrator parameters:");
        console2.log("   kernel", address(kernel));
        console2.log("   sFrom", address(oldSReserve));
        console2.log("   sTo", address(sReserve));
        console2.log("   migrator", address(externalMigrator));

        // Deploy ReserveMigrator
        vm.broadcast();
        reserveMigrator = new ReserveMigrator(
            kernel,
            address(oldSReserve),
            address(sReserve),
            address(externalMigrator)
        );

        console2.log("ReserveMigrator deployed at:", address(reserveMigrator));

        return address(reserveMigrator);
    }

    // ========== EMISSION MANAGER ========== //

    function _deployEmissionManager(bytes calldata) public returns (address) {
        // No additional arguments for EmissionManager

        address cdAuctioneer = address(0); // TODO: Add cdAuctioneer

        // Log dependencies
        console2.log("EmissionManager parameters:");
        console2.log("   kernel", address(kernel));
        console2.log("   ohm", address(ohm));
        console2.log("   gohm", address(gohm));
        console2.log("   reserve", address(reserve));
        console2.log("   sReserve", address(sReserve));
        console2.log("   bondAuctioneer", address(bondAuctioneer));
        console2.log("   cdAuctioneer", address(cdAuctioneer));
        console2.log("   teller", address(bondFixedTermTeller));

        // Deploy EmissionManager
        vm.broadcast();
        emissionManager = new EmissionManager(
            kernel,
            address(ohm),
            address(gohm),
            address(reserve),
            address(sReserve),
            address(bondAuctioneer),
            address(cdAuctioneer),
            address(bondFixedTermTeller)
        );

        console2.log("EmissionManager deployed at:", address(emissionManager));

        return address(emissionManager);
    }

    // ========== CONVERTIBLE DEPOSIT ========== //

    // function _deployConvertibleDepositPositionManager(bytes calldata) public returns (address) {
    //     // No additional arguments for ConvertibleDepositPositionManager

    //     // Log dependencies
    //     console2.log("ConvertibleDepositPositionManager parameters:");
    //     console2.log("   kernel", address(kernel));

    //     // Deploy ConvertibleDepositPositionManager
    //     vm.broadcast();
    //     CDPOS = new OlympusConvertibleDepositPositionManager(address(kernel));
    //     console2.log("ConvertibleDepositPositionManager deployed at:", address(CDPOS));

    //     return address(CDPOS);
    // }

    // function _deployConvertibleDepositTokenManager(bytes calldata) public returns (address) {
    //     // No additional arguments for ConvertibleDepositTokenManager

    //     // Log dependencies
    //     console2.log("ConvertibleDepositTokenManager parameters:");
    //     console2.log("   kernel", address(kernel));

    //     // Deploy ConvertibleDepositTokenManager
    //     vm.broadcast();
    //     cdTokenManager = new DepositManager(address(kernel));
    //     console2.log("ConvertibleDepositTokenManager deployed at:", address(cdTokenManager));

    //     return address(cdTokenManager);
    // }

    // function _deployConvertibleDepositAuctioneer(bytes calldata args_) public returns (address) {
    //     // No additional arguments for ConvertibleDepositAuctioneer
    //     uint8 depositPeriodMonths = abi.decode(args_, (uint8));

    //     // Log dependencies
    //     console2.log("ConvertibleDepositAuctioneer parameters:");
    //     console2.log("   kernel", address(kernel));
    //     console2.log("   cdFacility", address(cdFacility));
    //     console2.log("   reserveToken", address(reserve));
    //     console2.log("   depositPeriodMonths", depositPeriodMonths);

    //     // Deploy ConvertibleDepositAuctioneer
    //     vm.broadcast();
    //     cdAuctioneer = new CDAuctioneer(
    //         address(kernel),
    //         address(cdFacility),
    //         address(reserve),
    //         depositPeriodMonths
    //     );
    //     console2.log("ConvertibleDepositAuctioneer deployed at:", address(cdAuctioneer));

    //     return address(cdAuctioneer);
    // }

    // function _deployConvertibleDepositFacility(bytes calldata) public returns (address) {
    //     // No additional arguments for ConvertibleDepositFacility

    //     // Log dependencies
    //     console2.log("ConvertibleDepositFacility parameters:");
    //     console2.log("   kernel", address(kernel));
    //     console2.log("   cdTokenManager", address(cdTokenManager));

    //     // Deploy ConvertibleDepositFacility
    //     vm.broadcast();
    //     cdFacility = new CDFacility(address(kernel), address(cdTokenManager));
    //     console2.log("ConvertibleDepositFacility deployed at:", address(cdFacility));

    //     return address(cdFacility);
    // }

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
        require(ROLES.hasRole(address(heart), "heart"));
        require(ROLES.hasRole(guardian_, "heart"));
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
        require(ROLES.hasRole(address(heart), "heart"));
        require(ROLES.hasRole(guardian_, "heart"));
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
        // solhint-disable quotes
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
        // solhint-enable quotes
        vm.writeLine(file, "}");
    }

    function _readDeploymentArgString(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (string memory) {
        return
            deploymentFileJson.readString(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgBytes32(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (bytes32) {
        return
            deploymentFileJson.readBytes32(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgAddress(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (address) {
        return
            deploymentFileJson.readAddress(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgUint256(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (uint256) {
        return
            deploymentFileJson.readUint(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
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
