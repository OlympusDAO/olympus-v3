// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Script} from "@forge-std-1.9.6/Script.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {Safe} from "@safe-utils-0.0.11/Safe.sol";

/// @title BatchScriptV2
/// @notice A script that can be used to propose/execute a batch of transactions to a Safe Multisig or an EOA
abstract contract BatchScriptV2 is Script {
    using Safe for *;

    /// @notice Address of the owner
    /// @dev    This could be a Safe Multisig or an EOA
    address internal _owner;

    bool internal _isMultiSig;
    Safe.Client internal _multiSig;
    address[] internal _batchTargets;
    bytes[] internal _batchData;

    // TODOs
    // [ ] Add Ledger signer support

    function _setUpBatchScript(address owner_) internal {
        _owner = owner_;

        // Check if the owner is a Safe Multisig
        // It is assumed to be if it is a contract
        if (_owner.code.length > 0) {
            console2.log("Owner address is a multi-sig");
            _isMultiSig = true;
            _multiSig.initialize(_owner);
        } else {
            console2.log("Owner address is an EOA");
            _isMultiSig = false;
        }
    }

    function addToBatch(address target_, bytes memory data_) public {
        _batchTargets.push(target_);
        _batchData.push(data_);
    }

    function _proposeMultisigBatch() internal {
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
        vm.startBroadcast();

        // Iterate over each batch target and execute
        for (uint256 i; i < _batchTargets.length; i++) {
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

        vm.stopBroadcast();
    }

    function proposeBatch() public {
        if (_isMultiSig) {
            _proposeMultisigBatch();
        } else {
            _proposeEOABatch();
        }
    }
}
