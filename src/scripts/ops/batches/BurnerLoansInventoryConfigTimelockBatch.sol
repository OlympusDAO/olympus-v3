// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Inventory timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansInventoryConfigTimelockBatch is TimelockBatchScript {
    /// @notice Queue BurnSurplus using the required args file.
    function queueBurnSurplus(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansInventoryConfigTimelockBatch: queueBurnSurplus");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
            abi.encodeCall(IBurnerLoansInventoryConfigTimelock.queueBurnSurplus, ())
        );
        proposeBatch();
    }

    /// @notice Queue RescueSurplus using the required args file.
    function queueRescueSurplus(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansInventoryConfigTimelockBatch: queueRescueSurplus");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
            abi.encodeCall(IBurnerLoansInventoryConfigTimelock.queueRescueSurplus, ())
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.BurnerLoansInventoryConfigTimelock";
    }
}
