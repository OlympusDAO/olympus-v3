// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Delayed backing updates use backing_admin; execute and emergency cancel are separate runs.
contract BackingOracleConfigTimelockBatch is TimelockBatchScript {
    function queueSetBacking(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BackingOracleConfigTimelockBatch: queueSetBacking");
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracleConfigTimelock"),
            abi.encodeCall(
                IBackingOracleConfigTimelock.queueSetBacking,
                (_readBatchArgUint256("queueSetBacking", "backing"))
            )
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.BackingOracleConfigTimelock";
    }
}
