// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice YieldClaimerTask operational controls delegated to burner_loans_admin.
contract BurnerLoansYieldClaimerTaskBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice setExecutionGasLimit; downstream validation and pause semantics remain authoritative.
    function setExecutionGasLimit(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansYieldClaimerTask"),
            abi.encodeCall(
                IBurnerLoansYieldClaimerTask.setExecutionGasLimit,
                (_readBatchArgUint256("setExecutionGasLimit", "executionGasLimit").toUint32())
            )
        );
        proposeBatch();
    }

    /// @notice setMinimumGasToAttempt; downstream validation and pause semantics remain authoritative.
    function setMinimumGasToAttempt(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansYieldClaimerTask"),
            abi.encodeCall(
                IBurnerLoansYieldClaimerTask.setMinimumGasToAttempt,
                (_readBatchArgUint256("setMinimumGasToAttempt", "minimumGasToAttempt").toUint32())
            )
        );
        proposeBatch();
    }

    /// @notice setGasReserve; downstream validation and pause semantics remain authoritative.
    function setGasReserve(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansYieldClaimerTask"),
            abi.encodeCall(
                IBurnerLoansYieldClaimerTask.setGasReserve,
                (_readBatchArgUint256("setGasReserve", "gasReserve").toUint32())
            )
        );
        proposeBatch();
    }

    /// @notice setNextAssetIndex; downstream validation and pause semantics remain authoritative.
    function setNextAssetIndex(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansYieldClaimerTask"),
            abi.encodeCall(
                IBurnerLoansYieldClaimerTask.setNextAssetIndex,
                (_readBatchArgUint256("setNextAssetIndex", "index"))
            )
        );
        proposeBatch();
    }
}
