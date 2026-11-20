// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansDebtAuthorizationCallbackTest} from "./fixtures/BurnerLoansDebtAuthorizationCallbackTest.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract BurnerLoansExtendAuthorizationCallbacksTest is BurnerLoansDebtAuthorizationCallbackTest {
    // Scenarios: BLEXT-EXTEND-AUTH-C20.
    function test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts() public {
        _assertExtendRollback(false);
    }

    // Scenarios: BLEXT-EXTEND-AUTH-C21.
    function test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts() public {
        _assertExtendRollback(true);
    }

    function _assertExtendRollback(bool replacement_) internal {
        ReentrantFeeToken token = _prepareAuthorizationCallback(false, true, replacement_);
        uint256 epoch = _auth.pairEpochs(_borrower, _recipient);
        uint48 maturity = _lens.getPosition(address(_asset), _borrower).maturity;
        bytes32 beforeState = _authorizationRollbackDigest();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_recipient);
        _debt.extend(address(_asset), _borrower, 1, 7, address(0));
        _assertCallbackRollback(token, beforeState, epoch);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).maturity,
            maturity,
            "No maturity extension survives completion failure"
        );
    }
}
// forge-lint: disable-end(unused-return)
