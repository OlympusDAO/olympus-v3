// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {console2} from "@forge-std-1.9.6/console2.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";
import {stdJson} from "@forge-std-1.9.6/StdJson.sol";

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

import {Safe} from "@safe-utils-0.0.13/Safe.sol";

/// @title BatchScriptV2
/// @notice A script that can be used to propose/execute a batch of transactions to a Safe Multisig or an EOA
abstract contract BatchScriptV2 is WithEnvironment {
    using Safe for *;
    using stdJson for string;

    /// @notice Address of the owner
    /// @dev    This could be a Safe Multisig or an EOA
    address internal _owner;

    bool internal _isMultiSig;
    Safe.Client internal _multiSig;
    address[] internal _batchTargets;
    bytes[] internal _batchData;

    string internal _argsFile;

    // TODOs
    // [ ] Add Ledger signer support
    // [X] Check for --broadcast flag before proposing batch
    // [X] Simulate batch before proposing

    function _setUp(string memory chain_, bool useDaoMS_, string memory argsFilePath_) internal {
        console2.log("Setting up batch script");

        _loadEnv(chain_);
        _loadArgs(argsFilePath_);

        address owner = msg.sender;
        if (useDaoMS_) owner = _envAddressNotZero("olympus.multisig.dao");
        _setUpBatchScript(owner);
    }

    modifier setUp(string memory chain_, bool useDaoMS_, string memory argsFilePath_) {
        _setUp(chain_, useDaoMS_, argsFilePath_);
        _;
    }

    modifier setUpWithChainIdAndArgsFile(bool useDaoMS_, string memory argsFilePath_) {
        string memory chainName = ChainUtils._getChainName(block.chainid);
        _setUp(chainName, useDaoMS_, argsFilePath_);
        _;
    }

    modifier setUpWithChainId(bool useDaoMS_) {
        string memory chainName = ChainUtils._getChainName(block.chainid);
        _setUp(chainName, useDaoMS_, "");
        _;
    }

    function _setUpBatchScript(address owner_) internal {
        // Validate that the owner is not the forge default deployer
        if (owner_ == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            // solhint-disable-next-line gas-custom-errors
            revert("BatchScriptV2: Owner cannot be the forge default deployer");
        }

        _owner = owner_;
        console2.log("  Owner address", _owner);

        // Check if the owner is a Safe Multisig
        // It is assumed to be if it is a contract
        if (_owner.code.length > 0) {
            console2.log("  Owner address is a multi-sig");
            _isMultiSig = true;
            _multiSig.initialize(_owner);
        } else {
            console2.log("  Owner address is an EOA");
            _isMultiSig = false;
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

        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Batch simulation completed");
            return;
        }

        console2.log("\n");
        console2.log("Proposing batch to multi-sig");

        bytes32 txHash = _multiSig.proposeTransactions(
            _batchTargets,
            _batchData,
            msg.sender,
            ""
        );

        console2.log("Proposal created");
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
            _argsFile = vm.readFile(argsFilePath_);
        }
    }

    /// @notice Get a string argument for a given function and key
    /// @param functionName_ Name of the function
    /// @param key_ Key to look for
    /// @return string Returns the string value
    function _readBatchArgString(
        string memory functionName_,
        string memory key_
    ) internal view returns (string memory) {
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
        require(bytes(_argsFile).length > 0, "BatchScriptV2: No args file loaded");
        return
            _argsFile.readUint(
                string.concat(".functions[?(@.name == '", functionName_, "')].args.", key_)
            );
    }

    /// @notice Get address from environment file using "last" version
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file, or the zero address
    function _envLastAddress(string memory key_) internal view returns (address) {
        bool isDebug = _isDebugLogLevel();

        if (isDebug) console2.log("  Checking in env.json for", key_, "on", chain, "(last version)");
        string memory fullKey = string.concat(".last.", chain, ".", key_);
        address addr;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            addr = env.readAddress(fullKey);
            if (isDebug) console2.log("    %s: %s (from env.json - last)", key_, addr);
        } else {
            if (isDebug) console2.log("    %s: *** NOT FOUND (last) ***", key_);
        }

        return addr;
    }
}
