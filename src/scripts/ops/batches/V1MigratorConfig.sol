// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";

/// @notice V1Migrator batch script for admin operations
contract V1MigratorConfig is BatchScriptV2 {
    /// @notice Expected merkle root for post-batch validation
    bytes32 internal _expectedMerkleRoot;

    /// @notice Set the merkle root for eligible claims on V1Migrator
    /// @dev    When setting a new merkle root, the nonce increments which resets all
    ///         previous migration tracking. The new merkle tree should reflect the
    ///         amount each user can migrate going forward (i.e., their current OHM v1
    ///         balance minus any already migrated amounts).
    function setMerkleRoot(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        // Get addresses from environment
        address v1Migrator = _envAddressNotZero("olympus.policies.V1Migrator");

        console2.log("=== Setting Merkle Root on V1Migrator ===");
        console2.log("V1Migrator:", v1Migrator);

        // Read the new merkle root from args file
        bytes32 newMerkleRoot = _readBatchArgBytes32("setMerkleRoot", "merkleRoot");

        console2.log("New Merkle Root:");
        console2.logBytes32(newMerkleRoot);

        // Set merkle root on V1Migrator
        addToBatch(
            v1Migrator,
            abi.encodeWithSelector(IV1Migrator.setMerkleRoot.selector, newMerkleRoot)
        );

        // Store expected value for post-batch validation
        _expectedMerkleRoot = newMerkleRoot;

        console2.log("Merkle root set on V1Migrator");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateSetMerkleRootPostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate setMerkleRoot state after batch execution
    /// @dev    Validates that the merkle root has been updated correctly
    function _validateSetMerkleRootPostBatch() external view {
        address v1Migrator = _envAddressNotZero("olympus.policies.V1Migrator");

        console2.log("\n Validating setMerkleRoot Post-Batch State ");

        // Validate merkle root was set correctly
        bytes32 actualMerkleRoot = IV1Migrator(v1Migrator).merkleRoot();
        if (actualMerkleRoot != _expectedMerkleRoot) {
            revert(
                string.concat(
                    "Merkle root should be ",
                    vm.toString(_expectedMerkleRoot),
                    ", but is ",
                    vm.toString(actualMerkleRoot)
                )
            );
        }
        console2.log("Merkle root:");
        console2.logBytes32(actualMerkleRoot);
        console2.log("Expected root:");
        console2.logBytes32(_expectedMerkleRoot);

        console2.log("setMerkleRoot post-batch validation passed");
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
