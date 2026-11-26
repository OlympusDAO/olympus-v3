// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {BurnerLoansCoreTest} from "src/test/policies/BurnerLoansCore/BurnerLoansCoreTest.sol";

contract BurnerLoansAuthCancelAllGrantsCoreIntegrationTest is BurnerLoansCoreTest {
    // Scenarios: BLAUTH-CANCELALL-P01.
    function test_whenAccountCancelled(address otherAccount_) public {
        vm.assume(
            otherAccount_ != address(0) && otherAccount_ != _borrower && otherAccount_ != _recipient
        );
        _approveOperator(_borrower, _recipient, type(uint48).max);
        _approveOperator(otherAccount_, _recipient, type(uint48).max);
        bytes memory otherGrant = abi.encode(_auth.getGrant(otherAccount_, _recipient));
        bytes32 otherStamp = _auth.captureAuthorization(otherAccount_, _recipient, 1);
        bytes32 beforeLedger = _ledger();
        vm.prank(_borrower);
        _auth.cancelAllGrants();
        assertEq(_auth.accountEpochs(_borrower), 1, "Independent account epoch advanced");
        assertEq(_auth.pairEpochs(_borrower, _recipient), 1, "Pair counter preserved");
        assertFalse(_isSenderAuthorized(_recipient, _borrower), "Old account epoch invalidated");
        assertEq(_auth.accountEpochs(otherAccount_), 0, "Other owner's account epoch is unchanged");
        assertEq(_auth.pairEpochs(otherAccount_, _recipient), 1, "Other owner's pair is unchanged");
        assertEq(
            abi.encode(_auth.getGrant(otherAccount_, _recipient)),
            otherGrant,
            "Other owner's complete grant is unchanged"
        );
        assertEq(
            _auth.captureAuthorization(otherAccount_, _recipient, 1),
            otherStamp,
            "Other owner's original stamp remains valid"
        );
        assertTrue(_isSenderAuthorized(_recipient, otherAccount_), "Other owner retains authority");
        assertEq(_ledger(), beforeLedger, "Account cancellation moves no custody or principal");
    }
}
