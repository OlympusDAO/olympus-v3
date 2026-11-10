// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Initial oracle population and queue binding require ADMIN.
contract BackingOracleBatch is BatchScriptV2 {
    /// @notice After Kernel setup, bind the queue and populate backing in 18 decimals using reviewed args.
    function initialize(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address queue = _envAddressNotZero("olympus.policies.BackingOracleConfigTimelock");
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracle"),
            abi.encodeCall(IConfigOperator.setConfigOperator, (queue))
        );
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracle"),
            abi.encodeCall(
                IEnabler.enable,
                (abi.encode(_readBatchArgUint256("initialize", "backing")))
            )
        );
        addToBatch(queue, abi.encodeCall(IEnabler.enable, (bytes(""))));
        proposeBatch();
    }
}
