// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";

contract BurnerLoansCoreCancelAuthorizationTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-CANCEL-AUTH-P01, BLCORE-CANCEL-AUTH-P03, BLCORE-CANCEL-AUTH-P04, BLCORE-CANCEL-AUTH-P05, BLCORE-CANCEL-AUTH-P06, BLCORE-CANCEL-AUTH-P07.
    function test_givenAnyLifecycle_whenCancelled(
        address account_,
        address operator_,
        bool active_,
        bool enabled_,
        bool existing_,
        uint256 nonce_
    ) public {
        nonce_ = bound(nonce_, 0, type(uint256).max - 1);
        if (existing_ && account_ != operator_) {
            vm.prank(account_);
            _core.setAuthorization(operator_, type(uint48).max);
        }
        _setNonce(account_, nonce_);
        _setCoreLifecycle(active_, enabled_);
        vm.expectEmit(true, true, true, true, address(_core));
        emit IOperatorAuth.AuthorizationSet(account_, account_, operator_, 0);
        vm.prank(account_);
        _core.cancelAuthorization(operator_);
        assertEq(
            _core.authorizationDeadlines(account_, operator_),
            0,
            "Selected grant removed even when absent or self"
        );
        assertEq(
            _core.authorizationNonces(account_),
            nonce_ + 1,
            "Cancellation always consumes one nonce"
        );
    }

    // Scenarios: BLCORE-CANCEL-AUTH-P01, BLCORE-CANCEL-AUTH-P07.
    function test_whenCancellationBoundarySeeds() public {
        test_givenAnyLifecycle_whenCancelled(address(0), address(0), true, true, false, 0);
        test_givenAnyLifecycle_whenCancelled(
            _borrower,
            _borrower,
            false,
            false,
            false,
            type(uint256).max - 1
        );
    }

    // Scenarios: BLCORE-CANCEL-AUTH-A01.
    function test_givenExhaustedNonce_whenCancelled_reverts(address account_) public {
        _setNonce(account_, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_NonceExhausted.selector, account_)
        );
        vm.prank(account_);
        _core.cancelAuthorization(_recipient);
        assertEq(
            _core.authorizationNonces(account_),
            type(uint256).max,
            "Exhausted cancellation preserves nonce"
        );
    }

    // Scenarios: BLCORE-CANCEL-AUTH-P02.
    function test_givenMultipleGrants_whenOneCancelled() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        vm.startPrank(auth.account);
        _core.setAuthorization(_recipient, type(uint48).max);
        _core.setAuthorization(address(0xC0FFEE), type(uint48).max);
        vm.stopPrank();
        // Re-sign at the current nonce: cancellation invalidates signatures for every operator.
        auth.nonce = 2;
        sig = _sign(auth, _SIGNER_KEY, _core.DOMAIN_SEPARATOR());
        vm.prank(auth.account);
        _core.cancelAuthorization(address(0xC0FFEE));
        assertEq(
            _core.authorizationDeadlines(auth.account, _recipient),
            type(uint48).max,
            "Other operator grant remains"
        );
        assertEq(
            _core.authorizationDeadlines(auth.account, address(0xC0FFEE)),
            0,
            "Only selected grant removed"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 2)
        );
        _core.setAuthorizationWithSig(auth, sig);
    }
}
