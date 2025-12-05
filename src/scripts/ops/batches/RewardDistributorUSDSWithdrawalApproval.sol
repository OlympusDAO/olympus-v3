// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// External
import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Grants withdrawal approval to RewardDistributorUSDS for sUSDS
/// @dev    This script grants the RewardDistributorUSDS policy permission to withdraw
///         sUSDS from the Treasury via TreasuryCustodian to distribute as rewards
contract RewardDistributorUSDSWithdrawalApproval is BatchScriptV2 {
    /// @notice Grant withdrawal approval to RewardDistributorUSDS
    /// @dev    Requires args file with:
    ///         - treasuryCustodian: address of TreasuryCustodian policy
    ///         - rewardDistributor: address of RewardDistributorUSDS policy
    ///         - sUsds: address of sUSDS token
    ///         - approvalAmount: uint256 approval amount in wei
    function grantApproval(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        // Read values from args file
        address treasuryCustodian = _readBatchArgAddress("grantApproval", "treasuryCustodian");
        address rewardDistributor = _readBatchArgAddress("grantApproval", "rewardDistributor");
        address sUsds = _readBatchArgAddress("grantApproval", "sUsds");
        uint256 approvalAmount = _readBatchArgUint256("grantApproval", "approvalAmount");

        console2.log("=== Granting USDS Reward Distributor Withdrawal Approval ===");
        console2.log("TreasuryCustodian:", treasuryCustodian);
        console2.log("RewardDistributorUSDS:", rewardDistributor);
        console2.log("sUSDS:", sUsds);
        console2.log("Approval Amount:", approvalAmount);

        // Grant withdrawer approval via TreasuryCustodian
        console2.log("1. Granting withdrawal approval for sUSDS");
        addToBatch(
            treasuryCustodian,
            abi.encodeWithSignature(
                "grantWithdrawerApproval(address,address,uint256)",
                rewardDistributor,
                sUsds,
                approvalAmount
            )
        );

        // Propose/execute the batch
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
