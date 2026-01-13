// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorVerifyClaimTest is LegacyMigratorTest {
    function test_verifyClaim_validClaim() public {
        // Alice's claim should be valid
        assertTrue(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, aliceProof),
            "Alice's claim should be valid"
        );

        // Bob's claim should be valid
        assertTrue(
            migrator.verifyClaim(bob, BOB_ALLOWANCE, bobProof),
            "Bob's claim should be valid"
        );
    }

    function test_verifyClaim_invalidClaim() public {
        // Invalid proof should fail
        bytes32[] memory invalidProof = new bytes32[](0);
        assertFalse(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, invalidProof),
            "Invalid proof should fail"
        );
    }
}
