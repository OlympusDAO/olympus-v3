// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {console2} from "@forge-std-1.9.6/console2.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

import {Safe} from "@safe-utils-0.0.13/Safe.sol";
import {Enum} from "safe-smart-account/common/Enum.sol";

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
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
