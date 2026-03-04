// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.24;

// Scripting
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";

// Interfaces
import {IERC20 as ChainlinkIERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IDistributor} from "src/policies/interfaces/IDistributor.sol";
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IVault} from "src/libraries/Balancer/interfaces/IVault.sol";

// Contracts
import {Kernel, Module} from "src/Kernel.sol";

// Bridge
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";

// Deposits
import {CDAuctioneerLimitOrders} from "src/policies/deposits/LimitOrders.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositRedemptionVault} from "src/policies/deposits/DepositRedemptionVault.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

// Other
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {ReserveWrapper} from "src/policies/ReserveWrapper.sol";
import {ZeroDistributor} from "src/policies/Distributor/ZeroDistributor.sol";

// Modules
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {PositionTokenRenderer} from "src/modules/DEPOS/PositionTokenRenderer.sol";

// PRICE submodules
import {BalancerPoolTokenPrice} from "src/modules/PRICE/submodules/feeds/BalancerPoolTokenPrice.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ERC4626Price} from "src/modules/PRICE/submodules/feeds/ERC4626Price.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";
import {UniswapV2PoolTokenPrice} from "src/modules/PRICE/submodules/feeds/UniswapV2PoolTokenPrice.sol";
import {UniswapV3Price} from "src/modules/PRICE/submodules/feeds/UniswapV3Price.sol";
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";

// Oracle factories
import {ChainlinkOracleFactory} from "src/policies/price/ChainlinkOracleFactory.sol";
import {ERC7726Oracle} from "src/policies/price/ERC7726Oracle.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";

// PRICE
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {OlympusPriceConfig} from "src/policies/price/PriceConfig.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";

// Test mocks
import {MockPriceFeedOwned} from "src/test/mocks/MockPriceFeedOwned.sol";

// Migration contracts
import {OwnedERC20} from "src/external/OwnedERC20.sol";
import {Burner} from "src/policies/Burner.sol";
import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";
import {V1Migrator} from "src/policies/V1Migrator.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// OCG Activator contracts
import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";

// solhint-disable gas-custom-errors

