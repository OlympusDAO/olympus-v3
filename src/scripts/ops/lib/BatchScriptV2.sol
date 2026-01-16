// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {console2} from "@forge-std-1.9.6/console2.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

import {Safe} from "@safe-utils-0.0.17/Safe.sol";
import {Enum} from "safe-smart-account/common/Enum.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {Kernel, toKeycode} from "src/Kernel.sol";

/// @title BatchScriptV2
/// @notice A script that can be used to propose/execute a batch of transactions to a Safe Multisig or an EOA
abstract contract BatchScriptV2 is WithEnvironment {
    using Safe for *;
    using stdJson for string;

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

    /// @notice Set the post-batch validation function selector
    /// @param selector_ The function selector to call after batch simulation
    function _setPostBatchValidateSelector(bytes4 selector_) internal {
        _postBatchValidateSelector = selector_;
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

    function _proposeMultisigBatch() internal {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to propose");
            return;
        }

        console2.log("\n");
        console2.log("Simulating execution of batch");
        vm.startPrank(_owner);
        _runBatch();
        vm.stopPrank();
        console2.log("Batch simulation completed");

        // Call custom post-batch validation if selector is set (before heartbeats)
        if (_postBatchValidateSelector != bytes4(0)) {
            console2.log("\n=== Starting post-batch validation ===");
            console2.log("Calling post-batch validation function");
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(_postBatchValidateSelector)
            );
            if (!success) {
                // Revert with the error data
                assembly {
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
            console2.log("Post-batch validation passed");
        } else {
            console2.log("\nNo post-batch validation selector set, skipping validation");
        }

        // Validate heart beat after batch execution and post-batch validation
        _validateHeartBeat();

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

        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Not broadcasting, skipping batch proposal");
            return;
        }

        console2.log("\n");
        console2.log("Proposing batch to multi-sig");

        bytes32 txHash = _proposeMultisigBatchTransactions();

        console2.log("Batch created");
        console2.logBytes32(txHash);
    }

    function _proposeEOABatch() internal {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to propose");
            return;
        }

        console2.log("\n");
        console2.log("Executing batch as EOA");

        vm.startBroadcast();

        _runBatch();

        vm.stopBroadcast();

        console2.log("Batch executed");

        // Call custom post-batch validation if selector is set
        if (_postBatchValidateSelector != bytes4(0)) {
            console2.log("\n=== Starting post-batch validation ===");
            console2.log("Calling post-batch validation function");
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(_postBatchValidateSelector)
            );
            if (!success) {
                // Revert with the error data
                assembly {
                    let revertStringLength := mload(data)
                    let revertStringPtr := add(data, 0x20)
                    revert(revertStringPtr, revertStringLength)
                }
            }
            console2.log("Post-batch validation passed");
        } else {
            console2.log("\nNo post-batch validation selector set, skipping validation");
        }
    }

    function proposeBatch() public {
        if (_isMultiSig) {
            _proposeMultisigBatch();
        } else {
            _proposeEOABatch();
        }
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
    ///         Restores original timestamp and thresholds after validation to avoid signature issues
    function _validateHeartBeat() internal {
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");
        console2.log("\n=== Validating heart beat (full 24-hour cycle - 3 beats) ===");
        console2.log("Heart address:", heart);

        OlympusHeart heartContract = OlympusHeart(heart);
        PRICEv1 priceModule = _getPriceModule(heartContract);
        address priceConfig = _envAddressNotZero("olympus.policies.OlympusPriceConfig");

        uint256 originalTimestamp = block.timestamp;
        uint48 originalOhmEthThreshold = priceModule.ohmEthUpdateThreshold();
        uint48 originalReserveEthThreshold = priceModule.reserveEthUpdateThreshold();
        uint48 lastBeat = uint48(heartContract.lastBeat());
        uint48 frequency = heartContract.frequency();

        console2.log("Last beat:", lastBeat, "Frequency:", frequency);
        console2.log("Original thresholds - OHM/ETH:", originalOhmEthThreshold, "Reserve/ETH:", originalReserveEthThreshold);

        // Temporarily increase thresholds to 2 days to cover time warp
        uint48 tempThreshold = uint48(2 days);
        console2.log("Temporarily increasing update thresholds to:", tempThreshold);
        vm.prank(priceConfig);
        priceModule.changeUpdateThresholds(tempThreshold, tempThreshold);

        bool timeWarped = _executeHeartBeats(heartContract, lastBeat, frequency);

        console2.log("\nAll heart beats validated successfully");
        console2.log("Restoring original update thresholds");
        vm.prank(priceConfig);
        priceModule.changeUpdateThresholds(originalOhmEthThreshold, originalReserveEthThreshold);

        if (timeWarped) {
            console2.log("Restoring original timestamp:", originalTimestamp);
            vm.warp(originalTimestamp);
        }
    }

    /// @notice Get PRICE module from Heart and verify version is 1.0 or 1.1
    /// @param heartContract_ Heart contract to get kernel from
    /// @return priceModule PRICE module instance
    function _getPriceModule(OlympusHeart heartContract_) internal view returns (PRICEv1) {
        Kernel kernel = heartContract_.kernel();
        PRICEv1 priceModule = PRICEv1(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        (uint8 major, uint8 minor) = priceModule.VERSION();
        if (major != 1 || (minor != 0 && minor != 1)) revert("PRICE must be v1.0 or v1.1");
        console2.log("PRICE module version verified: v1.", uint256(minor));
        return priceModule;
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
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
