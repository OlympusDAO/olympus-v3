// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Shared revenue infrastructure operations; target authorization is checked in simulation.
contract RevenueDistributorBatch is BatchScriptV2 {
    /// @notice Distribute an asset using its current routes.
    function distribute(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributor"),
            abi.encodeCall(
                IRevenueDistributor.distribute,
                (_readBatchArgAddress("distribute", "asset"))
            )
        );
        proposeBatch();
    }

    /// @notice Retry the exact outstanding recipient entitlement.
    function transferPendingPayout(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributor"),
            abi.encodeCall(
                IRevenueDistributor.transferPendingPayout,
                (
                    _readBatchArgAddress("transferPendingPayout", "asset"),
                    _readBatchArgAddress("transferPendingPayout", "recipient")
                )
            )
        );
        proposeBatch();
    }
}
