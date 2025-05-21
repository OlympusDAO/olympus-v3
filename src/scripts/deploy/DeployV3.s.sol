// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

// Scripting
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

// Contracts
import {CCIPMintBurnTokenPool} from "src/policies/bridge/CCIPMintBurnTokenPool.sol";
import {CCIPCrossChainBridge} from "src/periphery/CCIPCrossChainBridge.sol";

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

            // e.g. a deployment named CCIPMintBurnTokenPool would require the following function: deployCCIPMintBurnTokenPool()
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

    // ========== DEPLOYMENT FUNCTIONS ========== //

    function deployCCIPMintBurnTokenPool() public returns (address, string memory) {
        // Decode arguments from the sequence file
        uint256 initialBridgedSupply = _readDeploymentArgUint256(
            "CCIPMintBurnTokenPool",
            "initialBridgedSupply"
        );

        // Determine the appropriate mainnet chain ID
        uint256 mainnetChainId = 1;
        bytes memory chainMemory = bytes(chain);
        // If a testnet, set sepolia to be the mainnet chain ID
        if (
            keccak256(chainMemory) == keccak256("sepolia") ||
            keccak256(chainMemory) == keccak256("optimism-sepolia") ||
            keccak256(chainMemory) == keccak256("base-sepolia") ||
            keccak256(chainMemory) == keccak256("arbitrum-sepolia") ||
            keccak256(chainMemory) == keccak256("berachain-bartio") ||
            keccak256(chainMemory) == keccak256("goerli") ||
            keccak256(chainMemory) == keccak256("holesky")
        ) {
            mainnetChainId = 11155111;
        }

        // If not mainnet/sepolia, ensure the initial bridged supply is 0
        if (mainnetChainId != 1 && mainnetChainId != 11155111 && initialBridgedSupply != 0)
            revert("initialBridgedSupply must be 0 on non-mainnet chains");

        // Dependencies
        console2.log("Checking dependencies");
        address rmnProxy = _envAddressNotZero("external.ccip.RMN");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        address kernel = _getAddressNotZero("olympus.Kernel");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");

        // Log arguments
        console2.log("\n");
        console2.log("CCIPMintBurnTokenPool parameters:");
        console2.log("  kernel", kernel);
        console2.log("  initialBridgedSupply", initialBridgedSupply);
        console2.log("  ohm", ohm);
        console2.log("  rmnProxy", rmnProxy);
        console2.log("  ccipRouter", ccipRouter);
        console2.log("  mainnetChainId", mainnetChainId);

        // Deploy CCIPMintBurnTokenPool
        vm.broadcast();
        CCIPMintBurnTokenPool ccipMintBurnTokenPool = new CCIPMintBurnTokenPool(
            kernel,
            initialBridgedSupply,
            ohm,
            rmnProxy,
            ccipRouter,
            mainnetChainId
        );

        return (address(ccipMintBurnTokenPool), "olympus.policies");
    }

    function deployCCIPCrossChainBridge() public returns (address, string memory) {
        // Dependencies
        console2.log("Checking dependencies");
        address ohm = _getAddressNotZero("olympus.legacy.OHM");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        // Log dependencies
        console2.log("CCIPCrossChainBridge parameters:");
        console2.log("  ohm", ohm);
        console2.log("  ccipRouter", ccipRouter);
        console2.log("  owner", daoMS);

        // Deploy CCIPCrossChainBridge
        vm.broadcast();
        CCIPCrossChainBridge ccipCrossChainBridge = new CCIPCrossChainBridge(
            ohm,
            ccipRouter,
            daoMS
        );

        return (address(ccipCrossChainBridge), "olympus.periphery");
    }
}
