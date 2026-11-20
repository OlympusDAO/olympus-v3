// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCoreTest} from "src/test/policies/BurnerLoansCore/BurnerLoansCoreTest.sol";

contract BurnerLoansAuthCancelGrantCoreIntegrationTest is BurnerLoansCoreTest {
    // Scenarios: BLAUTH-CANCEL-P01.
    function test_whenPairCancelled() public {
        _approveOperator(_borrower, _recipient, type(uint48).max);
        _approveOperator(_borrower, address(0xC0FFEE), type(uint48).max);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        assertEq(_auth.pairEpochs(_borrower, _recipient), 2, "Cancellation advances selected pair");
        assertFalse(_isSenderAuthorized(_recipient, _borrower), "Selected authority invalidated");
        assertTrue(
            _isSenderAuthorized(address(0xC0FFEE), _borrower),
            "Other operator remains authorized"
        );
    }

    // Scenarios: BLAUTH-CANCEL-L01.
    function test_whenCancelledWhileDisabled() public {
        _approveOperator(_borrower, _recipient, type(uint48).max);
        _core.disable("");
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        assertEq(_auth.pairEpochs(_borrower, _recipient), 2, "Cancellation advances a paused pair");
        _core.enable("");
        assertFalse(
            _isSenderAuthorized(_recipient, _borrower),
            "Cancelled authority stays invalid after Core enablement"
        );
    }

    // Scenarios: BLAUTH-CANCEL-N01.
    function test_whenCancellationEpochExhausted_reverts() public {
        _setPairEpoch(_borrower, _recipient, type(uint256).max);
        vm.expectRevert(IOperatorAuth.OperatorAuth_EpochExhausted.selector);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
    }

    // Scenarios: BLAUTH-CANCEL-N02.
    function test_whenLastPairEpochCancelled() public {
        _setPairEpoch(_borrower, _recipient, type(uint256).max - 1);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            type(uint256).max,
            "Final cancellation epoch usable once"
        );
    }

    // Scenarios: BLAUTH-CANCEL-A01.
    function test_whenUnrelatedAccountCancels(address caller_) public {
        vm.assume(caller_ != _borrower && caller_ != address(0) && caller_ != _recipient);
        _approveOperator(_borrower, _recipient, type(uint48).max);
        vm.prank(caller_);
        _auth.cancelGrant(_recipient);
        assertTrue(
            _isSenderAuthorized(_recipient, _borrower),
            "Caller cancels only their own authority"
        );
        assertEq(_auth.pairEpochs(caller_, _recipient), 1, "Absent own pair still advances");
    }
}
