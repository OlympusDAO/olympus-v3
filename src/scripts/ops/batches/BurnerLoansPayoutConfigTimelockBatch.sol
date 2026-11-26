// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Payout timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansPayoutConfigTimelockBatch is TimelockBatchScript {
    using SafeCast for uint256;

    /// @notice Queue SetSendFeesToDistributor using the required args file.
    function queueSetSendFeesToDistributor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansPayoutConfigTimelockBatch: queueSetSendFeesToDistributor");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueSetSendFeesToDistributor,
                (_readBatchArgBool("queueSetSendFeesToDistributor", "enabled"))
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetSendYieldToDistributor using the required args file.
    function queueSetSendYieldToDistributor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansPayoutConfigTimelockBatch: queueSetSendYieldToDistributor");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueSetSendYieldToDistributor,
                (_readBatchArgBool("queueSetSendYieldToDistributor", "enabled"))
            )
        );
        proposeBatch();
    }

    /// @notice Queue Rescue using the required args file.
    function queueRescue(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansPayoutConfigTimelockBatch: queueRescue");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueRescue,
                (
                    _readBatchArgAddress("queueRescue", "token"),
                    _readBatchArgAddress("queueRescue", "destination")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue RescuePendingPayout using the required args file.
    function queueRescuePendingPayout(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansPayoutConfigTimelockBatch: queueRescuePendingPayout");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueRescuePendingPayout,
                (
                    _readBatchArgAddress("queueRescuePendingPayout", "token"),
                    _readBatchArgAddress("queueRescuePendingPayout", "recipient"),
                    _readBatchArgAddress("queueRescuePendingPayout", "destination"),
                    _readBatchArgUint256("queueRescuePendingPayout", "amount")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue Batch using the required args file.
    function queueBatch(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansPayoutConfigTimelockBatch: queueBatch");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueBatch,
                (
                    abi.decode(
                        vm.parseBytes(_readBatchArgString("queueBatch", "encodedActions")),
                        (ITimelockBatchQueue.BatchAction[])
                    )
                )
            )
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.BurnerLoansPayoutConfigTimelock";
    }
}
