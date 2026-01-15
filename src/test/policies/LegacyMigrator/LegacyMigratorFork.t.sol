// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {LegacyMigrator} from "src/policies/LegacyMigrator.sol";
import {Kernel, Actions} from "src/Kernel.sol";

/// @title LegacyMigratorForkTest
/// @notice Fork test to verify LegacyMigrator works correctly against mainnet state
///
///         LegacyMigrator uses gOHM conversion (balanceTo -> balanceFrom)
///         to match the production migration flow. When the gOHM index is not at base
///         level (1e9), the double rounding can result in small losses (1 wei or more).
contract LegacyMigratorForkTest is Test {
    // ============ CONSTANTS ============ //

    /// @notice Block number for the fork
    uint256 constant FORK_BLOCK = 24070000;

    /// @notice Mainnet contract addresses
    address constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address constant OHM_V1 = 0x383518188C0C6d7730D91b2c03a03C837814a899;
    address constant OHM_V2 = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39; // Has admin role

    // ============ STATE VARIABLES ============ //

    IgOHM public gOHM;
    IERC20 public ohmV1;
    IERC20 public ohmV2;
    Kernel public kernel;
    LegacyMigrator public legacyMigrator;

    // ============ SETUP ============ //

    function setUp() public {
        // Create fork at fixed block for deterministic results
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Load mainnet contracts
        ohmV1 = IERC20(OHM_V1);
        ohmV2 = IERC20(OHM_V2);
        gOHM = IgOHM(GOHM);
        kernel = Kernel(KERNEL);

        // Label contracts for debugging
        vm.label(GOHM, "gOHM");
        vm.label(OHM_V1, "OHM_V1");
        vm.label(OHM_V2, "OHM_V2");
        vm.label(KERNEL, "KERNEL");

        // Deploy and activate LegacyMigrator for testing
        _deployLegacyMigrator();
    }

    /// @notice Deploy and configure LegacyMigrator
    function _deployLegacyMigrator() internal {
        // Set merkle root and migration cap
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 dummyRoot = keccak256(abi.encode("dummy"));
        uint256 initialCap = 1_000_000e9; // 1M OHM

        // Deploy LegacyMigrator with mainnet gOHM address
        legacyMigrator = new LegacyMigrator(kernel, ohmV1, gOHM, dummyRoot);
        vm.label(address(legacyMigrator), "LegacyMigrator");

        // Activate LegacyMigrator in the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(legacyMigrator));

        // Enable the migrator with initial cap (TIMELOCK has admin role on mainnet)
        vm.prank(TIMELOCK);
        legacyMigrator.enable(abi.encode(initialCap));
    }

    // ============ TESTS ============ //

    /// @notice Test that LegacyMigrator migration works correctly against mainnet
    ///         Validates that users receive the correct OHM v2 amount after gOHM conversion
    function test_legacyMigrator_migrationWorks(uint256 amount) public {
        // Bound to reasonable amounts
        amount = bound(amount, 1e9, 10_000e9);

        address user = makeAddr("user");
        vm.label(user, "user");

        // Calculate expected OHM v2 via gOHM conversion (what LegacyMigrator does internally)
        uint256 gohmAmount = gOHM.balanceTo(amount);
        uint256 expectedOHMv2 = gOHM.balanceFrom(gohmAmount);

        // Give user OHM v1 balance
        deal(address(ohmV1), user, amount);

        // Record balance before migration
        uint256 ohmV2Before = ohmV2.balanceOf(user);

        // Create a merkle proof that allows the user to migrate
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, amount))));
        bytes32[] memory proof = new bytes32[](0); // No siblings needed for single leaf tree

        // Set merkle root to include this user
        vm.prank(TIMELOCK);
        legacyMigrator.setMerkleRoot(leaf);

        // User approves and migrates via LegacyMigrator
        vm.startPrank(user);
        ohmV1.approve(address(legacyMigrator), amount);
        legacyMigrator.migrate(amount, proof, amount);
        vm.stopPrank();

        // Check the result
        uint256 ohmV2After = ohmV2.balanceOf(user);
        uint256 actualOHMv2 = ohmV2After - ohmV2Before;

        // User should receive the expected OHM v2 amount (after gOHM conversion)
        assertEq(actualOHMv2, expectedOHMv2, "User should receive expected OHM v2 amount");

        // Verify the conversion
        console2.log("====== LegacyMigrator Migration ======");
        console2.log("Input OHM v1:", amount);
        console2.log("Expected OHM v2:", expectedOHMv2);
        console2.log("Actual OHM v2:", actualOHMv2);
        console2.log("Match:", actualOHMv2 == expectedOHMv2);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
