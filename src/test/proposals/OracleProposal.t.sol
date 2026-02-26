// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Kernel, Actions, Policy, Module, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules, Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {console2} from "forge-std/console2.sol";

// PRICE imports
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// PRICE Submodules
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";
import {UniswapV3Price} from "src/modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {ERC4626Price} from "src/modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// External interfaces
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core-1.0.1/interfaces/IUniswapV3Pool.sol";

// Oracle policies
import {ERC7726Oracle} from "src/policies/price/ERC7726Oracle.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {ChainlinkOracleFactory} from "src/policies/price/ChainlinkOracleFactory.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";

// Oracle Proposal
import {OracleProposal} from "src/proposals/OracleProposal.sol";

// Role and access control imports
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {ADMIN_ROLE, ORACLE_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @notice Test contract for Oracle Proposal: Enable Oracle Policies and Deploy OHM/USDS Oracles
/// @dev    Simulates the proposal after the PRICE system has been deployed
contract OracleProposalTest is ProposalTest {
    Kernel public kernel;

    // Block to fork from (after DAO MS deployment, before OCG proposal)
    // TODO: Update to the block after the DAO MS deployment
    uint48 public constant FORK_BLOCK = 24413007 + 1;

    // Price validation bounds (18 decimals)
    // TODO adjust the price bounds when updating the fork block
    uint256 internal constant OHM_MIN_PRICE = 17e18;
    uint256 internal constant OHM_MAX_PRICE = 18e18;

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        vm.createSelectFork(_RPC_ALIAS, FORK_BLOCK);

        /// @dev Deploy your proposal
        OracleProposal proposal = new OracleProposal();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        _setupSuite(address(proposal));
        kernel = Kernel(addresses.getAddress("olympus-kernel"));

        // Deploy and configure PRICE v1.2 system if not already done
        _deployPriceSystem();

        // Set debug mode
        suite.setDebug(true);

        // Simulate the proposal
        _simulateProposal();
    }

    /// @notice Deploys and configures the PRICE v1.2 system
    /// @dev    Simulates the DAO MS batch deployment that should happen before the OCG proposal
    function _deployPriceSystem() internal {
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address kernelAddr = addresses.getAddress("olympus-kernel");

        vm.startPrank(daoMS);

        // 1. Deploy PRICE v1_2 module if not already installed
        address priceModule = address(kernel.getModuleForKeycode(toKeycode("PRICE")));
        (uint8 priceMajor, uint8 priceMinor) = Module(priceModule).VERSION();
        bool needsPriceUpgrade = (priceModule == address(0)) ||
            (priceMajor != 1) ||
            (priceMinor < 2);

        if (needsPriceUpgrade) {
            console2.log("Deploying PRICE v1.2 module");
            OlympusPricev1_2 price = new OlympusPricev1_2(
                Kernel(kernelAddr),
                ohm,
                28800, // observationFrequency (8 hours)
                12280000000000000000 // minimumTargetPrice
            );
            addresses.addAddress("olympus-module-price-1_2", address(price));
            vm.label(address(price), "olympus-module-price-1_2");

            // Upgrade PRICE module
            kernel.executeAction(Actions.UpgradeModule, address(price));
        } else {
            console2.log("PRICE v1.2 module already installed");
            // Validate that the addresses file has the correct address for the PRICE module
            require(
                addresses.getAddress("olympus-module-price-1_2") == priceModule,
                "PRICE module address mismatch"
            );
        }

        // Get the PRICE module address
        priceModule = _safeGetAddress("olympus-module-price-1_2");

        // 2. Deploy PRICE submodules
        _deployChainlinkPriceFeedsIfNeeded(priceModule);
        _deployPythPriceFeedsIfNeeded(priceModule);
        _deployUniswapV3PriceIfNeeded(priceModule);
        _deployErc4626PriceIfNeeded(priceModule);
        _deploySimplePriceFeedStrategyIfNeeded(priceModule);

        // 3. Deploy PriceConfigv2 policy if not already installed
        address priceConfig = _safeGetAddress("olympus-policy-price-config-2_0");
        if (priceConfig == address(0) || !Policy(priceConfig).isActive()) {
            console2.log("Deploying PriceConfigv2");
            PriceConfigv2 config = new PriceConfigv2(Kernel(kernelAddr));
            addresses.addAddress("olympus-policy-price-config-2_0", address(config));

            // Activate the policy
            kernel.executeAction(Actions.ActivatePolicy, address(config));
        } else {
            console2.log("PriceConfigv2 already active");
            addresses.addAddress("olympus-policy-price-config-2_0", priceConfig);
        }

        // 4. Deploy and activate oracle policies so their dependencies are configured
        // (The OCG proposal will enable() them later to turn on functionality)
        _deployERC7726OracleIfNeeded(kernelAddr);
        _deployChainlinkOracleFactoryIfNeeded(kernelAddr);
        _deployMorphoOracleFactoryIfNeeded(kernelAddr);
        _activateOraclePoliciesIfNeeded();

        vm.stopPrank();

        // 5. Configure PRICE assets (simplified - in production use ConfigurePriceV1_2 batch)
        _configurePriceAssets();
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Safely get an address from addresses.json, returning address(0) if not found
    function _safeGetAddress(string memory key_) internal view returns (address) {
        try addresses.getAddress(key_) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    // ========== SUBMODULE DEPLOYMENT ========== //

    function _deployChainlinkPriceFeedsIfNeeded(address priceModule_) internal {
        string memory key = "olympus-submodule-price-chainlink-price-feeds-1_0";
        address submodule = _safeGetAddress(key);
        if (submodule == address(0)) {
            console2.log("Deploying ChainlinkPriceFeeds");
            submodule = address(new ChainlinkPriceFeeds(Module(priceModule_)));
            addresses.addAddress(key, submodule);
        } else {
            console2.log("ChainlinkPriceFeeds already deployed");
        }

        vm.label(submodule, key);
    }

    function _deployPythPriceFeedsIfNeeded(address priceModule_) internal {
        string memory key = "olympus-submodule-price-pyth-price-feeds-1_0";
        address submodule = _safeGetAddress(key);
        if (submodule == address(0)) {
            console2.log("Deploying PythPriceFeeds");
            submodule = address(new PythPriceFeeds(Module(priceModule_)));
            addresses.addAddress(key, submodule);
        } else {
            console2.log("PythPriceFeeds already deployed");
        }

        vm.label(submodule, key);
    }

    function _deployUniswapV3PriceIfNeeded(address priceModule_) internal {
        string memory key = "olympus-submodule-price-uniswap-v3-1_0";
        address submodule = _safeGetAddress(key);
        if (submodule == address(0)) {
            console2.log("Deploying UniswapV3Price");
            submodule = address(new UniswapV3Price(Module(priceModule_)));
            addresses.addAddress(key, submodule);
        } else {
            console2.log("UniswapV3Price already deployed");
        }

        vm.label(submodule, key);
    }

    function _deployErc4626PriceIfNeeded(address priceModule_) internal {
        string memory key = "olympus-submodule-price-erc4626-1_0";
        address submodule = _safeGetAddress(key);
        if (submodule == address(0)) {
            console2.log("Deploying ERC4626Price");
            submodule = address(new ERC4626Price(Module(priceModule_)));
            addresses.addAddress(key, submodule);
        } else {
            console2.log("ERC4626Price already deployed");
        }

        vm.label(submodule, key);
    }

    function _deploySimplePriceFeedStrategyIfNeeded(address priceModule_) internal {
        string memory key = "olympus-submodule-price-simple-price-feed-strategy-1_0";
        address submodule = _safeGetAddress(key);
        if (submodule == address(0)) {
            console2.log("Deploying SimplePriceFeedStrategy");
            submodule = address(new SimplePriceFeedStrategy(Module(priceModule_)));
            addresses.addAddress(key, submodule);
        } else {
            console2.log("SimplePriceFeedStrategy already deployed");
        }

        vm.label(submodule, key);
    }

    // ========== POLICY DEPLOYMENT ========== //

    function _deployERC7726OracleIfNeeded(address kernelAddr_) internal {
        string memory key = "olympus-policy-erc7726-oracle-1_0";
        address policy = _safeGetAddress(key);
        if (policy == address(0)) {
            console2.log("Deploying ERC7726Oracle");
            policy = address(new ERC7726Oracle(Kernel(kernelAddr_)));
            addresses.addAddress(key, policy);
        } else {
            console2.log("ERC7726Oracle already deployed");
        }

        vm.label(policy, key);
    }

    function _deployChainlinkOracleFactoryIfNeeded(address kernelAddr_) internal {
        string memory key = "olympus-policy-chainlink-oracle-factory-1_0";
        address policy = _safeGetAddress(key);
        if (policy == address(0)) {
            console2.log("Deploying ChainlinkOracleFactory");
            policy = address(new ChainlinkOracleFactory(Kernel(kernelAddr_)));
            addresses.addAddress(key, policy);
        } else {
            console2.log("ChainlinkOracleFactory already deployed");
        }

        vm.label(policy, key);
    }

    function _deployMorphoOracleFactoryIfNeeded(address kernelAddr_) internal {
        string memory key = "olympus-policy-morpho-oracle-factory-1_0";
        address policy = _safeGetAddress(key);
        if (policy == address(0)) {
            console2.log("Deploying MorphoOracleFactory");
            policy = address(new MorphoOracleFactory(Kernel(kernelAddr_)));
            addresses.addAddress(key, policy);
        } else {
            console2.log("MorphoOracleFactory already deployed");
        }

        vm.label(policy, key);
    }

    /// @notice Activate oracle policies if not already active
    function _activateOraclePoliciesIfNeeded() internal {
        address erc7726Oracle = addresses.getAddress("olympus-policy-erc7726-oracle-1_0");
        address chainlinkFactory = addresses.getAddress(
            "olympus-policy-chainlink-oracle-factory-1_0"
        );
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");
        Kernel kernelAddr = Kernel(addresses.getAddress("olympus-kernel"));

        // Activate ERC7726Oracle if deployed but not active
        if (!Policy(erc7726Oracle).isActive()) {
            console2.log("Activating ERC7726Oracle");
            kernelAddr.executeAction(Actions.ActivatePolicy, erc7726Oracle);
        }

        // Activate ChainlinkOracleFactory if deployed but not active
        if (!Policy(chainlinkFactory).isActive()) {
            console2.log("Activating ChainlinkOracleFactory");
            kernelAddr.executeAction(Actions.ActivatePolicy, chainlinkFactory);
        }

        // Activate MorphoOracleFactory if deployed but not active
        if (!Policy(morphoFactory).isActive()) {
            console2.log("Activating MorphoOracleFactory");
            kernelAddr.executeAction(Actions.ActivatePolicy, morphoFactory);
        }
    }

    // ========== ASSET CONFIGURATION ========== //

    /// @notice Configure PRICE assets with mock price feeds for testing
    /// @dev    This is a simplified version of ConfigurePriceV1_2
    ///         In production, the DAO MS batch script handles this
    function _configurePriceAssets() internal {
        address priceConfig = addresses.getAddress("olympus-policy-price-config-2_0");
        address priceModule = addresses.getAddress("olympus-module-price-1_2");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");
        address susds = addresses.getAddress("external-tokens-susds");

        // Check if OHM is already configured (if so, all assets should be configured)
        if (IPRICEv2(priceModule).isAssetApproved(ohm)) {
            console2.log("OHM asset already configured, skipping asset configuration");
            return;
        }

        console2.log("Configuring PRICE assets");

        // Install submodules (skip if already installed)
        _installSubmoduleIfNeeded(priceConfig, "olympus-submodule-price-chainlink-price-feeds-1_0");
        _installSubmoduleIfNeeded(priceConfig, "olympus-submodule-price-pyth-price-feeds-1_0");
        _installSubmoduleIfNeeded(priceConfig, "olympus-submodule-price-uniswap-v3-1_0");
        _installSubmoduleIfNeeded(priceConfig, "olympus-submodule-price-erc4626-1_0");
        _installSubmoduleIfNeeded(
            priceConfig,
            "olympus-submodule-price-simple-price-feed-strategy-1_0"
        );

        // Configure USDS with a simple Chainlink feed
        _configureUSDS(priceConfig, usds);

        // Configure sUSDS using ERC4626 (derives from USDS)
        _configureSusds(priceConfig, susds);

        // Configure OHM with OHM/sUSDS Uniswap V3 pool
        _configureOHM(priceConfig, ohm);
    }

    /// @notice Configure USDS asset with Chainlink feed
    function _configureUSDS(address priceConfig_, address usds_) internal {
        console2.log("Configuring USDS asset");

        // USDS/USD Chainlink feed
        address chainlinkUsdsUsd = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
        vm.label(chainlinkUsdsUsd, "chainlinkUsdsUsd");

        // Create strategy component: empty (single price feed)
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode(""),
            selector: bytes4(0),
            params: abi.encode("")
        });

        // Create feed component using Chainlink
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(chainlinkUsdsUsd),
                    updateThreshold: 3 * 86400 // 3 days (relaxed for testing)
                })
            )
        });

        // Add USDS asset via PriceConfig
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        vm.startPrank(daoMS);
        PriceConfigv2(priceConfig_).addAssetPrice(
            usds_,
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            strategy,
            feeds
        );
        vm.stopPrank();

        console2.log("USDS asset configured");
    }

    /// @notice Configure sUSDS asset using ERC4626 (derives price from USDS)
    function _configureSusds(address priceConfig_, address susds_) internal {
        console2.log("Configuring sUSDS asset");

        // Create strategy component: empty (single price feed)
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode(""),
            selector: bytes4(0),
            params: abi.encode("")
        });

        // Create feed component using ERC4626
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.ERC4626"),
            selector: ERC4626Price.getPriceFromUnderlying.selector,
            params: "" // Empty params - underlying is derived from the asset being configured
        });

        // Add sUSDS asset via PriceConfig
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        vm.startPrank(daoMS);
        PriceConfigv2(priceConfig_).addAssetPrice(
            susds_,
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            strategy,
            feeds
        );
        vm.stopPrank();

        console2.log("sUSDS asset configured");
    }

    /// @notice Configure OHM asset with OHM/sUSDS Uniswap V3 pool
    function _configureOHM(address priceConfig_, address ohm_) internal {
        console2.log("Configuring OHM asset");

        // Get mainnet OHM/sUSDS Uniswap V3 pool address
        IUniswapV3Pool ohmSusdsPool = IUniswapV3Pool(0x0858e2B0F9D75f7300B38D64482aC2C8DF06a755);
        vm.label(address(ohmSusdsPool), "ohmSusdsPool");

        // Create strategy component: empty (single price feed)
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode(""),
            selector: bytes4(0),
            params: abi.encode("")
        });

        // Create feed component for OHM/sUSDS pool
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.UNIV3"),
            selector: UniswapV3Price.getTokenPrice.selector,
            params: abi.encode(
                UniswapV3Price.UniswapV3Params({
                    pool: ohmSusdsPool,
                    observationWindowSeconds: 3600 // 1 hour observation window
                })
            )
        });

        // Add OHM asset via PriceConfig
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        vm.startPrank(daoMS);
        PriceConfigv2(priceConfig_).addAssetPrice(
            ohm_,
            false, // storeMovingAverage
            false, // useMovingAverage
            uint32(0), // movingAverageDuration
            uint48(0), // lastObservationTime
            new uint256[](0), // observations
            strategy,
            feeds
        );
        vm.stopPrank();

        console2.log("OHM asset configured with OHM/sUSDS Uniswap V3 pool");
    }

    /// @notice Install a submodule via PriceConfig if not already installed
    function _installSubmoduleIfNeeded(address priceConfig_, string memory key_) internal {
        address submodule = _safeGetAddress(key_);
        if (submodule == address(0)) {
            revert(string.concat("Submodule key not found in addresses.json: ", key_));
        }

        // Get the PRICE module to check if submodule is already installed
        address priceModule = _safeGetAddress("olympus-module-price-1_2");

        // Get the submodule's SubKeycode by calling SUBKEYCODE()
        SubKeycode subKeycode = Submodule(submodule).SUBKEYCODE();

        // Check if submodule is already installed in PRICE module
        if (
            address(ModuleWithSubmodules(priceModule).getSubmoduleForKeycode(subKeycode)) !=
            address(0)
        ) {
            console2.log("Submodule already installed in PRICE module:", key_);
            return;
        }

        // Get DAO MS for the prank
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // Install the submodule via PriceConfig (pranked as DAO MS)
        vm.startPrank(daoMS);
        PriceConfigv2(priceConfig_).installSubmodule(submodule);
        vm.stopPrank();

        console2.log("Installed submodule:", key_);
    }

    // ========== STATE VALIDATION ========== //

    /// @notice Validates the post-execution state of the Oracle proposal
    function testProposal_validateState() public view {
        // Get addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");

        address chainlinkFactory = addresses.getAddress(
            "olympus-policy-chainlink-oracle-factory-1_0"
        );
        address morphoFactory = addresses.getAddress("olympus-policy-morpho-oracle-factory-1_0");

        // Verify roles
        assertTrue(roles.hasRole(timelock, ADMIN_ROLE), "Timelock does not have admin role");
        assertTrue(
            roles.hasRole(daoMS, ORACLE_MANAGER_ROLE),
            "DAO MS does not have oracle_manager role"
        );
        assertTrue(
            roles.hasRole(timelock, ORACLE_MANAGER_ROLE),
            "Timelock does not have oracle_manager role"
        );

        // Verify policies enabled
        assertTrue(
            IEnabler(addresses.getAddress("olympus-policy-erc7726-oracle-1_0")).isEnabled(),
            "ERC7726Oracle not enabled"
        );
        assertTrue(IEnabler(chainlinkFactory).isEnabled(), "ChainlinkOracleFactory not enabled");
        assertTrue(IEnabler(morphoFactory).isEnabled(), "MorphoOracleFactory not enabled");

        // Verify oracles deployed
        address chainlinkOracle = IOracleFactory(chainlinkFactory).getOracle(ohm, usds);
        assertTrue(chainlinkOracle != address(0), "OHM/USDS Chainlink oracle not deployed");
        assertTrue(
            IOracleFactory(chainlinkFactory).isOracleEnabled(chainlinkOracle),
            "Chainlink oracle not enabled"
        );

        address morphoOracle = IOracleFactory(morphoFactory).getOracle(ohm, usds);
        assertTrue(morphoOracle != address(0), "OHM/USDS Morpho oracle not deployed");
        assertTrue(
            IOracleFactory(morphoFactory).isOracleEnabled(morphoOracle),
            "Morpho oracle not enabled"
        );
    }

    /// @notice Validates that the ERC7726Oracle returns a valid OHM price
    /// @dev    Prices for USDS, wETH, OHM are validated in ConfigurePriceV1_2 batch
    ///         This test validates that the ERC7726Oracle correctly quotes OHM in USDS
    function testProposal_validatePricesAreSane() public view {
        address erc7726Oracle = addresses.getAddress("olympus-policy-erc7726-oracle-1_0");
        address ohm = addresses.getAddress("olympus-legacy-ohm");
        address usds = addresses.getAddress("external-tokens-usds");

        // Validate ERC7726Oracle can quote OHM in terms of USDS
        // Quote 1 OHM (9 decimals) in USDS (18 decimals)
        uint256 ohmInUsds = IERC7726Oracle(erc7726Oracle).getQuote(1e9, ohm, usds);
        console2.log("Asset price of OHM:", ohmInUsds);
        assertGe(ohmInUsds, OHM_MIN_PRICE, "OHM price below minimum");
        assertLe(ohmInUsds, OHM_MAX_PRICE, "OHM price above maximum");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
