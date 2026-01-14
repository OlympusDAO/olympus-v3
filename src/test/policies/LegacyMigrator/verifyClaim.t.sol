// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorVerifyClaimTest is LegacyMigratorTest {
    // ========== VERIFY CLAIM TESTS ========== //
    // Given valid proof and amount
    //  [X] it returns true for alice
    //  [X] it returns true for bob

    function test_verifyClaim_validClaim() public view {
        assertTrue(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, aliceProof),
            "Alice's claim should be valid"
        );

        assertTrue(
            migrator.verifyClaim(bob, BOB_ALLOWANCE, bobProof),
            "Bob's claim should be valid"
        );
    }

    // Given invalid proof
    //  [X] it returns false

    function test_verifyClaim_invalidClaim() public view {
        bytes32[] memory invalidProof = new bytes32[](0);

        assertFalse(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, invalidProof),
            "Invalid proof should fail"
        );
    }
}