/// @notice V3 of the deployment script
/// @dev    Changes from DeployV2.s.sol:
///         - env.json is updated with the deployed addresses
///         - helper functions for reading deployment arguments from the sequence file
///         - remove the use of state variables for all of the contracts, since they can be loaded easily with `_envAddressNotZero()`
///         - deployment functions can reference deployments from the same sequence file (using `_getAddressNotZero()`)
contract DeployV3 is WithEnvironment {
    using stdJson for string;

    // TODOs
    // [ ] Shift per-deployment functions into separate files, so we don't have import hell
    // [ ] Add support for Kernel deployment
    // [ ] Handle error code from ffi calls

    // ========== STATE VARIABLES ========== //

    string[] public deployments;
    string[] public deployedToKeys;
    mapping(string => address) public deployedTo;

    string public sequenceFile;

    // ========== SETUP FUNCTIONS ========== //

    function _setUp(string calldata deployFilePath_) internal {
        string memory chain_ = ChainUtils._getChainName(block.chainid);
        _loadEnv(chain_);

        // It would be nice to print the RPC URL being used here, but unfortunately vm.rpcUrl() prints the URL configured in foundry.toml

        // Load deployment data
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        sequenceFile = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(sequenceFile.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("  Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(sequenceFile.parseRaw(".sequence[*].name"), (string));
            deployments.push(name);
        } else {
            // More than one deployment
            string[] memory names = abi.decode(
                sequenceFile.parseRaw(".sequence[*].name"),
                (string[])
            );
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);
            }
        }
    }

    function deploy(string calldata deployFilePath_) external {
        // Setup
        _setUp(deployFilePath_);

        // Check that deployments is not empty
        uint256 len = deployments.length;
        require(len > 0, "No deployments");

        // Iterate through deployments
        // Note that this cannot be used with the kernel deployment
        for (uint256 i; i < len; i++) {
            // Get deploy deploy args from contract name
            string memory name = deployments[i];

            // Announce
            console2.log("\n");
            console2.log("--------------------------------");
            console2.log("Deploying", name);
            console2.log("\n");

            // e.g. a deployment named CCIPBurnMintTokenPool would require the following function: deployCCIPBurnMintTokenPool()
            bytes4 selector = bytes4(keccak256(bytes(string.concat("deploy", name, "()"))));

            // Call the deploy function for the contract
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(selector)
            );
            require(success, string.concat("Failed to deploy ", deployments[i]));

            // Store the deployed contract address for logging
            (address deploymentAddress, string memory keyPrefix) = abi.decode(
                data,
                (address, string)
            );
            string memory deployedToKey = string.concat(keyPrefix, ".", name);

            // Announce
            console2.log("\n");
            console2.log(name, "deployed at:", deploymentAddress);
            console2.log("Stored in", deployedToKey);
            console2.log("--------------------------------");

            deployedToKeys.push(deployedToKey);
            deployedTo[deployedToKey] = deploymentAddress;
        }

        // Save deployments to file
        _saveDeployment(chain);
    }

    function _saveDeployment(string memory chain_) internal {
        // Skip if broadcast is not enabled
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Broadcast not enabled. Skipping saving deployments");
            return;
        }

        // Create the deployments folder if it doesn't exist
        if (!vm.isDir("./deployments")) {
            console2.log("Creating deployments directory");

            string[] memory inputs = new string[](2);
            inputs[0] = "mkdir";
            inputs[1] = "deployments";

            /// forge-lint: disable-next-line(unsafe-cheatcode)
            vm.ffi(inputs);
        }

        // Create file path
        string memory file = string.concat(
            "./deployments/",
            ".",
            chain_,
            "-",
            vm.toString(block.timestamp),
            ".json"
        );
        console2.log("\n");
        console2.log("Writing deployments to", file);

        // Write deployment info to file in JSON format
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeLine(file, "{");

        // solhint-disable quotes

        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployedToKeys.length;
        for (uint256 i; i < len - 1; ++i) {
            /// forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeLine(
                file,
                string.concat(
                    '"',
                    deployedToKeys[i],
                    '": "',
                    vm.toString(deployedTo[deployedToKeys[i]]),
                    '",'
                )
            );
        }
        // Write last deployment without a comma
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeLine(
            file,
            string.concat(
                '"',
                deployedToKeys[len - 1],
                '": "',
                vm.toString(deployedTo[deployedToKeys[len - 1]]),
                '"'
            )
        );
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeLine(file, "}");

        // solhint-enable quotes

        // Update the env.json file
        console2.log("\n");
        console2.log("Writing deployment addresses to env.json");
        for (uint256 i; i < len; ++i) {
            string memory key = deployedToKeys[i];
            address value = deployedTo[key];

            string[] memory inputs = new string[](3);
            inputs[0] = "./src/scripts/deploy/write_deployment.sh";
            inputs[1] = string.concat("current", ".", chain_, ".", key);
            inputs[2] = vm.toString(value);

            /// forge-lint: disable-next-line(unsafe-cheatcode)
            vm.ffi(inputs);
        }
    }

    /// @notice Get an address for a given key
    /// @dev    This variant will first check for the key in the
    ///         addresses from the current deployment sequence (stored in `deployedTo`),
    ///         followed by the contents of `env.json`.
    ///
    ///         If no value is found for the key, or it is the zero address, the function will revert.
    ///
    /// @param  key_    Key to look for
    /// @return address Returns the address
    function _getAddressNotZero(string memory key_) internal view returns (address) {
        // Get from the deployed addresses first
        address deployedAddress = deployedTo[key_];

        if (deployedAddress != address(0)) {
            console2.log("  %s: %s (from deployment addresses)", key_, deployedAddress);
            return deployedAddress;
        }

        return _envAddressNotZero(key_);
    }

    function _readDeploymentArgString(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (string memory) {
        return
            sequenceFile.readString(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgBytes32(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (bytes32) {
        return
            sequenceFile.readBytes32(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgAddress(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (address) {
        return
            sequenceFile.readAddress(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgUint256(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (uint256) {
        return
            sequenceFile.readUint(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _readDeploymentArgUint8Array(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (uint8[] memory) {
        string memory jsonPath = string.concat(
            ".sequence[?(@.name == '",
            deploymentName_,
            "')].args.",
            key_
        );
        uint256[] memory uint256Array = sequenceFile.readUintArray(jsonPath);
        uint8[] memory uint8Array = new uint8[](uint256Array.length);
        for (uint256 i = 0; i < uint256Array.length; i++) {
            uint8Array[i] = SafeCast.encodeUInt8(uint256Array[i]);
        }
        return uint8Array;
    }

    function _readDeploymentArgAddressArray(
        string memory deploymentName_,
        string memory key_
    ) internal view returns (address[] memory) {
        return
            sequenceFile.readAddressArray(
                string.concat(".sequence[?(@.name == '", deploymentName_, "')].args.", key_)
            );
    }

    function _getDeployer() internal returns (address) {
        (, address msgSender, ) = vm.readCallers();

        // Validate that the sender is not the default deployer (or else it can cause problems)
        if (msgSender == address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38)) {
            // solhint-disable-next-line gas-custom-errors
            revert("Cannot use the default foundry deployer address, specify using --sender");
        }

        return msgSender;
    }

    // ========== DEPLOYMENT FUNCTIONS ========== //

    function deployCCIPBurnMintTokenPool() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address rmnProxy = _envAddressNotZero("external.ccip.RMN");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");

        // Log arguments
        console2.log("\n");
        console2.log("CCIPBurnMintTokenPool parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohm", ohm);
        console2.log("  rmnProxy", rmnProxy);
        console2.log("  ccipRouter", ccipRouter);

        // Deploy CCIPBurnMintTokenPool
        vm.broadcast();
        CCIPBurnMintTokenPool ccipBurnMintTokenPool = new CCIPBurnMintTokenPool(
            kernel,
            ohm,
            rmnProxy,
            ccipRouter
        );

        return (address(ccipBurnMintTokenPool), "olympus.policies");
    }

    function deployCCIPLockReleaseTokenPool() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address rmnProxy = _envAddressNotZero("external.ccip.RMN");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");
        uint8 ohmDecimals = 9;
        address[] memory allowlist = new address[](0);
        bool acceptLiquidity = true;

        // Log arguments
        console2.log("\n");
        console2.log("LockReleaseTokenPool parameters:");
        console2.log("  ohm", ohm);
        console2.log("  ohmDecimals", ohmDecimals);
        console2.log("  allowlist", allowlist.length > 0 ? "true" : "false");
        console2.log("  rmnProxy", rmnProxy);
        console2.log("  acceptLiquidity", acceptLiquidity);
        console2.log("  ccipRouter", ccipRouter);

        // Deploy LockReleaseTokenPool
        vm.broadcast();
        LockReleaseTokenPool lockReleaseTokenPool = new LockReleaseTokenPool(
            ChainlinkIERC20(ohm),
            ohmDecimals,
            allowlist,
            rmnProxy,
            acceptLiquidity,
            ccipRouter
        );

        return (address(lockReleaseTokenPool), "olympus.periphery");
    }

    function deployCCIPCrossChainBridge() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        address owner = _getDeployer(); // Make the deployer the initial owner, so the configuration can be completed easily

        // Log dependencies
        console2.log("CCIPCrossChainBridge parameters:");
        console2.log("  ohm", ohm);
        console2.log("  ccipRouter", ccipRouter);
        console2.log("  owner", owner);

        // Deploy CCIPCrossChainBridge
        vm.broadcast();
        CCIPCrossChainBridge ccipCrossChainBridge = new CCIPCrossChainBridge(
            ohm,
            ccipRouter,
            owner
        );

        return (address(ccipCrossChainBridge), "olympus.periphery");
    }

    function deployOlympusHeart() public returns (address, string memory) {
        // Input parameters
        uint256 maxReward = _readDeploymentArgUint256("OlympusHeart", "maxReward");
        uint48 auctionDuration = SafeCast.encodeUInt48(
            _readDeploymentArgUint256("OlympusHeart", "auctionDuration")
        );

        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address distributor = _getAddressNotZero("olympus.policies.ZeroDistributor");

        // Log inputs
        console2.log("Heart parameters:");
        console2.log("  kernel", kernel);
        console2.log("  distributor", distributor);
        console2.log("  maxReward", maxReward);
        console2.log("  auctionDuration", auctionDuration);

        // Deploy
        vm.broadcast();
        OlympusHeart heart = new OlympusHeart(
            Kernel(kernel),
            IDistributor(distributor),
            maxReward,
            auctionDuration
        );

        return (address(heart), "olympus.policies");
    }

    function deployReceiptTokenManager() public returns (address, string memory) {
        // Deploy
        vm.broadcast();
        ReceiptTokenManager receiptTokenManager = new ReceiptTokenManager();

        return (address(receiptTokenManager), "olympus.periphery");
    }

    function deployDepositManager() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address receiptTokenManager = _getAddressNotZero("olympus.periphery.ReceiptTokenManager");

        // Log parameters
        console2.log("DepositManager parameters:");
        console2.log("  kernel", kernel);
        console2.log("  receiptTokenManager", receiptTokenManager);

        // Deploy
        vm.broadcast();
        DepositManager depositManager = new DepositManager(kernel, receiptTokenManager);

        return (address(depositManager), "olympus.policies");
    }

    function deployEmissionManager() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");
        address gohm = _getAddressNotZero("olympus.legacy.gOHM");
        address reserve = _getAddressNotZero("external.tokens.USDS");
        address sReserve = _getAddressNotZero("external.tokens.sUSDS");
        address bondAuctioneer = _getAddressNotZero(
            "external.bond-protocol.BondFixedTermAuctioneer"
        );
        address cdAuctioneer = _getAddressNotZero("olympus.policies.ConvertibleDepositAuctioneer");
        address teller = _getAddressNotZero("external.bond-protocol.BondFixedTermTeller");

        // Log parameters
        console2.log("EmissionManager parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohm", ohm);
        console2.log("  gohm", gohm);
        console2.log("  reserve", reserve);
        console2.log("  sReserve", sReserve);
        console2.log("  bondAuctioneer", bondAuctioneer);
        console2.log("  cdAuctioneer", cdAuctioneer);
        console2.log("  teller", teller);

        // Deploy
        vm.broadcast();
        EmissionManager emissionManager = new EmissionManager(
            Kernel(kernel),
            ohm,
            gohm,
            reserve,
            sReserve,
            bondAuctioneer,
            cdAuctioneer,
            teller
        );

        return (address(emissionManager), "olympus.policies");
    }

    function deployConvertibleDepositFacility() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address depositManager = _getAddressNotZero("olympus.policies.DepositManager");

        // Log parameters
        console2.log("ConvertibleDepositFacility parameters:");
        console2.log("  kernel", kernel);
        console2.log("  depositManager", depositManager);

        // Deploy
        vm.broadcast();
        ConvertibleDepositFacility cdFacility = new ConvertibleDepositFacility(
            kernel,
            depositManager
        );

        return (address(cdFacility), "olympus.policies");
    }

    function deployConvertibleDepositAuctioneer() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address cdFacility = _getAddressNotZero("olympus.policies.ConvertibleDepositFacility");
        address depositAsset = _getAddressNotZero("external.tokens.USDS");

        // Log parameters
        console2.log("ConvertibleDepositAuctioneer parameters:");
        console2.log("  kernel", kernel);
        console2.log("  cdFacility", cdFacility);
        console2.log("  depositAsset", depositAsset);

        // Deploy
        vm.broadcast();
        ConvertibleDepositAuctioneer cdAuctioneer = new ConvertibleDepositAuctioneer(
            kernel,
            cdFacility,
            depositAsset
        );

        return (address(cdAuctioneer), "olympus.policies");
    }

    function deployOlympusDepositPositionManager() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address tokenRenderer = _getAddressNotZero("olympus.periphery.PositionTokenRenderer");

        // Log parameters
        console2.log("OlympusDepositPositionManager parameters:");
        console2.log("  kernel", kernel);
        console2.log("  tokenRenderer", tokenRenderer);

        // Deploy
        vm.broadcast();
        OlympusDepositPositionManager depos = new OlympusDepositPositionManager(
            kernel,
            tokenRenderer
        );

        return (address(depos), "olympus.modules");
    }

    function deployPositionTokenRenderer() public returns (address, string memory) {
        // No dependencies needed for PositionTokenRenderer

        // Log parameters
        console2.log("PositionTokenRenderer parameters:");
        console2.log("  No constructor parameters");

        // Deploy
        vm.broadcast();
        PositionTokenRenderer renderer = new PositionTokenRenderer();

        return (address(renderer), "olympus.periphery");
    }

    function deployDepositRedemptionVault() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address depositManager = _getAddressNotZero("olympus.policies.DepositManager");

        // Log parameters
        console2.log("DepositRedemptionVault parameters:");
        console2.log("  kernel", kernel);
        console2.log("  depositManager", depositManager);

        // Deploy
        vm.broadcast();
        DepositRedemptionVault vault = new DepositRedemptionVault(kernel, depositManager);

        return (address(vault), "olympus.policies");
    }

    function deployReserveWrapper() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address reserve = _getAddressNotZero("external.tokens.USDS");
        address sReserve = _getAddressNotZero("external.tokens.sUSDS");

        // Log parameters
        console2.log("ReserveWrapper parameters:");
        console2.log("  kernel", kernel);
        console2.log("  reserve", reserve);
        console2.log("  sReserve", sReserve);

        // Deploy
        vm.broadcast();
        ReserveWrapper wrapper = new ReserveWrapper(kernel, reserve, sReserve);

        return (address(wrapper), "olympus.policies");
    }

    function deployZeroDistributor() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address staking = _getAddressNotZero("olympus.legacy.Staking");

        // Log parameters
        console2.log("ZeroDistributor parameters:");
        console2.log("  staking", staking);

        // Deploy
        vm.broadcast();
        ZeroDistributor zeroDistributor = new ZeroDistributor(staking);

        return (address(zeroDistributor), "olympus.policies");
    }

    function deployOlympusPriceV1() public returns (address, string memory) {
        // Input parameters
        uint32 observationFrequency = SafeCast.encodeUInt32(
            _readDeploymentArgUint256("OlympusPriceV1", "observationFrequency")
        );
        uint256 minimumTargetPrice = _readDeploymentArgUint256(
            "OlympusPriceV1",
            "minimumTargetPrice"
        );

        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");

        // Log parameters
        console2.log("PRICEv1.2 parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohm", ohm);
        console2.log("  observationFrequency", observationFrequency);
        console2.log("  minimumTargetPrice", minimumTargetPrice);

        // Deploy PRICEv1_2 (replaces existing PRICE module)
        vm.broadcast();
        OlympusPricev1_2 price = new OlympusPricev1_2(
            Kernel(kernel),
            ohm,
            observationFrequency,
            minimumTargetPrice
        );

        return (address(price), "olympus.modules");
    }

    function deployOlympusPriceConfig() public returns (address, string memory) {
        // Dependencies
        address kernel = _getAddressNotZero("olympus.Kernel");

        // Log parameters
        console2.log("PriceConfig parameters:");
        console2.log("  kernel", kernel);

        // Deploy PriceConfig policy (v1)
        vm.broadcast();
        OlympusPriceConfig priceConfig = new OlympusPriceConfig(Kernel(kernel));

        return (address(priceConfig), "olympus.policies");
    }

    function deployOlympusPriceConfigV2() public returns (address, string memory) {
        // Dependencies
        address kernel = _getAddressNotZero("olympus.Kernel");

        // Log parameters
        console2.log("PriceConfigv2 parameters:");
        console2.log("  kernel", kernel);

        // Deploy PriceConfigV2 policy (auto-enables on deployment)
        vm.broadcast();
        PriceConfigv2 priceConfig = new PriceConfigv2(Kernel(kernel));

        return (address(priceConfig), "olympus.policies");
    }

    // ========== PRICE SUBMODULE DEPLOYMENT FUNCTIONS ========== //

    function deployChainlinkPriceFeeds() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("ChainlinkPriceFeeds parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        ChainlinkPriceFeeds feeds = new ChainlinkPriceFeeds(Module(priceModule));

        return (address(feeds), "olympus.submodules.PRICE");
    }

    function deployPythPriceFeeds() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("PythPriceFeeds parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        PythPriceFeeds feeds = new PythPriceFeeds(Module(priceModule));

        return (address(feeds), "olympus.submodules.PRICE");
    }

    function deployUniswapV3Price() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("UniswapV3Price parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        UniswapV3Price price = new UniswapV3Price(Module(priceModule));

        return (address(price), "olympus.submodules.PRICE");
    }

    function deployERC4626Price() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("ERC4626Price parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        ERC4626Price price = new ERC4626Price(Module(priceModule));

        return (address(price), "olympus.submodules.PRICE");
    }

    function deploySimplePriceFeedStrategy() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("SimplePriceFeedStrategy parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        SimplePriceFeedStrategy strategy = new SimplePriceFeedStrategy(Module(priceModule));

        return (address(strategy), "olympus.submodules.PRICE");
    }

    function deployUniswapV2PoolTokenPrice() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");

        // Log parameters
        console2.log("UniswapV2PoolTokenPrice parameters:");
        console2.log("  priceModule", priceModule);

        // Deploy
        vm.broadcast();
        UniswapV2PoolTokenPrice price = new UniswapV2PoolTokenPrice(Module(priceModule));

        return (address(price), "olympus.submodules.PRICE");
    }

    function deployBalancerPoolTokenPrice() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address priceModule = _getAddressNotZero("olympus.modules.OlympusPriceV1");
        address balVault = _envAddressNotZero("external.balancer.BalancerVault");

        // Log parameters
        console2.log("BalancerPoolTokenPrice parameters:");
        console2.log("  priceModule", priceModule);
        console2.log("  balVault", balVault);

        // Deploy
        vm.broadcast();
        BalancerPoolTokenPrice price = new BalancerPoolTokenPrice(
            Module(priceModule),
            IVault(balVault)
        );

        return (address(price), "olympus.submodules.PRICE");
    }

    // ========== ORACLE FACTORY DEPLOYMENT FUNCTIONS ========== //

    function deployChainlinkOracleFactory() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");

        // Log parameters
        console2.log("ChainlinkOracleFactory parameters:");
        console2.log("  kernel", kernel);

        // Deploy
        vm.broadcast();
        ChainlinkOracleFactory factory = new ChainlinkOracleFactory(Kernel(kernel));

        return (address(factory), "olympus.policies");
    }

    function deployMorphoOracleFactory() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");

        // Log parameters
        console2.log("MorphoOracleFactory parameters:");
        console2.log("  kernel", kernel);

        // Deploy
        vm.broadcast();
        MorphoOracleFactory factory = new MorphoOracleFactory(Kernel(kernel));

        return (address(factory), "olympus.policies");
    }

    function deployERC7726Oracle() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");

        // Log parameters
        console2.log("ERC7726Oracle parameters:");
        console2.log("  kernel", kernel);

        // Deploy
        vm.broadcast();
        ERC7726Oracle oracle = new ERC7726Oracle(Kernel(kernel));

        return (address(oracle), "olympus.policies");
    }

    // ========== MOCK PRICE FEED DEPLOYMENT FUNCTIONS ========== //

    function deploydaiEthPriceFeed() public returns (address, string memory) {
        // Log parameters
        console2.log("Deploying DAI/ETH MockPriceFeedOwned with 18 decimals");

        // Deploy
        vm.broadcast();
        MockPriceFeedOwned priceFeed = new MockPriceFeedOwned();

        // Set decimals to 18
        vm.broadcast();
        priceFeed.setDecimals(18);

        // Set description
        vm.broadcast();
        priceFeed.setDescription("DAI / ETH");

        return (address(priceFeed), "external.chainlink");
    }

    function deployohmEthPriceFeed() public returns (address, string memory) {
        // Log parameters
        console2.log("Deploying OHM/ETH MockPriceFeedOwned with 18 decimals");

        // Deploy
        vm.broadcast();
        MockPriceFeedOwned priceFeed = new MockPriceFeedOwned();

        // Set decimals to 18
        vm.broadcast();
        priceFeed.setDecimals(18);

        // Set description
        vm.broadcast();
        priceFeed.setDescription("OHMv2 / ETH");

        return (address(priceFeed), "external.chainlink");
    }

    // ===== OCG ACTIVATOR CONTRACTS ===== //

    function deployConvertibleDepositActivator() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address timelock = _getAddressNotZero("olympus.governance.Timelock");
        address depositManager = _getAddressNotZero("olympus.policies.DepositManager");
        address cdFacility = _getAddressNotZero("olympus.policies.ConvertibleDepositFacility");
        address cdAuctioneer = _getAddressNotZero("olympus.policies.ConvertibleDepositAuctioneer");
        address depositRedemptionVault = _getAddressNotZero(
            "olympus.policies.DepositRedemptionVault"
        );
        address emissionManager = _getAddressNotZero("olympus.policies.EmissionManager");
        address heart = _getAddressNotZero("olympus.policies.OlympusHeart");
        address reserveWrapper = _getAddressNotZero("olympus.policies.ReserveWrapper");

        // Log parameters
        console2.log("ConvertibleDepositActivator parameters:");
        console2.log("  owner", timelock);
        console2.log("  depositManager", depositManager);
        console2.log("  cdFacility", cdFacility);
        console2.log("  cdAuctioneer", cdAuctioneer);
        console2.log("  depositRedemptionVault", depositRedemptionVault);
        console2.log("  emissionManager", emissionManager);
        console2.log("  heart", heart);
        console2.log("  reserveWrapper", reserveWrapper);

        // Deploy
        vm.broadcast();
        ConvertibleDepositActivator activator = new ConvertibleDepositActivator(
            timelock,
            depositManager,
            cdFacility,
            cdAuctioneer,
            depositRedemptionVault,
            emissionManager,
            heart,
            reserveWrapper
        );

        return (address(activator), "olympus.periphery");
    }

    function deployConvertibleDepositAuctioneerLimitOrders()
        public
        returns (address, string memory)
    {
        // Dependencies
        console2.log("Checking dependencies");
        address owner = _getAddressNotZero("olympus.multisig.dao");
        address depositManager = _getAddressNotZero("olympus.policies.DepositManager");
        address cdAuctioneer = _getAddressNotZero("olympus.policies.ConvertibleDepositAuctioneer");
        address usds = _getAddressNotZero("external.tokens.USDS");
        address sUsds = _getAddressNotZero("external.tokens.sUSDS");
        address positionNft = _getAddressNotZero("olympus.modules.OlympusDepositPositionManager");
        address yieldRecipient = _getAddressNotZero("olympus.modules.OlympusTreasury");

        // Read arrays from args
        uint8[] memory depositPeriods = _readDeploymentArgUint8Array(
            "ConvertibleDepositAuctioneerLimitOrders",
            "depositPeriods"
        );
        address[] memory receiptTokens = _readDeploymentArgAddressArray(
            "ConvertibleDepositAuctioneerLimitOrders",
            "receiptTokens"
        );

        // Log parameters
        console2.log("ConvertibleDepositAuctioneerLimitOrders parameters:");
        console2.log("  owner", owner);
        console2.log("  depositManager", depositManager);
        console2.log("  cdAuctioneer", cdAuctioneer);
        console2.log("  usds", usds);
        console2.log("  sUsds", sUsds);
        console2.log("  positionNft", positionNft);
        console2.log("  yieldRecipient", yieldRecipient);
        console2.log("  depositPeriods count", depositPeriods.length);
        console2.log("  receiptTokens count", receiptTokens.length);
        for (uint256 i; i < depositPeriods.length; i++) {
            console2.log("  depositPeriod", depositPeriods[i]);
            console2.log("  receiptToken", receiptTokens[i]);
        }

        // Deploy
        vm.broadcast();
        CDAuctioneerLimitOrders limitOrders = new CDAuctioneerLimitOrders(
            owner,
            depositManager,
            cdAuctioneer,
            usds,
            sUsds,
            positionNft,
            yieldRecipient,
            depositPeriods,
            receiptTokens
        );

        return (address(limitOrders), "olympus.periphery");
    }

    // ===== MIGRATION CONTRACTS ===== //

    function deployTempOHM() public returns (address, string memory) {
        // Input parameters
        string memory name = _readDeploymentArgString("TempOHM", "name");
        string memory symbol = _readDeploymentArgString("TempOHM", "symbol");
        address initialOwner = _envAddressNotZero("olympus.multisig.dao");

        // Log parameters
        console2.log("TempOHM parameters:");
        console2.log("  name", name);
        console2.log("  symbol", symbol);
        console2.log("  initialOwner", initialOwner);

        // Deploy
        vm.broadcast();
        OwnedERC20 tempOHM = new OwnedERC20(name, symbol, initialOwner);

        return (address(tempOHM), "external.tokens");
    }

    function deployBurner() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");

        // Log parameters
        console2.log("Burner parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohm", ohm);

        // Deploy
        vm.broadcast();
        Burner burner = new Burner(Kernel(kernel), ERC20(ohm));

        return (address(burner), "olympus.policies");
    }

    function deployMigrationProposalHelper() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address owner = _getAddressNotZero("olympus.governance.Timelock");
        address admin = _getAddressNotZero("olympus.multisig.dao");
        address burner = _getAddressNotZero("olympus.policies.Burner");
        address tempOHM = _getAddressNotZero("external.tokens.TempOHM");

        // Read OHMv1ToMigrate from args
        uint256 OHMv1ToMigrate = _readDeploymentArgUint256(
            "MigrationProposalHelper",
            "OHMv1ToMigrate"
        );

        // Log parameters
        console2.log("MigrationProposalHelper parameters:");
        console2.log("  owner", owner);
        console2.log("  admin", admin);
        console2.log("  burner", burner);
        console2.log("  tempOHM", tempOHM);
        console2.log("  OHMv1ToMigrate", OHMv1ToMigrate);

        // Deploy
        vm.broadcast();
        MigrationProposalHelper helper = new MigrationProposalHelper(
            owner,
            admin,
            burner,
            tempOHM,
            OHMv1ToMigrate
        );

        return (address(helper), "olympus.periphery");
    }

    function deployV1Migrator() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohmV1 = _getAddressNotZero("olympus.legacy.OHMv1");
        address gohm = _getAddressNotZero("olympus.legacy.gOHM");
        bytes32 merkleRoot = bytes32(0); // Set to zero, will be set to a valid root after the proposal is executed

        // Log parameters
        console2.log("V1Migrator parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohmV1", ohmV1);
        console2.log("  gohm", gohm);
        console2.log("  merkleRoot", vm.toString(merkleRoot));

        // Deploy
        vm.broadcast();
        V1Migrator migrator = new V1Migrator(
            Kernel(kernel),
            IERC20(ohmV1),
            IgOHM(gohm),
            merkleRoot
        );

        return (address(migrator), "olympus.policies");
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
