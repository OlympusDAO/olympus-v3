// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity ^0.8.0;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Burner} from "src/policies/Burner.sol";
import {OwnedERC20} from "src/external/OwnedERC20.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";
import {IERC20Errors} from "@openzeppelin-5.3.0/interfaces/draft-IERC6093.sol";

import {MigrationProposalHelper} from "src/proposals/MigrationProposalHelper.sol";

/// @notice Fork test for MigrationProposalHelper
/// @dev    Tests the activate() function which performs the OHM v1 to OHM v2 migration and burn
contract MigrationProposalHelperForkTest is Test {
    // ======================================================================
    // Constants
    // ======================================================================

    /// @dev Block before migration proposal execution
    uint256 internal constant FORK_BLOCK = 24070000;

    // Mainnet addresses
    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;

    // Legacy contracts (hardcoded in MigrationProposalHelper)
    address public constant LEGACY_TREASURY = 0x31F8Cc382c9898b273eff4e0b7626a6987C846E8;
    address public constant MIGRATOR = 0x184f3FAd8618a6F458C16bae63F70C426fE784B3;
    address public constant STAKING = 0xB63cac384247597756545b500253ff8E607a8020;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address public constant OHMV1 = 0x383518188C0C6d7730D91b2c03a03C837814a899;
    address public constant OHMV2 = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

    // Test configuration
    uint256 internal constant OHM_V1_TO_MIGRATE = 197735188979073; // ~197.7k OHM v1 (1e9 decimals)
    uint256 internal constant TEMPOHM_TO_MINT = OHM_V1_TO_MIGRATE * 1e9; // Convert to 1e18 decimals

    // ======================================================================
    // Contracts
    // ======================================================================

    Kernel public kernel;
    ROLESv1 public roles;
    RolesAdmin public rolesAdmin;
    IOlympusTreasury public legacyTreasury;
    Burner public burner;
    OwnedERC20 public tempOHM;
    MigrationProposalHelper public helper;

    // Token interfaces
    IERC20 public ohmV1;
    IgOHM public gOHM;
    IERC20 public ohmV2;

    // ======================================================================
    // Setup
    // ======================================================================

    function setUp() public {
        // Create mainnet fork
        vm.createSelectFork("mainnet", FORK_BLOCK);

        // Load mainnet contracts
        kernel = Kernel(KERNEL);
        roles = ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);
        legacyTreasury = IOlympusTreasury(LEGACY_TREASURY);

        ohmV1 = IERC20(OHMV1);
        gOHM = IgOHM(GOHM);
        ohmV2 = IERC20(OHMV2);

        // Deploy tempOHM
        tempOHM = new OwnedERC20("TempOHM", "tempOHM", DAO_MS);

        // Deploy burner
        burner = new Burner(kernel, SolmateERC20(OHMV2));
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(burner));

        // Deploy helper
        helper = new MigrationProposalHelper(
            TIMELOCK, // owner
            DAO_MS, // admin
            address(burner),
            address(tempOHM),
            OHM_V1_TO_MIGRATE
        );

        // Setup legacy treasury permissions
        _setupLegacyTreasuryPermissions();
    }

    function _setupLegacyTreasuryPermissions() internal {
        // Queue tempOHM as reserve token
        vm.prank(DAO_MS);
        legacyTreasury.queue(IOlympusTreasury.MANAGING.RESERVETOKEN, address(tempOHM));

        // Queue helper as reserve depositor
        vm.prank(DAO_MS);
        legacyTreasury.queue(IOlympusTreasury.MANAGING.RESERVEDEPOSITOR, address(helper));

        // Warp past queue expiry
        uint256 reserveTokenQueueBlock = legacyTreasury.reserveTokenQueue(address(tempOHM));
        uint256 reserveDepositorQueueBlock = legacyTreasury.reserveDepositorQueue(address(helper));
        uint256 queueExpiryBlock = reserveTokenQueueBlock > reserveDepositorQueueBlock
            ? reserveTokenQueueBlock
            : reserveDepositorQueueBlock;
        vm.roll(queueExpiryBlock);

        // Toggle tempOHM as reserve token
        vm.prank(DAO_MS);
        legacyTreasury.toggle(IOlympusTreasury.MANAGING.RESERVETOKEN, address(tempOHM), address(0));

        // Toggle helper as reserve depositor
        vm.prank(DAO_MS);
        legacyTreasury.toggle(
            IOlympusTreasury.MANAGING.RESERVEDEPOSITOR,
            address(helper),
            address(0)
        );
    }

    function _grantBurnerAdminRole() internal {
        vm.prank(TIMELOCK);
        rolesAdmin.grantRole("burner_admin", address(helper));
    }

    function _mintTempOHMToTimelock(uint256 amount) internal {
        vm.prank(DAO_MS);
        tempOHM.mint(TIMELOCK, amount);
    }

    function _approveTempOHM() internal {
        vm.prank(TIMELOCK);
        tempOHM.approve(address(helper), type(uint256).max);
    }

    function _setupForActivation() internal {
        _grantBurnerAdminRole();
        _mintTempOHMToTimelock(TEMPOHM_TO_MINT);
        _approveTempOHM();
    }

    /// @notice Helper function to assert all token balances are zero after activation
    /// @dev    Verifies TempOHM, OHMv1, gOHM, and OHMv2 balances are all 0
    function _assertAllTokenBalancesAreZero() internal view {
        assertEq(tempOHM.balanceOf(address(helper)), 0, "Helper should have no TempOHM");
        assertEq(ohmV1.balanceOf(address(helper)), 0, "Helper should have no OHMv1");
        assertEq(gOHM.balanceOf(address(helper)), 0, "Helper should have no gOHM");
        assertEq(ohmV2.balanceOf(address(helper)), 0, "Helper should have no OHMv2");
    }

    // ======================================================================
    // Access Control Tests
    // ======================================================================

    // given the caller is not the timelock (owner)
    //  [X] it reverts

    function test_activate_givenCallerNotTimelock_reverts(address caller_) public {
        vm.assume(caller_ != TIMELOCK);
        _setupForActivation();

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        helper.activate();
    }

    // ======================================================================
    // Single-Use Constraint Tests
    // ======================================================================

    // given activate has already been called
    //  [X] it reverts

    function test_activate_givenAlreadyActivated_reverts() public {
        _setupForActivation();

        // First activation
        vm.prank(TIMELOCK);
        helper.activate();

        // Second activation should revert
        vm.expectRevert(MigrationProposalHelper.AlreadyActivated.selector);
        vm.prank(TIMELOCK);
        helper.activate();
    }

    // ======================================================================
    // Category Idempotency Tests
    // ======================================================================

    // given the migration category already exists in Burner
    //  when activate is called
    //    [X] it does not revert
    //    [X] it completes successfully

    function test_activate_givenCategoryExists_succeeds() public {
        // Pre-add the migration category to Burner via DAO_MS
        bytes32 migrationCategory = helper.MIGRATION_CATEGORY();
        vm.prank(TIMELOCK);
        rolesAdmin.grantRole("burner_admin", TIMELOCK);
        vm.prank(TIMELOCK);
        burner.addCategory(migrationCategory);

        // Verify category exists
        assertTrue(
            burner.categoryApproved(migrationCategory),
            "Migration category should be approved"
        );

        // Revoke burner_admin from TIMELOCK
        vm.prank(TIMELOCK);
        rolesAdmin.revokeRole("burner_admin", TIMELOCK);

        // Now setup for activation (grants burner_admin to helper)
        _setupForActivation();

        // Activate should succeed despite category already existing
        vm.prank(TIMELOCK);
        helper.activate();

        // Verify activation completed
        assertTrue(helper.isActivated(), "Helper should be activated");

        // Verify no tokens remain
        _assertAllTokenBalancesAreZero();
    }

    // ======================================================================
    // TempOHM Approval Tests
    // ======================================================================

    // given the timelock has not approved TempOHM spending
    //  [X] it reverts

    function test_activate_givenTempOHMNotApproved_reverts() public {
        _grantBurnerAdminRole();
        _mintTempOHMToTimelock(TEMPOHM_TO_MINT);
        // Do NOT approve TempOHM

        // SafeTransferLib wraps the revert, so we expect the wrapped error
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(TIMELOCK);
        helper.activate();
    }

    // ======================================================================
    // TempOHM Balance Tests
    // ======================================================================

    // given the timelock does not have enough TempOHM balance
    //  [X] it reverts

    function test_activate_givenInsufficientTempOHM_reverts() public {
        _grantBurnerAdminRole();
        // Mint only half the required amount
        _mintTempOHMToTimelock(TEMPOHM_TO_MINT / 2);
        _approveTempOHM();

        // Legacy treasury calls transferFrom on OZ ERC20, which reverts with custom error
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(helper),
                TEMPOHM_TO_MINT / 2,
                TEMPOHM_TO_MINT
            )
        );

        // Call function
        vm.prank(TIMELOCK);
        helper.activate();

        // Verify helper was not activated
        assertFalse(helper.isActivated(), "Helper should not be activated");
    }

    // ======================================================================
    // Excess OHMv1 Handling Tests
    // ======================================================================

    // given there is excess OHMv1 minted to the helper
    //  when activate is called
    //    [X] it migrates only OHMv1ToMigrate
    //    [X] it burns the excess OHMv1

    function test_activate_givenExcessOHMv1Minted() public {
        _setupForActivation();

        // Deal excess OHMv1 directly to helper
        deal(OHMV1, address(helper), 1000e9); // 1000 OHM v1 (1e9 decimals)

        // Activate
        vm.prank(TIMELOCK);
        helper.activate();

        // Verify OHMv1 was burned (should be 0 after activation)
        assertEq(
            ohmV1.balanceOf(address(helper)),
            0,
            "Helper should have no OHMv1 after activation"
        );
        assertTrue(helper.isActivated(), "Helper should be activated");
    }

    // ======================================================================
    // Migration and Burn Tests
    // ======================================================================

    // given all prerequisites are met
    //  when activate is called
    //    [X] it migrates OHMv1 to gOHM
    //    [X] it unstakes gOHM to OHMv2
    //    [X] it burns OHMv2
    //    [X] it emits Activated event
    //    [X] it leaves no tokens in the helper
    //    [X] it adds the migration category to burner

    function test_activate_givenPrerequisitesMet() public {
        _setupForActivation();

        // Record OHMv2 total supply before
        uint256 ohmV2SupplyBefore = ohmV2.totalSupply();

        // Expect Activated event
        vm.expectEmit(true, false, false, true);
        emit MigrationProposalHelper.Activated(TIMELOCK);

        // Activate
        vm.prank(TIMELOCK);
        helper.activate();

        // Verify OHMv2 was burned (total supply decreased)
        uint256 ohmV2SupplyAfter = ohmV2.totalSupply();
        assertTrue(
            ohmV2SupplyAfter < ohmV2SupplyBefore,
            "OHMv2 supply should decrease after burning"
        );
        assertTrue(helper.isActivated(), "Helper should be activated");

        // Verify migration category was added
        bytes32 migrationCategory = helper.MIGRATION_CATEGORY();
        assertTrue(
            burner.categoryApproved(migrationCategory),
            "Migration category should be approved"
        );

        // Verify no tokens remain
        _assertAllTokenBalancesAreZero();
    }

    // ======================================================================
    // Legacy Treasury Capacity Tests
    // ======================================================================

    // given OHMv1ToMigrate exceeds legacy treasury capacity
    //  when activate is called
    //    [X] it reverts with "OHMv1 minted"

    function test_activate_givenOHMv1ToMigrateExceedsCapacity_reverts() public {
        _setupForActivation();

        // Set OHMv1ToMigrate to an unrealistically high amount that exceeds reserves
        vm.prank(TIMELOCK);
        helper.setOHMv1ToMigrate(1e15); // 1 billion OHM v1 (1e9 decimals)

        // Mint enough tempOHM to pass the tempOHM balance check
        vm.prank(DAO_MS);
        tempOHM.mint(TIMELOCK, 1e24); // 1e15 * 1e9 = 1e24 tempOHM

        _approveTempOHM();

        // TokenMigrator will revert when trying to mint more OHMv1 than it can support
        vm.expectRevert("OHMv1 minted");
        vm.prank(TIMELOCK);
        helper.activate();

        // Verify helper was not activated
        assertFalse(helper.isActivated(), "Helper should not be activated");
    }

    // ======================================================================
    // setOHMv1ToMigrate Tests
    // ======================================================================

    // given the caller is not owner or admin
    //  [X] it reverts

    function test_setOHMv1ToMigrate_givenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != TIMELOCK && caller_ != DAO_MS);

        uint256 newOHMv1ToMigrate = 100000000000000; // 100k OHM (1e9 decimals)

        // Expect revert
        vm.expectRevert(MigrationProposalHelper.Unauthorized.selector);

        // Call function
        vm.prank(caller_);
        helper.setOHMv1ToMigrate(newOHMv1ToMigrate);
    }

    // given the caller is the admin (DAO MS)
    //  [X] it updates OHMv1ToMigrate
    //  [X] it updates getTempOHMToDeposit

    function test_setOHMv1ToMigrate_givenAdmin() public {
        uint256 newOHMv1ToMigrate = 50000000000000; // 50k OHM (1e9 decimals)
        uint256 expectedTempOHM = newOHMv1ToMigrate * 1e9; // Convert to 1e18 decimals

        vm.prank(DAO_MS);
        helper.setOHMv1ToMigrate(newOHMv1ToMigrate);

        assertEq(helper.OHMv1ToMigrate(), newOHMv1ToMigrate, "OHMv1ToMigrate should be updated");
        assertEq(
            helper.getTempOHMToDeposit(),
            expectedTempOHM,
            "getTempOHMToDeposit should return OHMv1ToMigrate * 1e9"
        );
    }

    // given the caller is the owner (timelock)
    //  [X] it updates OHMv1ToMigrate
    //  [X] it updates getTempOHMToDeposit

    function test_setOHMv1ToMigrate_givenTimelock() public {
        uint256 newOHMv1ToMigrate = 200000000000000; // 200k OHM (1e9 decimals)
        uint256 expectedTempOHM = newOHMv1ToMigrate * 1e9; // Convert to 1e18 decimals

        vm.prank(TIMELOCK);
        helper.setOHMv1ToMigrate(newOHMv1ToMigrate);

        assertEq(helper.OHMv1ToMigrate(), newOHMv1ToMigrate, "OHMv1ToMigrate should be updated");
        assertEq(
            helper.getTempOHMToDeposit(),
            expectedTempOHM,
            "getTempOHMToDeposit should return OHMv1ToMigrate * 1e9"
        );
    }

    // ======================================================================
    // Helper Function Tests
    // ======================================================================

    // given OHMv1ToMigrate is set
    //  when getTempOHMToDeposit is called
    //    [X] it returns the correct amount

    function test_getTempOHMToDeposit() public view {
        uint256 expectedTempOHM = helper.OHMv1ToMigrate() * 1e9;
        assertEq(
            helper.getTempOHMToDeposit(),
            expectedTempOHM,
            "getTempOHMToDeposit should return OHMv1ToMigrate * 1e9"
        );
    }

    // ======================================================================
    // Rescue Function Tests
    // ======================================================================

    // when owner calls rescue
    //  [X] it transfers entire balance to owner

    function test_rescue_givenOwner_transfersToOwner() public {
        // Deal random tokens to helper
        uint256 amount = 100e18;
        deal(OHMV2, address(helper), amount);

        uint256 balanceBefore = ohmV2.balanceOf(TIMELOCK);

        // Rescue as owner
        vm.prank(TIMELOCK);
        helper.rescue(IERC20(OHMV2));

        // Verify balance transferred
        assertEq(
            ohmV2.balanceOf(TIMELOCK),
            balanceBefore + amount,
            "Owner should receive rescued tokens"
        );
        assertEq(ohmV2.balanceOf(address(helper)), 0, "Helper should have zero balance");
    }

    // when admin calls rescue
    //  [X] it transfers entire balance to admin

    function test_rescue_givenAdmin_transfersToAdmin() public {
        // Deal random tokens to helper
        uint256 amount = 100e18;
        deal(OHMV2, address(helper), amount);

        uint256 balanceBefore = ohmV2.balanceOf(DAO_MS);

        // Rescue as admin
        vm.prank(DAO_MS);
        helper.rescue(IERC20(OHMV2));

        // Verify balance transferred
        assertEq(
            ohmV2.balanceOf(DAO_MS),
            balanceBefore + amount,
            "Admin should receive rescued tokens"
        );
        assertEq(ohmV2.balanceOf(address(helper)), 0, "Helper should have zero balance");
    }

    // given caller is not owner and not admin
    //  when attempting to rescue
    //    [X] it reverts

    function test_rescue_givenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != TIMELOCK && caller_ != DAO_MS);

        // Deal random tokens to helper
        uint256 amount = 100e18;
        deal(OHMV2, address(helper), amount);

        // Expect revert when unauthorized user tries to rescue
        vm.expectRevert(MigrationProposalHelper.Unauthorized.selector);
        vm.prank(caller_);
        helper.rescue(IERC20(OHMV2));
    }

    // given token is zero address
    //  when attempting to rescue
    //    [X] it reverts

    function test_rescue_givenZeroToken_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(MigrationProposalHelper.InvalidParams.selector, "token")
        );
        vm.prank(TIMELOCK);
        helper.rescue(IERC20(address(0)));
    }

    // given contract has no token balance
    //  when attempting to rescue
    //    [X] it reverts

    function test_rescue_givenZeroBalance_reverts() public {
        // Don't deal any tokens to helper

        vm.expectRevert(
            abi.encodeWithSelector(MigrationProposalHelper.InvalidParams.selector, "balance")
        );
        vm.prank(TIMELOCK);
        helper.rescue(IERC20(OHMV2));
    }

    // when owner calls rescue
    //  [X] it emits Rescued event

    function test_rescue_givenOwner_emitsRescuedEvent() public {
        // Deal random tokens to helper
        uint256 amount = 100e18;
        deal(OHMV2, address(helper), amount);

        // Expect Rescued event
        vm.expectEmit(true, true, false, true);
        emit MigrationProposalHelper.Rescued(OHMV2, TIMELOCK, amount);

        // Rescue as owner
        vm.prank(TIMELOCK);
        helper.rescue(IERC20(OHMV2));
    }

    // given contract has been activated
    //  when owner calls rescue
    //    [X] it still works (rescue is independent of activation state)

    function test_rescue_givenActivated_stillWorks() public {
        // Setup and activate
        _setupForActivation();
        vm.prank(TIMELOCK);
        helper.activate();

        // Deal random tokens to helper (simulating accidental send)
        uint256 amount = 100e18;
        deal(OHMV2, address(helper), amount);

        uint256 balanceBefore = ohmV2.balanceOf(TIMELOCK);

        // Rescue as owner
        vm.prank(TIMELOCK);
        helper.rescue(IERC20(OHMV2));

        // Verify balance transferred
        assertEq(
            ohmV2.balanceOf(TIMELOCK),
            balanceBefore + amount,
            "Owner should receive rescued tokens after activation"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
