// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {Burner} from "src/policies/Burner.sol";
import {V1Migrator} from "src/policies/V1Migrator.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";
import {OwnedERC20} from "src/external/OwnedERC20.sol";

// MigrationProposal imports
import {MigrationProposal} from "src/proposals/MigrationProposal.sol";
import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";

using SafeTransferLib for ERC20;

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
    V1Migrator public v1Migrator;
    MigrationProposal public proposal;
    MigrationProposalTestWrapper public proposalWrapper;

    bool public constant IS_TEMP_OHM_DEPLOYED = false;
    bool public constant IS_BURNER_SETUP = false;
    bool public constant IS_MIGRATION_PROPOSAL_HELPER_DEPLOYED = false;
    bool public constant IS_V1_MIGRATOR_SETUP = false;
    bool public constant IS_LEGACY_TREASURY_SETUP = false;
    bool public constant IS_TEMP_OHM_MINTED = false;

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // ========== PROPOSAL SETUP ==========

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Deploy proposal under test (no constructor parameters needed)
        proposal = new MigrationProposal();
        proposalWrapper = new MigrationProposalTestWrapper();

        // Create TestSuite (this initializes addresses)
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
            burner = new Burner(kernel, ERC20(address(OHMv2)));
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

        // V1Migrator setup
        if (IS_V1_MIGRATOR_SETUP == true) {
            address v1MigratorAddress = addresses.getAddress("olympus-policy-v1-migrator");
            if (v1MigratorAddress == address(0)) {
                revert("v1Migrator address is not set");
            }
            v1Migrator = V1Migrator(v1MigratorAddress);
            vm.label(address(v1Migrator), "v1Migrator");

            console2.log("v1Migrator already deployed");
        } else {
            // Deploy V1Migrator
            v1Migrator = new V1Migrator(
                kernel,
                IERC20(address(OHMv1)),
                gOHM,
                bytes32(0) // merkleRoot (set to zero, not used in proposal test)
            );
            vm.label(address(v1Migrator), "v1Migrator");
            addresses.addAddress("olympus-policy-v1-migrator", address(v1Migrator));

            // Install V1Migrator into the kernel
            vm.prank(DAO_MS);
            kernel.executeAction(Actions.ActivatePolicy, address(v1Migrator));

            console2.log("v1Migrator deployed and setup");
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

        // Deploy wrapper with updated addresses (after simulation)
        proposalWrapper.deploy(addresses, address(this));

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

    // ========================================================================
    // End State Tests
    // ========================================================================

    /// @notice Test that the proposal execution leaves the system in the correct end state
    function test_proposalEndState() public view {
        // Verify V1Migrator is enabled
        assertTrue(v1Migrator.isEnabled(), "V1Migrator should be enabled");

        // Verify MigrationProposalHelper is activated
        assertTrue(
            migrationProposalHelper.isActivated(),
            "MigrationProposalHelper should be activated"
        );

        // Verify migration category is approved in Burner
        bytes32 migrationCategory = migrationProposalHelper.MIGRATION_CATEGORY();
        assertTrue(
            burner.categoryApproved(migrationCategory),
            "Migration category should be approved in Burner"
        );

        // Verify helper has no tokens left (all burned)
        assertEq(
            IERC20(GOHM).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 gOHM"
        );
        assertEq(
            IERC20(address(OHMv2)).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 OHMv2"
        );
        assertEq(
            IERC20(address(OHMv1)).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 OHMv1"
        );
        assertEq(
            IERC20(address(tempOHM)).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 tempOHM"
        );

        // Verify timelock has no tempOHM left
        assertEq(IERC20(address(tempOHM)).balanceOf(TIMELOCK), 0, "Timelock should have 0 tempOHM");
    }

    // ========================================================================
    // Griefing Protection Tests (L-03 fix)
    // ========================================================================

    /// @notice Test that validation passes when timelock has OHMv2 balance
    /// @dev This tests that the fix prevents griefing via OHMv2 donation to timelock.
    ///      Attempts to transfer OHMv2 to timelock if source has balance. Regardless,
    ///      validation should pass because timelock OHMv2 balance is no longer checked.
    function test_validate_passesWhenTimelockHasOHMv2() public {
        // Try to transfer OHMv2 to timelock from an external holder (simulates griefer)
        // Using a known OHM/DAI Uniswap V3 pool address that holds OHMv2
        address ohmv2Holder = 0x905dfCd5649343956c564A899Bbc391C767DCe34;
        uint256 balanceBefore = IERC20(address(OHMv2)).balanceOf(ohmv2Holder);
        if (balanceBefore > 1e18) {
            vm.prank(ohmv2Holder);
            ERC20(address(OHMv2)).safeTransfer(TIMELOCK, 1e18);
        }

        // Validation should pass because timelock OHMv2 balance is not checked (L-03 fix)
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Test that validation passes when timelock has gOHM balance
    /// @dev This tests that the fix prevents griefing via gOHM donation to timelock.
    ///      Attempts to transfer gOHM to timelock if source has balance. Regardless,
    ///      validation should pass because timelock gOHM balance is no longer checked.
    function test_validate_passesWhenTimelockHasGOHM() public {
        // Try to transfer gOHM to timelock from a holder (may have 0 balance after proposal)
        address gohmHolder = 0x31F8Cc382c9898b273eff4e0b7626a6987C846E8; // Legacy treasury
        uint256 balanceBefore = IERC20(GOHM).balanceOf(gohmHolder);
        if (balanceBefore > 1e18) {
            vm.prank(gohmHolder);
            ERC20(GOHM).safeTransfer(TIMELOCK, 1e18);
        }

        // Validation should pass because timelock gOHM balance is not checked (L-03 fix)
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Test that validation passes when timelock has OHMv1 balance
    /// @dev This tests that the fix prevents griefing via OHMv1 donation to timelock.
    ///      Attempts to transfer OHMv1 to timelock if source has balance. Regardless,
    ///      validation should pass because timelock OHMv1 balance is no longer checked.
    function test_validate_passesWhenTimelockHasOHMv1() public {
        // Try to transfer OHMv1 to timelock from a holder (may have 0 balance after proposal)
        address ohmv1Holder = 0x31F8Cc382c9898b273eff4e0b7626a6987C846E8; // Legacy treasury
        uint256 balanceBefore = IERC20(address(OHMv1)).balanceOf(ohmv1Holder);
        if (balanceBefore > 1e9) {
            vm.prank(ohmv1Holder);
            ERC20(address(OHMv1)).safeTransfer(TIMELOCK, 1e9);
        }

        // Validation should pass because timelock OHMv1 balance is not checked (L-03 fix)
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Test that validation passes when helper has 0 gOHM balance (proper cleanup)
    /// @dev This ensures helper contract IS checked for proper cleanup. After proposal
    ///      simulation, helper has 0 gOHM (properly burned). This test verifies validation
    ///      passes when helper is properly cleaned up.
    function test_validate_passesWhenHelperHasZeroGOHM() public view {
        // After proposal simulation, helper should have 0 gOHM
        assertEq(
            IERC20(GOHM).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 gOHM"
        );

        // Validation should pass when helper is properly cleaned up
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Test that validation passes when helper has 0 OHMv2 balance (proper cleanup)
    /// @dev This ensures helper contract IS checked for proper cleanup. After proposal
    ///      simulation, helper has 0 OHMv2 (properly burned).
    function test_validate_passesWhenHelperHasZeroOHMv2() public view {
        // After proposal simulation, helper should have 0 OHMv2
        assertEq(
            IERC20(address(OHMv2)).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 OHMv2"
        );

        // Validation should pass when helper is properly cleaned up
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Test that validation passes when helper has 0 OHMv1 balance (proper cleanup)
    /// @dev This ensures helper contract IS checked for proper cleanup. After proposal
    ///      simulation, helper has 0 OHMv1 (properly burned).
    function test_validate_passesWhenHelperHasZeroOHMv1() public view {
        // After proposal simulation, helper should have 0 OHMv1
        assertEq(
            IERC20(address(OHMv1)).balanceOf(address(migrationProposalHelper)),
            0,
            "Helper should have 0 OHMv1"
        );

        // Validation should pass when helper is properly cleaned up
        proposalWrapper.validate(addresses, address(this));
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)

/// @notice Test wrapper to expose internal _validate function for testing
contract MigrationProposalTestWrapper is MigrationProposal {
    function validate(Addresses addresses, address caller) external view {
        _validate(addresses, caller);
    }

    function deploy(Addresses addresses, address deployer) external {
        _deploy(addresses, deployer);
    }
}
