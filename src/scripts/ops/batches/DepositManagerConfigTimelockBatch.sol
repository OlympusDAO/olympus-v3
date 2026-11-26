// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Delayed shared-custody configuration; generic batching admits only the queue's allowlist.
contract DepositManagerConfigTimelockBatch is TimelockBatchScript {
    /// @notice Queue a cap change in underlying-token base units.
    function queueSetAssetDepositCap(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero(_timelockKey()),
            abi.encodeCall(
                IDepositManagerConfigTimelock.queueSetAssetDepositCap,
                (
                    IERC20(_readBatchArgAddress("queueSetAssetDepositCap", "asset")),
                    _readBatchArgUint256("queueSetAssetDepositCap", "cap")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue reviewed selector/payload pairs for the manager's admitted settings.
    function queueBatch(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        ITimelockBatchQueue.BatchAction[] memory actions = abi.decode(
            vm.parseBytes(_readBatchArgString("queueBatch", "encodedActions")),
            (ITimelockBatchQueue.BatchAction[])
        );
        addToBatch(
            _envAddressNotZero(_timelockKey()),
            abi.encodeCall(IDepositManagerConfigTimelock.queueBatch, (actions))
        );
        proposeBatch();
    }

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.DepositManagerConfigTimelock";
    }
}
