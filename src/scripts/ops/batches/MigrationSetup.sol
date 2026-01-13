// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Setup script for migration treasury permissions
/// @dev    Provides queue() and toggle() functions for managing tempOHM and MigrationHelper permissions
contract MigrationSetup is BatchScriptV2 {
    /// @notice Queue treasury permissions for tempOHM and MigrationHelper
    /// @dev    Grants MigrationHelper permission to withdraw tempOHM from treasury
    ///         This must be executed first, then after timelock period, permissions are effective
    function queue(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address treasury = _envAddressNotZero("olympus.modules.Treasury");
        address migrationHelper = _envAddressNotZero("olympus.policies.MigrationHelper");
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");

        console2.log("=== Queueing Treasury Permissions ===");
        console2.log("Treasury:", treasury);
        console2.log("MigrationHelper:", migrationHelper);
        console2.log("tempOHM:", tempOHM);

        // Grant MigrationHelper permission to withdraw tempOHM from treasury
        console2.log("Granting MigrationHelper permission to withdraw tempOHM");
        addToBatch(
            treasury,
            abi.encodeWithSelector(
                TRSRYv1.increaseWithdrawApproval.selector,
                migrationHelper,
                ERC20(tempOHM),
                type(uint256).max // Infinite approval
            )
        );

        console2.log("Treasury permissions queued");
        proposeBatch();
    }

    /// @notice Toggle (revoke) treasury permissions for tempOHM and MigrationHelper
    /// @dev    Revokes MigrationHelper permission to withdraw tempOHM from treasury
    ///         Use this after migration is complete to clean up permissions
    function toggle(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address treasury = _envAddressNotZero("olympus.modules.Treasury");
        address migrationHelper = _envAddressNotZero("olympus.policies.MigrationHelper");
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");

        console2.log("=== Toggling (Revoking) Treasury Permissions ===");
        console2.log("Treasury:", treasury);
        console2.log("MigrationHelper:", migrationHelper);
        console2.log("tempOHM:", tempOHM);

        // Revoke MigrationHelper permission to withdraw tempOHM from treasury
        console2.log("Revoking MigrationHelper permission to withdraw tempOHM");
        addToBatch(
            treasury,
            abi.encodeWithSelector(
                TRSRYv1.decreaseWithdrawApproval.selector,
                migrationHelper,
                ERC20(tempOHM),
                type(uint256).max // Revoke all approval
            )
        );

        console2.log("Treasury permissions toggled");
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
