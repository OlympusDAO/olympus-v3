// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILegacyMigrator} from "src/interfaces/ILegacyMigrator.sol";

contract LegacyMigratorSetMigrationCapTest is LegacyMigratorTest {
    event MigrationCapUpdated(uint256 indexed newCap, uint256 indexed oldCap);

    uint256 internal constant NEW_CAP = 20000e9;

    // ========== SET MIGRATION CAP TESTS ========== //

    //  given contract is disabled
    //   [X] it reverts

    function test_givenDisabled_reverts() public givenContractDisabled {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(adminUser);
        migrator.setMigrationCap(NEW_CAP);
    }

    // given caller does not have admin role
    //  [X] it reverts

    function test_givenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != adminUser);

        // Expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("admin")
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(caller_);
        migrator.setMigrationCap(NEW_CAP);
    }

    // given caller has admin role
    //  given new cap is higher than old cap
    //   [X] it increases MINTR approval
    //   [X] it sets the migration cap

    function test_givenAdmin_setsHigherCap_increasesApproval() public {
        uint256 newCap = INITIAL_CAP + 1000e9;

        // Expect emit
        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        // Call function
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        // Assert state
        assertEq(migrator.remainingMintApproval(), newCap, "Migration cap should be updated");
    }

    //  given new cap is lower than old cap
    //   [X] it decreases MINTR approval
    //   [X] it sets the migration cap

    function test_givenAdmin_setsLowerCap_decreasesApproval() public {
        uint256 newCap = INITIAL_CAP - 1000e9;

        vm.expectEmit(false, false, false, true);
        emit MigrationCapUpdated(newCap, INITIAL_CAP);

        vm.prank(adminUser);
        migrator.setMigrationCap(newCap);

        assertEq(migrator.remainingMintApproval(), newCap, "Migration cap should be updated");
    }

    // given any uint256 cap value
    //  [X] admin can set it as migration cap

    function test_givenAdmin_fuzz(uint256 newCap_) public {
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap_);

        assertEq(migrator.remainingMintApproval(), newCap_, "Migration cap should match input");
    }

    // ========== CAP SYNC TESTS ========== //

    // given the cap is set to 0
    //  [X] migrations are blocked

    function test_givenCapSetToZero_migrationsBlocked() public givenAliceApproved {
        // Set cap to 0
        vm.prank(adminUser);
        migrator.setMigrationCap(0);

        // Verify MINTR approval is 0
        assertEq(MINTR.mintApproval(address(migrator)), 0, "MINTR approval should be 0");

        // Expect revert when trying to migrate
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.CapExceeded.selector, 100e9, 0);
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(100e9, aliceProof, ALICE_ALLOWANCE);
    }

    // given the cap is set to a specific value X
    //  [X] migrations up to X work
    //  [X] migrations exceeding X fail

    function test_givenCapSetToX_amountXWorks_amountXPlusOneFails() public givenAliceApproved {
        uint256 X = 200e9;

        // Set cap to X
        vm.prank(adminUser);
        migrator.setMigrationCap(X);

        // Alice can migrate exactly X
        vm.prank(alice);
        migrator.migrate(X, aliceProof, ALICE_ALLOWANCE);

        // MINTR approval is now 0
        assertEq(MINTR.mintApproval(address(migrator)), 0, "MINTR approval should be 0");

        // Trying to migrate more should fail
        bytes memory err = abi.encodeWithSelector(ILegacyMigrator.CapExceeded.selector, 1, 0);
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.migrate(1, aliceProof, ALICE_ALLOWANCE);
    }

    // given the cap is set multiple times
    //  [X] migrationCap always reflects current MINTR approval

    function test_givenMultipleCapChanges_migrationCapReflectsMINTR() public {
        // Initially, migrationCap should equal INITIAL_CAP
        assertEq(migrator.remainingMintApproval(), INITIAL_CAP, "Initial cap should match");
        assertEq(MINTR.mintApproval(address(migrator)), INITIAL_CAP, "MINTR should match");

        // Set cap to a lower value
        uint256 lowerCap = INITIAL_CAP - 500e9;
        vm.prank(adminUser);
        migrator.setMigrationCap(lowerCap);
        assertEq(migrator.remainingMintApproval(), lowerCap, "Cap should be lower");
        assertEq(MINTR.mintApproval(address(migrator)), lowerCap, "MINTR should match");

        // Set cap to a higher value
        uint256 higherCap = lowerCap + 1000e9;
        vm.prank(adminUser);
        migrator.setMigrationCap(higherCap);
        assertEq(migrator.remainingMintApproval(), higherCap, "Cap should be higher");
        assertEq(MINTR.mintApproval(address(migrator)), higherCap, "MINTR should match");
    }
}
