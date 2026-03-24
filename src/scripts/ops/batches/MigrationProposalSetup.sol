// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {OwnedERC20} from "src/external/OwnedERC20.sol";

import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";
import {Kernel, Actions, Policy} from "src/Kernel.sol";

/// @notice Setup script for migration treasury permissions
/// @dev    Provides queue() and toggle() functions for managing tempOHM and MigrationProposalHelper permissions
contract MigrationProposalSetup is BatchScriptV2 {
    IERC20 public constant OHMV1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);

    /// @notice Expected tempOHM amount for mint validation
    uint256 internal _expectedTempOHMAmount;

    /// @notice Expected OHMv1ToMigrate amount for setOHMv1ToMigrate validation (1e9 decimals)
    uint256 internal _expectedOHMv1ToMigrateAmount;

    function install(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        // Get addresses from environment
        address kernel = _envAddressNotZero("olympus.Kernel");
        address burner = _envAddressNotZero("olympus.policies.Burner");
        address v1Migrator = _envAddressNotZero("olympus.policies.V1Migrator");

        // Display addresses
        console2.log("Kernel:", kernel);
        console2.log("Burner:", burner);
        console2.log("V1Migrator:", v1Migrator);

        // Install Burner policy
        console2.log("Installing Burner policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, burner)
        );

        // Install V1Migrator policy
        console2.log("Installing V1Migrator policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                v1Migrator
            )
        );

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateInstallPostBatch.selector);

        // Propose batch
        proposeBatch();
        console2.log("Batch completed");
    }

    /// @notice Validate install state after batch execution
    /// @dev    Validates that Burner and V1Migrator have been installed properly
    function _validateInstallPostBatch() external view {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address burner = _envAddressNotZero("olympus.policies.Burner");
        address v1Migrator = _envAddressNotZero("olympus.policies.V1Migrator");

        console2.log("Validating install Post-Batch State");

        // Validate Burner policy is active
        if (!Kernel(kernel).isPolicyActive(Policy(burner))) {
            revert("Burner policy should be active");
        }
        console2.log("Burner policy is active");

        // Validate V1Migrator policy is active
        if (!Kernel(kernel).isPolicyActive(Policy(v1Migrator))) {
            revert("V1Migrator policy should be active");
        }
        console2.log("V1Migrator policy is active");

        console2.log("install post-batch validation passed");
    }

    /// @notice Queue treasury permissions for tempOHM and MigrationProposalHelper
    /// @dev    Grants MigrationProposalHelper permission to deposit tempOHM into treasury
    ///         This must be executed first, then after timelock period, permissions are effective
    function queueEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");

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

        console2.log("Legacy Treasury permissions queued");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateQueueEnablePostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate queueEnable state after batch execution
    /// @dev    Validates that tempOHM and MigrationProposalHelper have been queued properly
    function _validateQueueEnablePostBatch() external view {
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");

        console2.log("\n Validating queueEnable Post-Batch State ");

        // Validate reserveToken queue
        uint256 reserveTokenTimelock = IOlympusTreasury(legacyTreasury).reserveTokenQueue(tempOHM);
        if (reserveTokenTimelock == 0) {
            revert("reserveToken queue block should not be 0");
        }
        console2.log("reserveToken queue block:", reserveTokenTimelock);

        // Validate reserveDepositor queue
        uint256 reserveDepositorTimelock = IOlympusTreasury(legacyTreasury).reserveDepositorQueue(
            migrationProposalHelper
        );
        if (reserveDepositorTimelock == 0) {
            revert("reserveDepositor queue block should not be 0");
        }
        console2.log("reserveDepositor queue block:", reserveDepositorTimelock);

        console2.log("queueEnable post-batch validation passed");
    }

    /// @notice Toggle treasury permissions for tempOHM and MigrationProposalHelper
    /// @dev    Enables MigrationProposalHelper permission to deposit tempOHM into treasury
    ///         This must be executed after timelock period, permissions are effective
    function toggleEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");

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

        console2.log("Legacy Treasury permissions toggled");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateToggleEnablePostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate toggleEnable state after batch execution
    /// @dev    Validates that tempOHM and MigrationProposalHelper have been enabled properly
    function _validateToggleEnablePostBatch() external view {
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");

        console2.log("\n Validating toggleEnable Post-Batch State ");

        // Validate tempOHM is now a reserve token
        if (!IOlympusTreasury(legacyTreasury).isReserveToken(tempOHM)) {
            revert("tempOHM should be a reserve token in the legacy treasury");
        }
        console2.log("tempOHM is a reserve token");

        // Validate MigrationProposalHelper is now a reserve depositor
        if (!IOlympusTreasury(legacyTreasury).isReserveDepositor(migrationProposalHelper)) {
            revert("MigrationProposalHelper should be a reserve depositor in the legacy treasury");
        }
        console2.log("MigrationProposalHelper is a reserve depositor");

        console2.log("toggleEnable post-batch validation passed");
    }

    /// @notice Remove tempOHM and MigrationProposalHelper as a reserve token and depositor from the legacy treasury
    /// @dev    To be run after the OCG proposal has been executed
    function disable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");
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
                tempOHM,
                address(0)
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

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateDisablePostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate disable state after batch execution
    /// @dev    Validates that tempOHM and MigrationProposalHelper have been removed properly
    function _validateDisablePostBatch() external view {
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );

        console2.log("\n Validating disable Post-Batch State ");

        // Validate tempOHM is no longer a reserve token
        if (IOlympusTreasury(legacyTreasury).isReserveToken(tempOHM)) {
            revert("tempOHM should not be a reserve token in the legacy treasury");
        }
        console2.log("tempOHM is not a reserve token");

        // Validate MigrationProposalHelper is no longer a reserve depositor
        if (IOlympusTreasury(legacyTreasury).isReserveDepositor(migrationProposalHelper)) {
            revert(
                "MigrationProposalHelper should not be a reserve depositor in the legacy treasury"
            );
        }
        console2.log("MigrationProposalHelper is not a reserve depositor");

        console2.log("disable post-batch validation passed");
    }

    /// @notice Mint tempOHM to the Timelock (MigrationProposalHelper owner)
    /// @dev    To be run before OCG proposal submission
    ///         Reads OHMv1ToMigrate from MigrationProposalHelper to determine amount
    function mintTempOHM(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);

        // Get addresses from environment
        address legacyTreasury = _envAddressNotZero("olympus.legacy.TreasuryV2");
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");
        address timelock = _envAddressNotZero("olympus.governance.Timelock");
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );

        console2.log("=== Minting tempOHM ===");
        console2.log("Legacy Treasury:", legacyTreasury);
        console2.log("tempOHM:", tempOHM);
        console2.log("Timelock:", timelock);
        console2.log("MigrationProposalHelper:", migrationProposalHelper);

        // Validate tempOHM valuation
        if (IOlympusTreasury(legacyTreasury).valueOf(address(tempOHM), 1e18) != 1e9) {
            revert("OHM valuation of tempOHM should be 1:1 in OHM decimals");
        }

        // Read OHMv1ToMigrate from MigrationProposalHelper (must be pre-set)
        uint256 ohmV1ToMigrate = MigrationProposalHelper(migrationProposalHelper).OHMv1ToMigrate();
        if (ohmV1ToMigrate == 0) {
            revert("OHMv1ToMigrate must be set on MigrationProposalHelper before minting tempOHM");
        }
        console2.log("OHMv1ToMigrate (9 dp):", ohmV1ToMigrate);

        // Calculate tempOHM needed from the helper's getter
        uint256 tempOHMNeeded = MigrationProposalHelper(migrationProposalHelper)
            .getTempOHMToDeposit();
        console2.log("tempOHM needed (18 dp):", tempOHMNeeded);

        // Store expected amount for post-batch validation
        _expectedTempOHMAmount = tempOHMNeeded;

        // Mint tempOHM to the Timelock
        addToBatch(
            tempOHM,
            abi.encodeWithSelector(OwnedERC20.mint.selector, timelock, tempOHMNeeded)
        );

        console2.log("tempOHM minted to Timelock");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateMintTempOHMPostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate mintTempOHM state after batch execution
    /// @dev    Validates that the timelock received the expected tempOHM amount
    function _validateMintTempOHMPostBatch() external view {
        address tempOHM = _envAddressNotZero("external.tokens.TempOHM");
        address timelock = _envAddressNotZero("olympus.governance.Timelock");

        console2.log("\n Validating mintTempOHM Post-Batch State ");

        // Validate timelock has the expected tempOHM balance
        uint256 timelockBalance = IERC20(tempOHM).balanceOf(timelock);
        if (timelockBalance < _expectedTempOHMAmount) {
            revert(
                string.concat(
                    "Timelock tempOHM balance should be at least ",
                    vm.toString(_expectedTempOHMAmount),
                    ", but is ",
                    vm.toString(timelockBalance)
                )
            );
        }
        console2.log("Timelock tempOHM balance:", timelockBalance);
        console2.log("Expected balance:", _expectedTempOHMAmount);

        console2.log("mintTempOHM post-batch validation passed");
    }

    /// @notice Set the OHM v1 to migrate value on MigrationProposalHelper
    /// @dev    Updates the amount of OHM v1 that will be migrated
    ///         Args file format: {"functions": [{"name": "setOHMv1ToMigrate", "args": {"OHMv1ToMigrate": "197735188979073"}}]}
    function setOHMv1ToMigrate(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        // Get addresses from environment
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );

        console2.log("=== Setting OHM v1 to Migrate on MigrationProposalHelper ===");
        console2.log("MigrationProposalHelper:", migrationProposalHelper);

        // Read the new OHMv1ToMigrate value from args file
        uint256 newOHMv1ToMigrate = _readBatchArgUint256("setOHMv1ToMigrate", "OHMv1ToMigrate");

        console2.log("New OHMv1ToMigrate (1e9 decimals):", newOHMv1ToMigrate);

        // Set OHMv1ToMigrate on MigrationProposalHelper
        addToBatch(
            migrationProposalHelper,
            abi.encodeWithSelector(
                MigrationProposalHelper.setOHMv1ToMigrate.selector,
                newOHMv1ToMigrate
            )
        );

        // Store expected amount for post-batch validation
        _expectedOHMv1ToMigrateAmount = newOHMv1ToMigrate;

        console2.log("OHMv1ToMigrate set on MigrationProposalHelper");

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this._validateSetOHMv1ToMigratePostBatch.selector);

        proposeBatch();
    }

    /// @notice Validate setOHMv1ToMigrate state after batch execution
    /// @dev    Validates that OHMv1ToMigrate has been updated correctly
    function _validateSetOHMv1ToMigratePostBatch() external view {
        address migrationProposalHelper = _envAddressNotZero(
            "olympus.periphery.MigrationProposalHelper"
        );

        console2.log("\n Validating setOHMv1ToMigrate Post-Batch State ");

        // Validate OHMv1ToMigrate was set correctly
        uint256 actualOHMv1ToMigrate = MigrationProposalHelper(migrationProposalHelper)
            .OHMv1ToMigrate();
        if (actualOHMv1ToMigrate != _expectedOHMv1ToMigrateAmount) {
            revert(
                string.concat(
                    "OHMv1ToMigrate should be ",
                    vm.toString(_expectedOHMv1ToMigrateAmount),
                    ", but is ",
                    vm.toString(actualOHMv1ToMigrate)
                )
            );
        }
        console2.log("OHMv1ToMigrate:", actualOHMv1ToMigrate);
        console2.log("Expected value:", _expectedOHMv1ToMigrateAmount);

        // Validate getTempOHMToDeposit returns correct value
        uint256 tempOHMToDeposit = MigrationProposalHelper(migrationProposalHelper)
            .getTempOHMToDeposit();
        uint256 expectedTempOHM = _expectedOHMv1ToMigrateAmount * 1e9;
        if (tempOHMToDeposit != expectedTempOHM) {
            revert(
                string.concat(
                    "getTempOHMToDeposit should return ",
                    vm.toString(expectedTempOHM),
                    ", but returns ",
                    vm.toString(tempOHMToDeposit)
                )
            );
        }
        console2.log("getTempOHMToDeposit:", tempOHMToDeposit);

        console2.log("setOHMv1ToMigrate post-batch validation passed");
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
