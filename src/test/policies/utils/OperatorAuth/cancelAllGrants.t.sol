// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthCancelAllGrantsTest is OperatorAuthTest {
    // Scenarios: OAALL-P01.
    function test_givenGrant_whenCancelled_preservesPairs() public {
        _approve(_grant(true));
        vm.prank(_account);
        _auth.cancelAllGrants();
        assertEq(_auth.accountEpochs(_account), 1, "Account epoch advances");
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Pair counters never reset");
        _expectInvalidContext();
        _auth.captureAuthorization(_account, _operator, 1);
    }

    // Scenarios: OAALL-P02.
    function test_givenFuturePairSignature_whenAccountCancelled_reverts() public {
        IOperatorAuth.Grant memory g = _grant(true);
        g.pairEpoch = 1;
        bytes memory signature = _signature(g, "");
        vm.startPrank(_account);
        _auth.cancelAllGrants();
        _auth.cancelGrant(_operator);
        vm.stopPrank();
        vm.prank(_operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidEpoch.selector);
        _auth.acceptGrant(g, "", signature);
    }

    // Scenarios: OAALL-L01.
    function test_givenAdmissionDisabled_whenCancelled() public {
        _auth.setCreationAllowed(false);
        _auth.setUseAllowed(false);
        vm.prank(_account);
        _auth.cancelAllGrants();
        assertEq(_auth.accountEpochs(_account), 1, "Account cancellation bypasses readiness");
    }

    // Scenarios: OAALL-N01.
    function test_givenAccountMax_whenCancelled_reverts() public {
        _accountEpoch(type(uint256).max);
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_EpochExhausted.selector);
        _auth.cancelAllGrants();
    }
}
// forge-lint: disable-end(unused-return)
