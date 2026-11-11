// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice SeizerTask operational controls delegated to burner_loans_admin.
contract BurnerLoansSeizerTaskBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice setScanLimits; downstream validation and pause semantics remain authoritative.
    function setScanLimits(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setScanLimits,
                (
                    _readBatchArgUint256("setScanLimits", "maxBorrowersToCheck").toUint16(),
                    _readBatchArgUint256("setScanLimits", "maxBorrowersToSeize").toUint8()
                )
            )
        );
        proposeBatch();
    }

    /// @notice setExecutionGasLimit; downstream validation and pause semantics remain authoritative.
    function setExecutionGasLimit(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setExecutionGasLimit,
                (_readBatchArgUint256("setExecutionGasLimit", "executionGasLimit").toUint32())
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
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setNextAssetIndex,
                (_readBatchArgUint256("setNextAssetIndex", "index"))
            )
        );
        proposeBatch();
    }

    /// @notice setNextAssetBorrowerIndex; downstream validation and pause semantics remain authoritative.
    function setNextAssetBorrowerIndex(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setNextAssetBorrowerIndex,
                (
                    _readBatchArgAddress("setNextAssetBorrowerIndex", "asset"),
                    _readBatchArgUint256("setNextAssetBorrowerIndex", "index")
                )
            )
        );
        proposeBatch();
    }
}
