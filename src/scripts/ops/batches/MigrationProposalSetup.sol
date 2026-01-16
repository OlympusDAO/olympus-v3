// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {OwnedERC20} from "src/external/OwnedERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";
import {IOlympusTokenMigrator} from "src/interfaces/IOlympusTokenMigrator.sol";

/// @notice Setup script for migration treasury permissions
/// @dev    Provides queue() and toggle() functions for managing tempOHM and MigrationProposalHelper permissions
contract MigrationProposalSetup is BatchScriptV2 {
    IERC20 public constant OHMV1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);

    // TODO validation checks need to be performed post-simulation

    /// @notice Queue treasury permissions for tempOHM and MigrationProposalHelper
    /// @dev    Grants MigrationProposalHelper permission to deposit tempOHM into treasury
    ///         This must be executed first, then after timelock period, permissions are effective
    function queueEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");

        console2.log("=== Setting up Legacy Treasury ===");
        console2.log("Legacy Treasury:", legacyTreasury);
        console2.log("MigrationProposalHelper:", migrationProposalHelper);
        console2.log("tempOHM:", tempOHM);

        // Confirm that tempOHM is not a reserve token in the legacy treasury
        if (IOlympusTreasury(legacyTreasury).isReserveToken(tempOHM)) {
            revert("tempOHM should not be a reserve token in the legacy treasury");
        }

        // Add tempOHM as a reserve token to the legacy treasury
        console2.log("Adding tempOHM as a reserve token to the legacy treasury");
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.queue.selector,
                IOlympusTreasury.MANAGING.RESERVETOKEN,
                tempOHM
            )
        );

        // Print the queue result
        uint256 reserveTokenTimelock = IOlympusTreasury(legacyTreasury).reserveTokenQueue(tempOHM);
        if (reserveTokenTimelock == 0) {
            revert("reserveToken queue timestamp should not be 0");
        }
        console2.log("reserveToken queue timestamp:", reserveTokenTimelock);

        // Confirm that MigrationProposalHelper is not a reserve depositor in the legacy treasury
        if (IOlympusTreasury(legacyTreasury).isReserveDepositor(migrationProposalHelper)) {
            revert(
                "MigrationProposalHelper should not be a reserve depositor in the legacy treasury"
            );
        }

        // Add MigrationProposalHelper as a reserve depositor to the legacy treasury
        console2.log(
            "Adding MigrationProposalHelper as a reserve depositor to the legacy treasury"
        );
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.queue.selector,
                IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
                migrationProposalHelper
            )
        );

        // Print the queue result
        uint256 reserveDepositorTimelock = IOlympusTreasury(legacyTreasury).reserveDepositorQueue(
            migrationProposalHelper
        );
        if (reserveDepositorTimelock == 0) {
            revert("reserveDepositor queue timestamp should not be 0");
        }
        console2.log("reserveDepositor queue timestamp:", reserveDepositorTimelock);

        console2.log("Legacy Treasury permissions queued");
        proposeBatch();
    }

    /// @notice Toggle treasury permissions for tempOHM and MigrationProposalHelper
    /// @dev    Enables MigrationProposalHelper permission to deposit tempOHM into treasury
    ///         This must be executed after timelock period, permissions are effective
    function toggleEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");

        console2.log("=== Toggling Legacy Treasury Permissions ===");
        console2.log("Legacy Treasury:", legacyTreasury);
        console2.log("MigrationProposalHelper:", migrationProposalHelper);
        console2.log("tempOHM:", tempOHM);

        // Toggle tempOHM as a reserve token in the legacy treasury
        console2.log("Toggling tempOHM as a reserve token in the legacy treasury");
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.toggle.selector,
                IOlympusTreasury.MANAGING.RESERVETOKEN,
                tempOHM,
                address(0)
            )
        );

        // Verify that tempOHM is now a reserve token in the legacy treasury
        if (!IOlympusTreasury(legacyTreasury).isReserveToken(tempOHM)) {
            revert("tempOHM should be a reserve token in the legacy treasury");
        }

        // Toggle MigrationProposalHelper as a reserve depositor in the legacy treasury
        console2.log(
            "Toggling MigrationProposalHelper as a reserve depositor in the legacy treasury"
        );
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.toggle.selector,
                IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
                migrationProposalHelper,
                address(0)
            )
        );

        // Verify that MigrationProposalHelper is now a reserve depositor in the legacy treasury
        if (!IOlympusTreasury(legacyTreasury).isReserveDepositor(migrationProposalHelper)) {
            revert("MigrationProposalHelper should be a reserve depositor in the legacy treasury");
        }

        console2.log("Legacy Treasury permissions toggled");
        proposeBatch();
    }

    /// @notice Remove tempOHM and MigrationProposalHelper as a reserve token and depositor from the legacy treasury
    /// @dev    To be run after the OCG proposal has been executed
    function disable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );

        console2.log("=== Queueing Removal of tempOHM and MigrationProposalHelper ===");
        console2.log("Legacy Treasury:", legacyTreasury);
        console2.log("tempOHM:", tempOHM);
        console2.log("MigrationProposalHelper:", migrationProposalHelper);

        // Remove tempOHM as a reserve token from the legacy treasury
        console2.log("Removing tempOHM as a reserve token from the legacy treasury");
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.toggle.selector,
                IOlympusTreasury.MANAGING.RESERVETOKEN,
                tempOHM
            )
        );

        // Remove MigrationProposalHelper as a reserve depositor from the legacy treasury
        console2.log(
            "Removing MigrationProposalHelper as a reserve depositor from the legacy treasury"
        );
        addToBatch(
            legacyTreasury,
            abi.encodeWithSelector(
                IOlympusTreasury.toggle.selector,
                IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
                migrationProposalHelper,
                address(0)
            )
        );

        console2.log("Legacy Treasury permissions removed");
        proposeBatch();
    }

    function mintTempOHM(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address tempOHM = _envAddressNotZero("external.tokens.tempOHM");
        address timelock = _envAddressNotZero("olympus.timelock");
        address migrator = _envAddressNotZero("olympus.legacy.TokenMigrator");

        console2.log("=== Minting tempOHM ===");
        console2.log("Legacy Treasury:", legacyTreasury);
        console2.log("tempOHM:", tempOHM);
        console2.log("Timelock:", timelock);

        // Excess reserves is 65659757174924
        console2.log(
            "Treasury excess reserves (18 dp):",
            IOlympusTreasury(legacyTreasury).excessReserves()
        );

        // OHM valuation of tempOHM is 1:1 in OHM decimals
        if (IOlympusTreasury(legacyTreasury).valueOf(address(tempOHM), 1e18) != 1e9) {
            revert("OHM valuation of tempOHM should be 1:1 in OHM decimals");
        }

        // OHMV1 old supply is 553483798713734 (9 dp)
        // OHMV1 total supply is 278651810168261 (9 dp)
        // The difference is what can be minted and migrated
        // Difference is 274831988545473 (274831.988545473 OHM)
        console2.log("OHMV1 oldSupply (9 dp):", IOlympusTokenMigrator(migrator).oldSupply());
        console2.log("OHMV1 total supply (9 dp):", OHMV1.totalSupply());
        uint256 maxMintableOHM = IOlympusTokenMigrator(migrator).oldSupply() - OHMV1.totalSupply();
        console2.log("maxMintableOHM (9 dp):", maxMintableOHM);

        // 1e9 OHM = 21403507467877949 gOHM (18 dp)
        // 274831988545473 OHM can be converted into how much gOHM?
        // 274831988545473 * 21403507467877949 / 1e18 = 5882368519244778449578 gOHM (18 dp)

        // Migrator gOHM balance is 4232050112844353034347 (18 dp)
        // maxMigrateableOHM * conversionRate = 4232050112844353034347
        // maxMigrateableOHM = 4232050112844353034347 / conversionRate = 4232050112844353034347 * 1e9 / 21403507467877949 = 197726943548656 OHM (9 dp) (197,726.9435486566)
        // In reality, the maxOHM is higher
        uint256 maxOHM = 197726943548656;
        // There seems to be some issue with calculations, as the maxOHM results in residual gOHM
        // 176481131518703773 * 1e9 / 21403507467877949
        // = 8245430417
        maxOHM += 8245430417;
        uint256 maxTempOHM = maxOHM * 1e9;

        // Mint tempOHM to the Timelock (MigrationProposalHelper owner)
        OwnedERC20(tempOHM).mint(timelock, maxTempOHM);
        console2.log("maxTempOHM (18 dp):", maxTempOHM);

        console2.log("tempOHM minted to Timelock");
        proposeBatch();
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
