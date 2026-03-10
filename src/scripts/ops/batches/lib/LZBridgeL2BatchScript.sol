// SPDX-License-Identifier: Unlicensed
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {LZBridgeBatchScript} from "./LZBridgeBatchScript.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";
import {VmSafe} from "@forge-std-1.9.6/Vm.sol";

/// @title LZBridgeL2BatchScript
/// @notice Abstract base for LZ bridge batch scripts on L2 chains.
///         Extends LZBridgeBatchScript with `_proposeL2Batch()` which skips
///         heart beat validation (L2 chains don't have OlympusHeart).
abstract contract LZBridgeL2BatchScript is LZBridgeBatchScript {
    /// @notice Custom batch proposal for L2 chains that skips heart beat validation.
    /// @dev L2 chains don't have OlympusHeart, so _validateHeartBeat() would revert.
    function _proposeL2Batch() internal {
        if (_batchTargets.length == 0) {
            console2.log("No batch targets to execute");
            return;
        }

        console2.log("\n");
        console2.log("=== Proposing L2 batch (no heart beat validation) ===");

        // Simulate and validate with snapshot/revert (without heart beat)
        {
            uint256 snapshotId = vm.snapshotState();
            console2.log("Created snapshot before simulation, id:", snapshotId);

            // Simulate batch execution
            console2.log("Simulating execution of batch");
            vm.startPrank(_owner);
            _runBatch();
            vm.stopPrank();
            console2.log("Batch simulation completed");

            // Run custom post-batch validation (if set)
            _runPostBatchValidation();

            // Revert to snapshot
            vm.revertToStateAndDelete(snapshotId);
            console2.log("Restored state from snapshot");
        }

        // Check execution mode
        bool useAnvilFork = vm.envOr("USE_ANVIL_FORK", false);
        bool useTenderlyFork = vm.envOr("USE_TENDERLY_FORK", false);

        if (useAnvilFork) {
            if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                console2.log("Not broadcasting, skipping Anvil fork execution");
                return;
            }
            console2.log("\nBroadcasting batch to Anvil fork");
            vm.startBroadcast(_owner);
            for (uint256 i; i < _batchTargets.length; ++i) {
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
            return;
        }

        if (useTenderlyFork) {
            console2.log("Tenderly fork not supported for L2 batch, use standard proposeBatch");
            return;
        }

        // Normal execution: multisig or EOA
        if (_isMultiSig) {
            if (_signOnly) {
                console2.log("signOnly is true, sign the batch");
                return;
            }

            if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                console2.log("Not broadcasting, skipping multisig proposal");
                return;
            }

            console2.log("\nBroadcasting batch to Multisig");
            bytes32 txHash = _proposeMultisigBatchTransactions();
            console2.log("Batch created");
            console2.logBytes32(txHash);
        } else {
            if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
                console2.log("Not broadcasting, skipping EOA execution");
                return;
            }

            console2.log("\nBroadcasting batch to EOA");
            vm.startBroadcast();
            _runBatch();
            vm.stopBroadcast();
            console2.log("Batch executed successfully");
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
