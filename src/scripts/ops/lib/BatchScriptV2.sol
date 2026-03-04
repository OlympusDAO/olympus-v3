// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity >=0.8.15;

// Interfaces
import {console2} from "@forge-std-1.9.6/console2.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";

// Libraries
import {Surl} from "@surl-1.0.0/Surl.sol";

// Scripts
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

// External
import {Safe} from "@safe-utils-0.0.17/Safe.sol";
import {Enum} from "safe-smart-account/common/Enum.sol";

// Bophades
import {Kernel, toKeycode} from "src/Kernel.sol";
import {SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";

/// @title BatchScriptV2
/// @notice A script that can be used to propose/execute a batch of transactions to a Safe Multisig or an EOA
abstract contract BatchScriptV2 is WithEnvironment {
    using Safe for *;
    using stdJson for string;
    using Surl for *;

    /// @notice Address of the owner
    /// @dev    This could be a Safe Multisig or an EOA
    address internal _owner;

    /// @notice Whether the owner is a Safe Multisig
    bool internal _isMultiSig;

    /// @notice Whether to only sign the batch without proposing/executing it
    /// @dev    Provided to setUp modifiers
    bool internal _signOnly;

    /// @notice safe-utils client
    Safe.Client internal _multiSig;

    /// @notice Array of the target addresses for the batch
    /// @dev    Loaded by {_runBatch()}
    address[] internal _batchTargets;

    /// @notice Array of the calldata for the batch
    /// @dev    Loaded by {_runBatch()}
    bytes[] internal _batchData;

    /// @notice Contents of the arguments file
    /// @dev    Loaded by {_loadArgs}
    string internal _argsFile;

    /// @notice Derivation path for Ledger signing (if applicable)
    /// @dev    Loaded by {_setUpBatchScript}
    string internal _ledgerDerivationPath;

    /// @notice Optional signature for the batch
    /// @dev    Loaded by {_setUpBatchScript}
    ///         If this is provided, the batch will be proposed using the signature instead of asking the sender to sign
    bytes internal _signature;

    /// @notice Optional post-batch validation function selector
    /// @dev    If set, this function will be called after batch simulation to validate state
    bytes4 internal _postBatchValidateSelector;

    // TODOs
    // [X] Add Ledger signer support
    // [X] Check for --broadcast flag before proposing batch
    // [X] Simulate batch before proposing

    function _setUp(string memory chain_, bool useDaoMS_, bool signOnly_, string memory argsFilePath_, string memory ledgerDerivationPath_, bytes memory signature_) internal {
        console2.log("Setting up batch script");

        _loadEnv(chain_);
        _loadArgs(argsFilePath_);

        address owner = msg.sender;
        if (useDaoMS_) owner = _envAddressNotZero("olympus.multisig.dao");
        _setUpBatchScript(signOnly_, owner, ledgerDerivationPath_, signature_);
    }

    modifier setUp(bool useDaoMS_, bool signOnly_, string memory argsFilePath_, string memory ledgerDerivationPath_, bytes memory signature_) {
        string memory chainName = ChainUtils._getChainName(block.chainid);
        _setUp(chainName, useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath_, signature_);
        _;
    }

    /// @dev    Deprecated.
    modifier setUpWithChainId(bool useDaoMS_) {
        string memory chainName = ChainUtils._getChainName(block.chainid);
        _setUp(chainName, useDaoMS_, false, "", "", "");
        _;
    }

    function _hasSignature() internal view returns (bool) {
        return bytes(_signature).length > 0;
    }

    function _setUpBatchScript(bool signOnly_, address owner_, string memory ledgerDerivationPath_, bytes memory signature_) internal {
        // Validate that the owner is not the forge default deployer
        if (owner_ == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            // solhint-disable-next-line gas-custom-errors
            revert("BatchScriptV2: Owner cannot be the forge default deployer");
        }

        _owner = owner_;
        console2.log("  Owner address", _owner);

        // Check if the owner is a Safe Multisig
        // It is assumed to be if it is a contract
        // Skip this check if FORK environment variable is true
        // This allows pranking when using a local anvil fork
        bool skipCodeCheck = vm.envOr("FORK", false);
        if (!skipCodeCheck && _owner.code.length > 0) {
            console2.log("  Owner address is a multi-sig");
            _isMultiSig = true;
            _multiSig.initialize(_owner);
        } else {
            console2.log("  Owner address is an EOA");
            _isMultiSig = false;
        }

        _signOnly = signOnly_;
        console2.log("  Sign only", _signOnly);

        _signature = signature_;
        if (_hasSignature()) {
            console2.log("  Signature provided");
        } else {
            console2.log("  No signature provided");
        }

        // If signOnly is true, no signature should be provided
        if (signOnly_ && _hasSignature()) {
            revert("BatchScriptV2: Cannot provide signature when signOnly is true");
        }

        _ledgerDerivationPath = ledgerDerivationPath_;
        if (bytes(_ledgerDerivationPath).length > 0) {
            console2.log("  Ledger derivation path provided:", _ledgerDerivationPath);
        } else {
            console2.log("  No Ledger derivation path provided");
        }
    }

    /// @notice Set the post-batch validation function selector
    /// @param selector_ The function selector to call after batch simulation
    function _setPostBatchValidateSelector(bytes4 selector_) internal {
        _postBatchValidateSelector = selector_;
    }

    function addToBatch(address target_, bytes memory data_) public {
        _batchTargets.push(target_);
        _batchData.push(data_);
    }

    function _runBatch() internal {
        // Iterate over each batch target and execute
        for (uint256 i; i < _batchTargets.length; i++) {
            console2.log("  Executing batch target", i);
            console2.log("  Target", _batchTargets[i]);
            (bool success, bytes memory data) = _batchTargets[i].call(_batchData[i]);

            // Revert if the call failed
            // Source: https://ethereum.stackexchange.com/a/150367
            if (!success) {
                assembly{
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
        }
    }

    /// @notice Get the nonce to use for the batch
    /// @dev    If a nonce is provided using the "SAFE_NONCE" environment variable, it will be used. Otherwise the Safe's nonce will be used.
    ///
    /// @return nonce The nonce to use for the batch
    function _getNonce() internal view returns (uint256 nonce) {
        // Determine the nonce to use
        nonce = _multiSig.getNonce();
        {
            try vm.envUint("SAFE_NONCE") returns (uint256 nonce_) {
                console2.log("  Using nonce from environment:", nonce_);
                nonce = nonce_;
            } catch {
                // Do nothing
                console2.log("  No nonce provided in environment, using Safe nonce:", nonce);
            }
        }

        return nonce;
    }

    function _proposeMultisigBatchTransactions() internal returns (bytes32 txHash) {
        if (_signOnly) {
            revert("BatchScriptV2: Cannot propose batch when signOnly is true");
        }

        uint256 nonce = _getNonce();

        // Get tx data
        (address to, bytes memory data) = _multiSig.getProposeTransactionsTargetAndData(_batchTargets, _batchData);

        // Prepare the tx params
        Safe.ExecTransactionParams memory params = Safe.ExecTransactionParams({
            to: to,
            value: 0,
            data: data,
            operation: Enum.Operation.DelegateCall,
            sender: msg.sender,
            signature: _signature, // Empty signature, will be signed later
            nonce: nonce
        });

        // If there is no signature, get the signature
        if (!_hasSignature()) {
            console2.log("  No signature provided, getting signature");
            bytes memory signature = _multiSig.sign(
                to,
                data,
                Enum.Operation.DelegateCall,
                msg.sender,
                nonce,
                "" // No derivation path
            );
            params.signature = signature;
        }
        else {
            console2.log("  Using provided signature");
        }

        console2.log("  Submitting transaction");
        txHash = _multiSig.proposeTransaction(params);

        return txHash;
    }

    /// @notice Execute batch via Multisig with proposal
    /// @dev    Simulates, validates, and proposes batch transactions to the multisig
    function _sendMultisigBatch() internal {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to execute");
            return;
        }

        console2.log("\n");
        console2.log("=== Executing batch via Multisig ===");

        // Simulate and validate with snapshot/revert
        _validateWithSnapshot();

        // If signOnly, get the signature and return
        if (_signOnly) {
            console2.log("signOnly is true, approve the request to sign the batch");

            uint256 nonce = _getNonce();

            (address to, bytes memory data) = _multiSig.getProposeTransactionsTargetAndData(_batchTargets, _batchData);

            // This will revert if the user is using a Ledger and the derivation path is not provided
            bytes memory signature = _multiSig.sign(
                to,
                data,
                Enum.Operation.DelegateCall,
                msg.sender,
                nonce,
                _ledgerDerivationPath
            );
            console2.log("Batch signed. Signature:");
            console2.logBytes(signature);
            return;
        }

        // Check if we're in broadcast mode before proposing
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping multisig proposal");
            return;
        }

        console2.log("\nBroadcasting batch to Multisig");

        bytes32 txHash = _proposeMultisigBatchTransactions();

        console2.log("Batch created");
        console2.logBytes32(txHash);
    }

    /// @notice Execute batch via EOA with broadcast
    /// @dev    Simulates and validates first, then executes if broadcast mode is enabled
    function _sendEOABatch() internal {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to execute");
            return;
        }

        console2.log("\n");
        console2.log("=== Executing batch via EOA ===");

        // Simulate and validate with snapshot/revert
        _validateWithSnapshot();

        // Check if we're in broadcast mode before executing
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping EOA execution");
            return;
        }

        // Execute batch on EOA with broadcast
        console2.log("\nBroadcasting batch to EOA");
        vm.startBroadcast();

        _runBatch();

        vm.stopBroadcast();

        console2.log("Batch executed successfully");
    }

    function proposeBatch() public {
        bool useAnvilFork = vm.envOr("USE_ANVIL_FORK", false);
        bool useTenderlyFork = vm.envOr("USE_TENDERLY_FORK", false);

        // Reject mutually exclusive fork flags
        if (useAnvilFork && useTenderlyFork) {
            revert("BatchScriptV2: USE_ANVIL_FORK and USE_TENDERLY_FORK are mutually exclusive");
        }

        // Handle fork modes first
        if (useAnvilFork) {
            _sendAnvilBatch();
            return;
        }

        if (useTenderlyFork) {
            _sendTenderlyBatch();
            return;
        }

        // Normal execution path
        if (_isMultiSig) {
            _sendMultisigBatch();
        } else {
            _sendEOABatch();
        }
    }

    /// @notice Execute batch via Anvil fork with auto-impersonation
    /// @dev    Uses vm.startBroadcast with the multisig address to impersonate signers
    function _sendAnvilBatch() private {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to execute");
            return;
        }

        console2.log("\n");
        console2.log("=== Executing batch via Anvil fork ===");

        // Simulate and validate with snapshot/revert
        _validateWithSnapshot();

        // Check if we're in broadcast mode before executing on Anvil fork
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping Anvil fork execution");
            return;
        }

        // Execute batch on Anvil fork with auto-impersonation
        console2.log("\nBroadcasting batch to Anvil fork");
        vm.startBroadcast(_owner);

        for (uint256 i; i < _batchTargets.length; i++) {
            console2.log("  Executing batch target", i);
            console2.log("  Target", _batchTargets[i]);
            (bool success, bytes memory data) = _batchTargets[i].call(_batchData[i]);

            if (!success) {
                assembly {
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
        }

        vm.stopBroadcast();
        console2.log("Batch executed successfully on Anvil fork");
    }

    /// @notice Execute batch via Tenderly VNet using HTTP API calls
    /// @dev    Sends transactions to Tenderly VNet for execution without requiring private keys
    function _sendTenderlyBatch() private {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to execute");
            return;
        }

        console2.log("\n");
        console2.log("=== Executing batch via Tenderly VNet ===");

        // Simulate and validate with snapshot/revert (newly added)
        _validateWithSnapshot();

        // Check if we're in broadcast mode before executing on Tenderly VNet
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping Tenderly VNet execution");
            return;
        }

        // Get the testnet RPC URL and access key
        string memory TENDERLY_ACCOUNT_SLUG = vm.envString("TENDERLY_ACCOUNT_SLUG");
        string memory TENDERLY_PROJECT_SLUG = vm.envString("TENDERLY_PROJECT_SLUG");
        string memory TENDERLY_VNET_ID = vm.envString("TENDERLY_VNET_ID");
        string memory TENDERLY_ACCESS_KEY = vm.envString("TENDERLY_ACCESS_KEY");

        // Iterate over the batch targets and execute them
        for (uint256 i; i < _batchTargets.length; i++) {
            console2.log("  Executing batch target", i);
            console2.log("  Target", _batchTargets[i]);

            // Construct the API call
            string[] memory headers = new string[](3);
            headers[0] = "Accept: application/json";
            headers[1] = "Content-Type: application/json";
            headers[2] = string.concat("X-Access-Key: ", TENDERLY_ACCESS_KEY);

            string memory url = string.concat(
                "https://api.tenderly.co/api/v1/account/",
                TENDERLY_ACCOUNT_SLUG,
                "/project/",
                TENDERLY_PROJECT_SLUG,
                "/vnets/",
                TENDERLY_VNET_ID,
                "/transactions"
            );

            // Execute the API call
            (uint256 status, bytes memory response) = url.post(
                headers,
                string.concat(
                    "{",
                    '"callArgs": {',
                    '"from": "',
                    vm.toString(_owner),
                    '", "to": "',
                    vm.toString(_batchTargets[i]),
                    '", "gas": "0x7a1200", "gasPrice": "0x10", "value": "0x0", ',
                    '"data": "',
                    vm.toString(_batchData[i]),
                    '"',
                    "}}"
                )
            );

            string memory responseString = string(response);
            console2.log("  Response:", responseString);

            // If the response contains "error", exit
            if (status >= 400 || vm.keyExists(responseString, ".error")) {
                revert("Error executing batch action on Tenderly VNet");
            }
        }

        console2.log("Batch executed successfully on Tenderly VNet");
    }

    /// @notice Load arguments from a file (optional)
    /// @param argsFilePath_ Path to the arguments file
    function _loadArgs(string memory argsFilePath_) internal {
        if (bytes(argsFilePath_).length > 0) {
            console2.log("Loading arguments from", argsFilePath_);
            /// forge-lint: disable-next-line(unsafe-cheatcode)
            _argsFile = vm.readFile(argsFilePath_);
        }
    }

    function _validateArgsFileEmpty(string memory argsFilePath_) internal pure {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(argsFilePath_).length == 0, "BatchScriptV2: Args file should be empty for this function");
    }

    /// @notice Get a string argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return string Returns the string value
    function _readBatchArgString(
        string memory functionName_,
        string memory key_
    ) internal view returns (string memory) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readString(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    /// @notice Get a bool argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return bool Returns the bool value
    function _readBatchArgBool(
        string memory functionName_,
        string memory key_
    ) internal view returns (bool) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readBool(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    /// @notice Get a bytes32 argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return bytes32 Returns the bytes32 value
    function _readBatchArgBytes32(
        string memory functionName_,
        string memory key_
    ) internal view returns (bytes32) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readBytes32(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    /// @notice Get an address argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return address Returns the address value
    function _readBatchArgAddress(
        string memory functionName_,
        string memory key_
    ) internal view returns (address) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readAddress(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    /// @notice Get a uint256 argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return uint256 Returns the uint256 value
    function _readBatchArgUint256(
        string memory functionName_,
        string memory key_
    ) internal view returns (uint256) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readUint(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    function _readBatchArgUint256Array(
        string memory functionName_,
        string memory key_
    ) internal view returns (uint256[] memory) {
        // solhint-disable-next-line gas-custom-errors
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readUintArray(string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_));
    }

    /// @notice Validate that heart beat will work after batch execution
    /// @dev    Warps through a full 24-hour cycle (3 beats) and calls beat() to validate
    ///         Temporarily increases price feed update thresholds to prevent stale feed errors
    ///         State is restored by _validateWithSnapshot() which calls vm.revertToStateAndDelete
    function _validateHeartBeat() internal {
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");
        console2.log("\n=== Validating heart beat (full 24-hour cycle - 3 beats) ===");
        console2.log("Heart address:", heart);

        OlympusHeart heartContract = OlympusHeart(heart);
        IPRICEv2 priceModule = _getPriceModule(heartContract);
        address priceConfig = _envAddressNotZero("olympus.policies.OlympusPriceConfigV2");

        uint256 originalTimestamp = block.timestamp;
        uint48 lastBeat = uint48(heartContract.lastBeat());
        uint48 frequency = heartContract.frequency();

        console2.log("Last beat:", lastBeat, "Frequency:", frequency);

        // Update all price feed thresholds to at least 2 days to cover time warp
        _updatePriceFeedThresholds(priceModule, priceConfig);

        bool timeWarped = _executeHeartBeats(heartContract, lastBeat, frequency);

        console2.log("\nAll heart beats validated successfully");

        if (timeWarped) {
            console2.log("Restoring original timestamp:", originalTimestamp);
            vm.warp(originalTimestamp);
        }
    }

    /// @notice Get PRICE module from Heart and verify version is 1.2+
    /// @param heartContract_ Heart contract to get kernel from
    /// @return priceModule PRICE module instance
    function _getPriceModule(OlympusHeart heartContract_) internal view returns (IPRICEv2) {
        Kernel kernel = heartContract_.kernel();
        IPRICEv2 priceModule = IPRICEv2(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        // Version check is handled by trying to call IPRICEv2 functions
        // If the module doesn't support IPRICEv2, calls will revert
        return priceModule;
    }

    /// @notice Update price feed thresholds for all assets to at least 2 days
    /// @dev    Iterates over all assets and their feeds, updating thresholds as needed
    /// @param priceModule_ PRICE module to get assets from
    /// @param priceConfig_ PriceConfig policy to call updateAsset on
    function _updatePriceFeedThresholds(IPRICEv2 priceModule_, address priceConfig_) internal {
        uint48 twoDays = uint48(2 days);
        address daoMS = _envAddressNotZero("olympus.multisig.dao");

        address[] memory assets = priceModule_.getAssets();
        console2.log("Updating price feed thresholds for", assets.length, "assets");

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            IPRICEv2.Asset memory assetData = priceModule_.getAssetData(asset);

            if (!assetData.approved) continue;

            IPRICEv2.Component[] memory feeds = abi.decode(assetData.feeds, (IPRICEv2.Component[]));
            bool needsUpdate = false;

            // Check each feed and update thresholds if needed
            for (uint256 j = 0; j < feeds.length; j++) {
                bytes memory newParams = _updateFeedThreshold(feeds[j], twoDays);
                if (newParams.length > 0) {
                    feeds[j].params = newParams;
                    needsUpdate = true;
                }
            }

            // Update the asset if any feeds were modified
            if (needsUpdate) {
                console2.log("  Updating thresholds for asset:", asset);
                IPRICEv2.UpdateAssetParams memory params = IPRICEv2.UpdateAssetParams({
                    updateFeeds: true,
                    updateStrategy: false,
                    updateMovingAverage: false,
                    feeds: feeds,
                    strategy: IPRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), ""),
                    useMovingAverage: false,
                    storeMovingAverage: false,
                    movingAverageDuration: 0,
                    lastObservationTime: 0,
                    observations: new uint256[](0)
                });

                vm.prank(daoMS);
                PriceConfigv2(priceConfig_).updateAsset(asset, params);
            }
        }
    }

    /// @notice Update a single feed's threshold if needed
    /// @dev    Determines feed type based on SubKeycode and updates threshold if below minimum
    /// @param feed_ Feed component to check/update
    /// @param minThreshold_ Minimum threshold to enforce (2 days)
    /// @return New encoded params if updated, empty bytes if no update needed
    function _updateFeedThreshold(
        IPRICEv2.Component memory feed_,
        uint48 minThreshold_
    ) internal pure returns (bytes memory) {
        // Get the underlying bytes20 for comparison
        bytes20 targetBytes = SubKeycode.unwrap(feed_.target);

        // Skip UniswapV3 - uses observationWindowSeconds, not updateThreshold
        if (targetBytes == SubKeycode.unwrap(toSubKeycode("PRICE.UNIV3"))) {
            return new bytes(0);
        }

        // Handle Chainlink feeds
        if (targetBytes == SubKeycode.unwrap(toSubKeycode("PRICE.CHAINLINK"))) {
            return _updateChainlinkThreshold(feed_.params, feed_.selector, minThreshold_);
        }

        // Handle Pyth feeds
        if (targetBytes == SubKeycode.unwrap(toSubKeycode("PRICE.PYTH"))) {
            return _updatePythThreshold(feed_.params, feed_.selector, minThreshold_);
        }

        // Unknown feed type - skip
        return new bytes(0);
    }

    /// @notice Update Chainlink feed thresholds if below minimum
    /// @param params_ Encoded feed parameters
    /// @param selector_ Function selector to determine feed type
    /// @param minThreshold_ Minimum threshold to enforce
    /// @return New encoded params if updated, empty bytes if no update needed
    function _updateChainlinkThreshold(
        bytes memory params_,
        bytes4 selector_,
        uint48 minThreshold_
    ) internal pure returns (bytes memory) {
        // OneFeedParams: getOneFeedPrice
        if (selector_ == ChainlinkPriceFeeds.getOneFeedPrice.selector) {
            ChainlinkPriceFeeds.OneFeedParams memory p =
                abi.decode(params_, (ChainlinkPriceFeeds.OneFeedParams));
            if (p.updateThreshold < minThreshold_) {
                p.updateThreshold = minThreshold_;
                return abi.encode(p);
            }
            return new bytes(0);
        }

        // TwoFeedParams: getTwoFeedPriceDiv or getTwoFeedPriceMul
        if (selector_ == ChainlinkPriceFeeds.getTwoFeedPriceDiv.selector ||
            selector_ == ChainlinkPriceFeeds.getTwoFeedPriceMul.selector) {
            ChainlinkPriceFeeds.TwoFeedParams memory p =
                abi.decode(params_, (ChainlinkPriceFeeds.TwoFeedParams));
            bool updated = false;

            if (p.firstUpdateThreshold < minThreshold_) {
                p.firstUpdateThreshold = minThreshold_;
                updated = true;
            }
            if (p.secondUpdateThreshold < minThreshold_) {
                p.secondUpdateThreshold = minThreshold_;
                updated = true;
            }

            return updated ? abi.encode(p) : new bytes(0);
        }

        return new bytes(0);
    }

    /// @notice Update Pyth feed thresholds if below minimum
    /// @param params_ Encoded feed parameters
    /// @param selector_ Function selector to determine feed type
    /// @param minThreshold_ Minimum threshold to enforce
    /// @return New encoded params if updated, empty bytes if no update needed
    function _updatePythThreshold(
        bytes memory params_,
        bytes4 selector_,
        uint48 minThreshold_
    ) internal pure returns (bytes memory) {
        // OneFeedParams: getOneFeedPrice
        if (selector_ == PythPriceFeeds.getOneFeedPrice.selector) {
            PythPriceFeeds.OneFeedParams memory p =
                abi.decode(params_, (PythPriceFeeds.OneFeedParams));
            if (p.updateThreshold < minThreshold_) {
                p.updateThreshold = minThreshold_;
                return abi.encode(p);
            }
            return new bytes(0);
        }

        // TwoFeedParams: getTwoFeedPriceDiv or getTwoFeedPriceMul
        if (selector_ == PythPriceFeeds.getTwoFeedPriceDiv.selector ||
            selector_ == PythPriceFeeds.getTwoFeedPriceMul.selector) {
            PythPriceFeeds.TwoFeedParams memory p =
                abi.decode(params_, (PythPriceFeeds.TwoFeedParams));
            bool updated = false;

            if (p.firstUpdateThreshold < minThreshold_) {
                p.firstUpdateThreshold = minThreshold_;
                updated = true;
            }
            if (p.secondUpdateThreshold < minThreshold_) {
                p.secondUpdateThreshold = minThreshold_;
                updated = true;
            }

            return updated ? abi.encode(p) : new bytes(0);
        }

        return new bytes(0);
    }

    /// @notice Execute 3 heart beats for full 24-hour cycle validation
    /// @param heartContract_ Heart contract to call beat() on
    /// @param lastBeat_ Last beat timestamp
    /// @param frequency_ Beat frequency
    /// @return timeWarped_ Whether time was warped during validation
    function _executeHeartBeats(OlympusHeart heartContract_, uint48 lastBeat_, uint48 frequency_) internal returns (bool timeWarped_) {
        uint256 numBeats = 3;
        uint48 lastBeat = lastBeat_;

        for (uint256 i = 0; i < numBeats; ++i) {
            uint48 nextBeat = lastBeat + frequency_;
            uint48 currentTime = uint48(block.timestamp);

            console2.log("\nBeat", i + 1, "of", numBeats);
            console2.log("Current time:", currentTime, "Next beat time:", nextBeat);

            if (currentTime < nextBeat) {
                console2.log("Warping to next heartbeat timestamp");
                vm.warp(nextBeat);
                timeWarped_ = true;
            }

            console2.log("Calling heart.beat()");
            heartContract_.beat();
            console2.log("Heart beat", i + 1, "validation successful");

            lastBeat = uint48(heartContract_.lastBeat());
        }
    }

    /// @notice Run custom post-batch validation if selector is set
    /// @dev    Calls the function specified by _postBatchValidateSelector
    function _runPostBatchValidation() internal {
        if (_postBatchValidateSelector != bytes4(0)) {
            console2.log("\n=== Starting post-batch validation ===");
            console2.log("Calling post-batch validation function");
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(_postBatchValidateSelector)
            );
            if (!success) {
                assembly {
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
            console2.log("Post-batch validation passed");
        } else {
            console2.log("\nNo post-batch validation selector set, skipping custom validation");
        }
    }

    /// @notice Run simulation and validation with state rollback
    /// @dev    Creates snapshot before simulation, reverts after validation.
    ///         This ensures both simulation AND validation state changes are removed.
    function _validateWithSnapshot() internal {
        // Create snapshot BEFORE simulation (critical!)
        uint256 snapshotId = vm.snapshotState();
        console2.log("Created snapshot before simulation, id:", snapshotId);

        // Simulate batch execution
        console2.log("Simulating execution of batch");
        vm.startPrank(_owner);
        _runBatch();
        vm.stopPrank();
        console2.log("Batch simulation completed");

        // Call custom post-batch validation
        _runPostBatchValidation();

        // Validate heart beat
        _validateHeartBeat();

        // Revert to snapshot - removes BOTH simulation and validation artifacts
        vm.revertToStateAndDelete(snapshotId);
        console2.log("Restored state from snapshot (simulation + validation artifacts removed)");
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
