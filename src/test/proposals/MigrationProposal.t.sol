// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
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

    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;

    IOlympusTreasury public legacyTreasury;
    OwnedERC20 public tempOHM;
    IERC20 public OHMv1;
    IgOHM public gOHM;
    IERC20 public OHMv2;
    Burner public burner;
    MigrationProposalHelper public migrationProposalHelper;
    LegacyMigrator public legacyMigrator;

    bool public constant IS_TEMP_OHM_DEPLOYED = false;
    bool public constant IS_BURNER_SETUP = false;
    bool public constant IS_MIGRATION_PROPOSAL_HELPER_DEPLOYED = false;
    bool public constant IS_LEGACY_MIGRATOR_SETUP = false;
    bool public constant IS_LEGACY_TREASURY_SETUP = false;
    bool public constant IS_TEMP_OHM_MINTED = false;

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // ========== PROPOSAL SETUP ==========

        // Deploy proposal under test (no constructor parameters needed)
        MigrationProposal proposal = new MigrationProposal();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Create TestSuite
        _setupSuite(address(proposal));

        // ========== Other scaffolding ==========

        // Existing contracts
        OHMv1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);
        OHMv2 = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        gOHM = IgOHM(GOHM);
        legacyTreasury = IOlympusTreasury(0x31F8Cc382c9898b273eff4e0b7626a6987C846E8);
        vm.label(address(legacyTreasury), "legacyTreasury");

        Kernel kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

        // TempOHM setup
        if (IS_TEMP_OHM_DEPLOYED == true) {
            address tempOHMAddress = addresses.getAddress("external-tokens-tempohm");
            if (tempOHMAddress == address(0)) {
                revert("tempOHM address is not set");
            }
            tempOHM = OwnedERC20(tempOHMAddress);
            vm.label(address(tempOHM), "tempOHM");

            console2.log("tempOHM already deployed");
        } else {
            tempOHM = new OwnedERC20("TempOHM", "tempOHM", DAO_MS);
            vm.label(address(tempOHM), "tempOHM");
            addresses.addAddress("external-tokens-tempohm", address(tempOHM));

            console2.log("tempOHM deployed");
        }

        // Burner setup
        if (IS_BURNER_SETUP == true) {
            address burnerAddress = addresses.getAddress("olympus-policy-burner");
            if (burnerAddress == address(0)) {
                revert("burner address is not set");
            }
            burner = Burner(burnerAddress);
            vm.label(address(burner), "burner");

            console2.log("burner policy already deployed");
        } else {
            // Deploy burner
            burner = new Burner(kernel, SolmateERC20(address(OHMv2)));
            vm.label(address(burner), "burner");
            addresses.addAddress("olympus-policy-burner", address(burner));

            // Install burner into the kernel
            vm.prank(DAO_MS);
            kernel.executeAction(Actions.ActivatePolicy, address(burner));

            console2.log("burner policy deployed and setup");
        }

        // MigrationProposalHelper setup
        if (IS_MIGRATION_PROPOSAL_HELPER_DEPLOYED == true) {
            address migrationProposalHelperAddress = addresses.getAddress(
                "olympus-periphery-migration-proposal-helper"
            );
            if (migrationProposalHelperAddress == address(0)) {
                revert("migrationProposalHelper address is not set");
            }
            migrationProposalHelper = MigrationProposalHelper(migrationProposalHelperAddress);
            vm.label(address(migrationProposalHelper), "migrationProposalHelper");

            console2.log("migrationProposalHelper already deployed");
        } else {
            // Initial OHM v1 limit (1e9 decimals) - calculated off-chain
            uint256 maxOHMv1ToMigrate = 197735188979073; // ~197.7k OHM v1

            // Deploy MigrationProposalHelper
            migrationProposalHelper = new MigrationProposalHelper(
                TIMELOCK, // owner
                DAO_MS, // admin
                address(burner),
                address(tempOHM),
                maxOHMv1ToMigrate
            );
            vm.label(address(migrationProposalHelper), "migrationProposalHelper");
            addresses.addAddress(
                "olympus-periphery-migration-proposal-helper",
                address(migrationProposalHelper)
            );

            console2.log("migrationProposalHelper deployed and setup");
        }

        // LegacyMigrator setup
        if (IS_LEGACY_MIGRATOR_SETUP == true) {
            address legacyMigratorAddress = addresses.getAddress("olympus-policy-legacy-migrator");
            if (legacyMigratorAddress == address(0)) {
                revert("legacyMigrator address is not set");
            }
            legacyMigrator = LegacyMigrator(legacyMigratorAddress);
            vm.label(address(legacyMigrator), "legacyMigrator");

            console2.log("legacyMigrator already deployed");
        } else {
            // Deploy LegacyMigrator
            legacyMigrator = new LegacyMigrator(
                kernel,
                IERC20(address(OHMv1)),
                gOHM,
                bytes32(0) // merkleRoot (set to zero, not used in proposal test)
            );
            vm.label(address(legacyMigrator), "legacyMigrator");
            addresses.addAddress("olympus-policy-legacy-migrator", address(legacyMigrator));

            // Install LegacyMigrator into the kernel
            vm.prank(DAO_MS);
            kernel.executeAction(Actions.ActivatePolicy, address(legacyMigrator));

            console2.log("legacyMigrator deployed and setup");
        }

        // LegacyTreasury setup
        if (IS_LEGACY_TREASURY_SETUP == true) {
            // Do nothing

            console2.log("legacyTreasury already setup");
        } else {
            // Queue tempOHM as a reserve token in the legacy treasury
            vm.prank(DAO_MS);
            legacyTreasury.queue(IOlympusTreasury.MANAGING.RESERVETOKEN, address(tempOHM));

            // Queue MigrationProposalHelper as a reserve depositor in the legacy treasury
            vm.prank(DAO_MS);
            legacyTreasury.queue(
                IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
                address(migrationProposalHelper)
            );

            // Get the actual queue expiry block numbers
            uint256 reserveTokenQueueBlock = legacyTreasury.reserveTokenQueue(address(tempOHM));
            uint256 reserveDepositorQueueBlock = legacyTreasury.reserveDepositorQueue(
                address(migrationProposalHelper)
            );

            // Warp to the later of the two queue expiry block numbers
            uint256 queueExpiryBlock = reserveTokenQueueBlock > reserveDepositorQueueBlock
                ? reserveTokenQueueBlock
                : reserveDepositorQueueBlock;
            vm.roll(queueExpiryBlock);

            // Toggle tempOHM as a reserve token in the legacy treasury
            vm.prank(DAO_MS);
            legacyTreasury.toggle(
                IOlympusTreasury.MANAGING.RESERVETOKEN,
                address(tempOHM),
                address(0)
            );

            // Toggle MigrationProposalHelper as a reserve depositor in the legacy treasury
            vm.prank(DAO_MS);
            legacyTreasury.toggle(
                IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
                address(migrationProposalHelper),
                address(0)
            );

            console2.log("legacyTreasury setup");
        }

        // Mint tempOHM to the Timelock (MigrationProposalHelper owner)
        if (IS_TEMP_OHM_MINTED == true) {
            // Do nothing
            console2.log("tempOHM already minted");
        } else {
            // Mint enough tempOHM for the migration (maxOHMv1ToMigrate * 1e9)
            uint256 maxOHMv1ToMigrate = 197735188979073; // ~197.7k OHM v1 (1e9 decimals)
            uint256 tempOHMToMint = maxOHMv1ToMigrate * 1e9; // Convert to 1e18 decimals
            vm.prank(DAO_MS);
            tempOHM.mint(TIMELOCK, tempOHMToMint);
            console2.log("tempOHM minted to Timelock");
        }

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
        assertTrue(
            migrationProposalHelper.isActivated(),
            "MigrationProposalHelper should be activated"
        );

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
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
