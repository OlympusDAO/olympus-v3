// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

// Scripting
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IDistributor} from "src/policies/interfaces/IDistributor.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {PositionTokenRenderer} from "src/modules/DEPOS/PositionTokenRenderer.sol";
import {DepositRedemptionVault} from "src/policies/deposits/DepositRedemptionVault.sol";
import {ReserveWrapper} from "src/policies/ReserveWrapper.sol";
import {ZeroDistributor} from "src/policies/Distributor/ZeroDistributor.sol";
import {OlympusPrice} from "src/modules/PRICE/OlympusPrice.sol";
import {OlympusPriceConfig} from "src/policies/PriceConfig.sol";
import {MockPriceFeedOwned} from "src/test/mocks/MockPriceFeedOwned.sol";

// OCG Activator contracts
import {ConvertibleDepositActivator} from "src/scripts/ops/batches/ConvertibleDepositActivator.sol";

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
        sequenceFile = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(sequenceFile.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("  Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(sequenceFile.parseRaw(".sequence..name"), (string));
            deployments.push(name);
        } else {
            // More than one deployment
            string[] memory names = abi.decode(
                sequenceFile.parseRaw(".sequence..name"),
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
        vm.writeLine(file, "{");

        // solhint-disable quotes

        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployedToKeys.length;
        for (uint256 i; i < len - 1; ++i) {
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
            IERC20(ohm),
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

    function deployOlympusPrice() public returns (address, string memory) {
        // Dependencies
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohmEthPriceFeed = _envAddressNotZero("external.chainlink.ohmEthPriceFeed");
        address reserveEthPriceFeed = _envAddressNotZero("external.chainlink.daiEthPriceFeed");

        // Input parameters
        uint48 ohmEthUpdateThreshold = SafeCast.encodeUInt48(
            _readDeploymentArgUint256("OlympusPrice", "ohmEthUpdateThreshold")
        );
        uint48 reserveEthUpdateThreshold = SafeCast.encodeUInt48(
            _readDeploymentArgUint256("OlympusPrice", "reserveEthUpdateThreshold")
        );
        uint48 observationFrequency = SafeCast.encodeUInt48(
            _readDeploymentArgUint256("OlympusPrice", "observationFrequency")
        );
        uint48 movingAverageDuration = SafeCast.encodeUInt48(
            _readDeploymentArgUint256("OlympusPrice", "movingAverageDuration")
        );
        uint256 minimumTargetPrice = _readDeploymentArgUint256(
            "OlympusPrice",
            "minimumTargetPrice"
        );

        // Log parameters
        console2.log("PRICE parameters:");
        console2.log("  kernel", kernel);
        console2.log("  ohmEthPriceFeed", ohmEthPriceFeed);
        console2.log("  reserveEthPriceFeed", reserveEthPriceFeed);
        console2.log("  reserveEthUpdateThreshold", reserveEthUpdateThreshold);
        console2.log("  observationFrequency", observationFrequency);
        console2.log("  movingAverageDuration", movingAverageDuration);
        console2.log("  minimumTargetPrice", minimumTargetPrice);

        // Deploy Price module
        vm.broadcast();
        OlympusPrice price = new OlympusPrice(
            Kernel(kernel),
            AggregatorV2V3Interface(ohmEthPriceFeed),
            ohmEthUpdateThreshold,
            AggregatorV2V3Interface(reserveEthPriceFeed),
            reserveEthUpdateThreshold,
            observationFrequency,
            movingAverageDuration,
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

        // Deploy PriceConfig policy
        vm.broadcast();
        OlympusPriceConfig priceConfig = new OlympusPriceConfig(Kernel(kernel));

        return (address(priceConfig), "olympus.policies");
    }

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
}
