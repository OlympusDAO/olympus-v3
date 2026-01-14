// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";

contract LegacyMigratorVerifyClaimTest is LegacyMigratorTest {
    // ========== VERIFY CLAIM TESTS ========== //

    // when the proof is invalid
    //  [X] it returns false

    function test_whenInvalidProof() public view {
        bytes32[] memory invalidProof = new bytes32[](0);

        assertFalse(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, invalidProof),
            "Invalid proof should fail"
        );
    }

    // when the allocated amount is wrong
    //  [X] it returns false

    function test_whenWrongAmount() public view {
        assertFalse(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE + 1, aliceProof),
            "Wrong amount should fail"
        );
    }

    // given valid proof and correct allocated amount
    //  given the contract is disabled
    //   [X] it returns true for alice

    function test_givenDisabled_validClaim() public givenContractDisabled {
        assertTrue(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, aliceProof),
            "Alice's claim should be valid"
        );

        assertTrue(
            migrator.verifyClaim(bob, BOB_ALLOWANCE, bobProof),
            "Bob's claim should be valid"
        );
    }

    //  [X] it returns true for alice
    //  [X] it returns true for bob

    function test_validClaim() public view {
        assertTrue(
            migrator.verifyClaim(alice, ALICE_ALLOWANCE, aliceProof),
            "Alice's claim should be valid"
        );

        assertTrue(
            migrator.verifyClaim(bob, BOB_ALLOWANCE, bobProof),
            "Bob's claim should be valid"
        );
    }
}
