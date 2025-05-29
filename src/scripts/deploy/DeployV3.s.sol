// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

// Scripting
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Interfaces
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

// Contracts
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";

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

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal {
        _loadEnv(chain_);

        // Load deployment data
        sequenceFile = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(sequenceFile.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

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

    function deploy(string calldata chain_, string calldata deployFilePath_) external {
        // Setup
        _setUp(chain_, deployFilePath_);

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
        _saveDeployment(chain_);
    }

    function _saveDeployment(string memory chain_) internal {
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
}
