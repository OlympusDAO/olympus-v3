// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

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
        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
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

        assertEq(migrator.migrationCap(), newCap, "Migration cap should be updated");
    }

    // given any uint256 cap value
    //  [X] admin can set it as migration cap

    function test_givenAdmin_fuzz(uint256 newCap_) public {
        vm.prank(adminUser);
        migrator.setMigrationCap(newCap_);

        assertEq(migrator.migrationCap(), newCap_, "Migration cap should match input");
    }
}
