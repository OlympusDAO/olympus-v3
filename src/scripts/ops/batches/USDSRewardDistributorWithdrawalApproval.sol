// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// External
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Grants withdrawal approval to USDSRewardDistributor for sUSDS
/// @dev    This script grants the USDSRewardDistributor policy permission to withdraw
///         sUSDS from the Treasury via TreasuryCustodian to distribute as rewards
contract USDSRewardDistributorWithdrawalApproval is BatchScriptV2 {
    // Initial withdrawal approval
    uint256 internal constant INITIAL_WITHDRAWAL_APPROVAL = 10_000e18; // 10k sUSDS

    /// @notice Grant withdrawal approval to USDSRewardDistributor
    function grantApproval(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address treasuryCustodian = _envAddressNotZero("olympus.policies.TreasuryCustodian");
        address usdsRewardDistributor = _envAddressNotZero(
            "olympus.policies.USDSRewardDistributor"
        );
        address sUsds = _envAddressNotZero("external.tokens.sUSDS");

        console2.log("=== Granting USDS Reward Distributor Withdrawal Approval ===");
        console2.log("TreasuryCustodian:", treasuryCustodian);
        console2.log("USDSRewardDistributor:", usdsRewardDistributor);
        console2.log("sUSDS:", sUsds);
        console2.log("Approval Amount:", INITIAL_WITHDRAWAL_APPROVAL);

        // Grant withdrawer approval via TreasuryCustodian
        console2.log("1. Granting withdrawal approval for sUSDS");
        addToBatch(
            treasuryCustodian,
            abi.encodeWithSignature(
                "grantWithdrawerApproval(address,address,uint256)",
                usdsRewardDistributor,
                sUsds,
                INITIAL_WITHDRAWAL_APPROVAL
            )
        );

        // Propose/execute the batch
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
