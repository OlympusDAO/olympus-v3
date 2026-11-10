// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansDebtAuthorizationCallbackTest} from "./fixtures/BurnerLoansDebtAuthorizationCallbackTest.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract BurnerLoansBorrowAuthorizationCallbacksTest is BurnerLoansDebtAuthorizationCallbackTest {
    // Scenarios: BLDEBT-BORROW-AUTH-C20.
    function test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts() public {
        _assertBorrowRollback(false, false);
    }

    // Scenarios: BLDEBT-BORROW-AUTH-C21.
    function test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts() public {
        _assertBorrowRollback(false, true);
    }

    // Scenarios: BLDEBT-BORROW-AUTH-C22.
    function test_givenPrincipalDeliveryCallback_whenOriginalGrantCancelled_reverts() public {
        _assertBorrowRollback(true, false);
    }

    // Scenarios: BLDEBT-BORROW-AUTH-C23.
    function test_givenPrincipalDeliveryCallback_whenIdenticalGrantReaccepted_reverts() public {
        _assertBorrowRollback(true, true);
    }

    function _assertBorrowRollback(bool delivery_, bool replacement_) internal {
        ReentrantFeeToken token = _prepareAuthorizationCallback(delivery_, false, replacement_);
        uint256 epoch = _auth.pairEpochs(_borrower, _recipient);
        bytes32 beforeState = _authorizationRollbackDigest();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_recipient);
        _debt.borrow(address(_asset), 100e9, _borrower, _recipient, delivery_ ? 0 : 7, address(0));
        _assertCallbackRollback(token, beforeState, epoch);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            0,
            "No borrowed principal survives completion failure"
        );
    }
}
// forge-lint: disable-end(unused-return)
