// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {CDTokenManagerTest} from "./CDTokenManagerTest.sol";

contract SetTokenReclaimRateCDTokenManagerTest is CDTokenManagerTest {
    // given the CD token manager is disabled
    //  [X] it reverts
    // given the caller does not have the admin role
    //  [X] it reverts
    // [X] it sets the reclaim rate for the CD token

    function test_givenDisabled_reverts() public givenDisabled {
        // Expect
        _expectRevertDisabled();

        // Call function
        vm.prank(admin);
        cdTokenManager.setTokenReclaimRate(cdToken, 100e2);
    }

    function test_givenNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        // Expect
        _expectRevertNotAdmin();

        // Call function
        vm.prank(caller_);
        cdTokenManager.setTokenReclaimRate(cdToken, 100e2);
    }

    function test_success() public givenCDTokenCreated(iVault, 6) {
        // Call function
        vm.prank(admin);
        cdTokenManager.setTokenReclaimRate(cdToken, 100e2);

        // Assert
        assertEq(CDEPO.reclaimRate(address(cdToken)), 100e2, "Reclaim rate not set");
        assertEq(cdTokenManager.getTokenReclaimRate(cdToken), 100e2, "Reclaim rate mismatch");
    }
}
