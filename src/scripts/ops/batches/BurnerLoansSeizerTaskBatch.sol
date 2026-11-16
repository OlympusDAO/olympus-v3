// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
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
        console2.log("BurnerLoansSeizerTaskBatch: setScanLimits");
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
        console2.log("BurnerLoansSeizerTaskBatch: setExecutionGasLimit");
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
        console2.log("BurnerLoansSeizerTaskBatch: setNextAssetIndex");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setNextAssetIndex,
                (_readBatchArgUint256("setNextAssetIndex", "index"))
            )
        );
        proposeBatch();
    }

    /// @notice setExpiredAssetCursor; downstream validation and pause semantics remain authoritative.
    function setExpiredAssetCursor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansSeizerTaskBatch: setExpiredAssetCursor");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setExpiredAssetCursor,
                (
                    _readBatchArgAddress("setExpiredAssetCursor", "asset"),
                    _readBatchArgUint256("setExpiredAssetCursor", "index")
                )
            )
        );
        proposeBatch();
    }

    /// @notice setUnhealthyAssetCursor; downstream validation and pause semantics remain authoritative.
    function setUnhealthyAssetCursor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansSeizerTaskBatch: setUnhealthyAssetCursor");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansSeizerTask"),
            abi.encodeCall(
                IBurnerLoansSeizerTask.setUnhealthyAssetCursor,
                (
                    _readBatchArgAddress("setUnhealthyAssetCursor", "asset"),
                    _readBatchArgUint256("setUnhealthyAssetCursor", "index")
                )
            )
        );
        proposeBatch();
    }
}
