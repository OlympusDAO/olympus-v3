// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for on-chain.
// forge-lint: disable-start(calls-loop)

// Scripting
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title CCIPQueueLib
/// @notice Reads and describes the queue of a `CCIPTokenPoolConfigTimelock` for the tooling: the
///         unresolved actions, the status of an action at a timestamp, and the config function
///         and route of each sub-action.
/// @dev The timestamp is passed in by the caller, which reads it at simulation time.
library CCIPQueueLib {
    // ========== CONSTANTS ========== //

    VmSafe internal constant _VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    // ========== DATA STRUCTURES ========== //

    /// @notice The status of an unresolved action at a timestamp.
    /// @param Delayed The delay has not elapsed.
    /// @param Executable The delay has elapsed and the execution window is open.
    /// @param Expired The execution window has closed; the action holds its keys until cancelled.
    enum Status {
        Delayed,
        Executable,
        Expired
    }

    // ========== QUEUE ========== //

    /// @notice Returns the ids of the actions that are neither executed nor cancelled, ascending.
    function unresolvedActionIds(
        IConfigTimelockBatchQueue timelock_
    ) internal view returns (uint64[] memory ids) {
        uint64 nextActionId = timelock_.nextActionId();
        uint64[] memory buffer = new uint64[](nextActionId);
        uint256 count = 0;
        for (uint64 actionId = 1; actionId < nextActionId; ++actionId) {
            ITimelockBatchQueue.QueuedAction memory action = timelock_.getQueuedAction(actionId);
            if (action.executed || action.cancelled) continue;
            buffer[count++] = actionId;
        }
        ids = new uint64[](count);
        for (uint256 i = 0; i < count; ++i) {
            ids[i] = buffer[i];
        }
    }

    /// @notice Returns the status of an unresolved action at a timestamp.
    function status(
        ITimelockBatchQueue.QueuedAction memory action_,
        uint256 timestamp_
    ) internal pure returns (Status actionStatus) {
        if (timestamp_ < action_.executableAt) return Status.Delayed;
        if (timestamp_ > action_.expiresAt) return Status.Expired;
        return Status.Executable;
    }

    // ========== LOGGING ========== //

    /// @notice Logs an unresolved action: its id, proposer, window and status, then one line per
    ///         sub-action with the config function and the route it addresses.
    function logAction(
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction memory action_,
        uint256 timestamp_
    ) internal pure {
        console2.log("  Action", actionId_, describeStatus(status(action_, timestamp_)));
        console2.log("    proposer:", action_.proposer);
        console2.log("    executable at:", action_.executableAt, "expires at:", action_.expiresAt);
        for (uint256 i = 0; i < action_.actions.length; ++i) {
            console2.log("    sub-action", i, describe(action_.actions[i]));
        }
    }

    /// @notice Formats a status for the logs.
    // Formats the status on its own, so that a caller can print it next to its own text rather
    // than the whole action record
    // forge-lint: disable-next-item(internal-function-used-once)
    function describeStatus(Status status_) internal pure returns (string memory text) {
        if (status_ == Status.Delayed) return "(delayed)";
        if (status_ == Status.Expired) return "(expired: cancel it to release its keys)";
        return "(executable)";
    }

    /// @notice Formats a sub-action: the config function and, for a route function, the chain
    ///         selector of its route.
    function describe(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal pure returns (string memory text) {
        (bool found, uint64 chainSelector) = routeChainSelector(sub_);
        if (!found) return selectorName(sub_.selector);
        return
            string.concat(
                selectorName(sub_.selector),
                " on chain selector ",
                _VM.toString(chainSelector)
            );
    }

    /// @notice Returns the name of a supported config function, or the hex selector.
    function selectorName(bytes4 selector_) internal pure returns (string memory name) {
        if (selector_ == ICCIPTokenPoolConfig.addChain.selector) return "addChain";
        if (selector_ == ICCIPTokenPoolConfig.removeChain.selector) return "removeChain";
        if (selector_ == ICCIPTokenPoolConfig.setRemoteToken.selector) return "setRemoteToken";
        if (selector_ == ICCIPTokenPoolConfig.addRemotePool.selector) return "addRemotePool";
        if (selector_ == ICCIPTokenPoolConfig.removeRemotePool.selector) return "removeRemotePool";
        if (selector_ == ICCIPTokenPoolConfig.applyAllowListUpdates.selector)
            return "applyAllowListUpdates";
        if (selector_ == ICCIPTokenPoolConfig.setChainRateLimits.selector)
            return "setChainRateLimits";
        return string.concat("selector ", _VM.toString(abi.encodePacked(selector_)));
    }

    /// @notice Returns the chain selector of a route sub-action. `found` is false for the
    ///         allowlist update, which addresses the whole pool, and for an unsupported selector.
    function routeChainSelector(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal pure returns (bool found, uint64 chainSelector) {
        bytes4 selector = sub_.selector;
        bytes memory payload = sub_.payload;

        // The boolean literals below are the `found` element of the returned tuple, not conditions
        // forge-lint: disable-start(boolean-cst)
        if (selector == ICCIPTokenPoolConfig.addChain.selector) {
            return (true, abi.decode(payload, (ICCIPTokenPoolAdmin.ChainUpdate)).remoteChainSelector);
        }
        if (selector == ICCIPTokenPoolConfig.removeChain.selector) {
            return (true, abi.decode(payload, (uint64)));
        }
        if (
            selector == ICCIPTokenPoolConfig.setRemoteToken.selector ||
            selector == ICCIPTokenPoolConfig.addRemotePool.selector ||
            selector == ICCIPTokenPoolConfig.removeRemotePool.selector
        ) {
            (chainSelector, ) = abi.decode(payload, (uint64, bytes));
            return (true, chainSelector);
        }
        if (selector == ICCIPTokenPoolConfig.setChainRateLimits.selector) {
            (chainSelector, , ) = abi.decode(
                payload,
                (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config)
            );
            return (true, chainSelector);
        }
        return (false, 0);
        // forge-lint: disable-end(boolean-cst)
    }
}

// forge-lint: disable-end(calls-loop)
