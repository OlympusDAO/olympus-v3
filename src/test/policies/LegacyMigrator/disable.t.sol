// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorDisableTest is LegacyMigratorTest {
    // ========== DISABLE TESTS ========== //
    // Given contract enabled
    //  [X] emergency role can disable it

    function test_givenEnabled_emergencyUserDisables_succeeds() public {
        vm.prank(emergencyUser);
        migrator.disable("");

        // Check contract is disabled
        assertEq(migrator.isEnabled(), false, "Contract should be disabled");
    }

    // Given non-emergency user tries to disable
    //  [X] it reverts

    function test_givenNonEmergencyUser_triesToDisable_reverts() public {
        bytes memory err = abi.encodeWithSignature("NotAuthorised()");
        vm.expectRevert(err);

        vm.prank(alice);
        migrator.disable("");
    }
}
