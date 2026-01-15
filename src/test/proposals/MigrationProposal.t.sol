// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {Burner} from "src/policies/Burner.sol";
import {LegacyMigrator} from "src/policies/LegacyMigrator.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";
import {OwnedERC20} from "src/external/OwnedERC20.sol";

// MigrationProposal imports
import {MigrationProposal} from "src/proposals/MigrationProposal.sol";
import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";

contract MigrationProposalTest is ProposalTest {
    /// @dev Block the migration should be executed at
    uint256 public constant BLOCK = 24070000;
    uint256 public constant BLOCKS_NEEDED_FOR_QUEUE = 6000;

    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;

    IOlympusTreasury public treasury;
    OwnedERC20 public tempOHM;
    IERC20 public OHMv1;
    IgOHM public gOHM;
    IERC20 public OHMv2;
    Burner public burner;
    MigrationProposalHelper public migrationProposalHelper;
    LegacyMigrator public legacyMigrator;

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // Existing contracts
        OHMv1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);
        gOHM = IgOHM(GOHM);
        treasury = IOlympusTreasury(0x31F8Cc382c9898b273eff4e0b7626a6987C846E8);

        Kernel kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

        // Create tempOHM token
        tempOHM = new OwnedERC20("TempOHM", "tempOHM", DAO_MS);
        vm.label(address(tempOHM), "tempOHM");

        // Deploy burner and install it into the kernel
        // Note: In production, the burner would already be deployed and activated
        OHMv2 = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        burner = new Burner(kernel, SolmateERC20(address(OHMv2)));

        // Install burner into the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(burner));

        // ========== DEPLOY MIGRATION HELPER ==========

        // Deploy MigrationProposalHelper (deployed separately, not by the proposal)
        // This needs to be deployed before treasury setup so it can be granted permissions
        address timelock = TIMELOCK;

        // Deploy MigrationProposalHelper
        migrationProposalHelper = new MigrationProposalHelper(
            timelock, // owner
            address(burner),
            address(tempOHM)
        );

        // ========== DEPLOY LEGACY MIGRATOR ==========

        // Deploy LegacyMigrator (pre-deployed, enabled via proposal)
        legacyMigrator = new LegacyMigrator(
            kernel,
            IERC20(address(OHMv1)),
            gOHM,
            bytes32(0) // merkleRoot (set to zero, not used in proposal test)
        );

        // Install LegacyMigrator into the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(legacyMigrator));

        // ========== NOTE: TREASURY SETUP ==========
        // Treasury permissions for tempOHM and MigrationProposalHelper should be set up
        // separately via the MigrationProposalSetup script before this proposal is executed.
        // This includes:
        // - Setting tempOHM as a reserve token
        // - Granting MigrationProposalHelper permission to withdraw tempOHM
        // - Minting tempOHM to the Timelock for the gOHM burn
        //
        // For this test, we assume those steps have been completed via MigrationProposalSetup.
        // In a real scenario, run:
        //   forge script MigrationProposalSetup --sig "queue(...)" --broadcast
        //   (wait for timelock)
        //   forge script MigrationProposalSetup --sig "toggle(...)" --broadcast

        // ========== PROPOSAL SIMULATION ==========

        // Deploy proposal under test (no constructor parameters needed)
        MigrationProposal proposal = new MigrationProposal();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Create TestSuite
        _setupSuite(address(proposal));

        // Update addresses with test-deployed contracts (needed for _build and _validate)
        addresses.addAddress("olympus-policy-burner", address(burner));
        addresses.addAddress("olympus-policy-legacy-migrator", address(legacyMigrator));
        addresses.addAddress("olympus-policy-migration-helper", address(migrationProposalHelper));
        addresses.addAddress("external.tokens.tempOHM", address(tempOHM));

        // Set debug mode
        suite.setDebug(true);

        // Simulate the proposal
        _simulateProposal();

        // ========== VERIFY MIGRATION HELPER ACTIVATION ==========

        _verifyMigrationProposalHelperActivation();
    }

    /// @notice Helper function to verify MigrationProposalHelper activation
    function _verifyMigrationProposalHelperActivation() internal view {
        // Verify that MigrationProposalHelper is marked as activated
        assertTrue(migrationProposalHelper.isActivated(), "MigrationProposalHelper should be activated");

        // Verify that the "migration" category was added to the burner
        bytes32 migrationCategory = migrationProposalHelper.MIGRATION_CATEGORY();
        assertTrue(
            burner.categoryApproved(migrationCategory),
            "Migration category should be approved in Burner"
        );

        console2.log("");
        console2.log("====== Migration Helper Activation Verified ======");
        console2.log("MigrationProposalHelper activated:", migrationProposalHelper.isActivated());
        console2.log("Migration category approved:", burner.categoryApproved(migrationCategory));
    }
}
