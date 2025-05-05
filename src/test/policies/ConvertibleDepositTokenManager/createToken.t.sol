// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {CDTokenManagerTest} from "./CDTokenManagerTest.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract CreateTokenCDTokenManagerTest is CDTokenManagerTest {
    // given the CD token manager is disabled
    //  [X] it reverts
    // given the caller does not have the admin role
    //  [X] it reverts
    // [X] it creates a new CD token

    function test_givenDisabled_reverts() public givenDisabled {
        // Expect
        _expectRevertDisabled();

        // Call function
        vm.prank(admin);
        cdTokenManager.createToken(iVault, 6, 100e2);
    }

    function test_givenNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        // Expect
        _expectRevertNotAdmin();

        // Call function
        vm.prank(caller_);
        cdTokenManager.createToken(iVault, 6, 100e2);
    }

    function test_success() public {
        // Call function
        vm.prank(admin);
        cdTokenManager.createToken(iVault, 6, 100e2);

        IConvertibleDepository.DepositToken[] memory depositTokens = cdTokenManager
            .getDepositTokens();

        // Assert CD token is created
        assertEq(depositTokens.length, 1, "Deposit tokens length mismatch");
        assertEq(depositTokens[0].vault, address(iVault), "Vault mismatch");
        assertEq(depositTokens[0].periodMonths, 6, "Period months mismatch");
        assertEq(depositTokens[0].reclaimRate, 100e2, "Reclaim rate mismatch");
    }
}
