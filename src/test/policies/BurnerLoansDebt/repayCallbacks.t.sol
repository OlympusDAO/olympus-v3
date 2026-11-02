// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansDebtRepayCallbacksTest is BurnerLoansDebtTest {
    // Scenarios: BLDEBT-REPAY-C08.
    function test_givenOhmCallback_whenRepaid_thenMandatoryReceiptFailureRollsBack()
        public
        givenDebtBearingPosition
    {
        ReentrantFeeToken token = _prepareOhmCallback();

        token.setBubbleCallbackFailure(true);
        uint256 balance = token.balanceOf(_borrower);
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(token.balanceOf(_borrower), balance, "Payer funds restored");
        assertEq(token.allowance(_borrower, address(_core)), 100e9, "Finite allowance restored");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Inventory debt restored");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            100e9,
            "FLOAN debt restored"
        );
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    function test_givenCaughtOhmCallback_whenRepaid_thenOnlyOuterOperationSucceeds()
        public
        givenDebtBearingPosition
    {
        ReentrantFeeToken token = _prepareOhmCallback();

        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Funded permissionless nested repay reaches Core guard"
        );
    }

    function _prepareOhmCallback() internal returns (ReentrantFeeToken token) {
        vm.roll(block.number + 1);
        // Both mocks inherit the same OZ ERC20 storage layout. Etching adds only callback code;
        // Core's immutable OHM decimal scale remains the original 9, and no pricing uses metadata here.
        ReentrantFeeToken template = new ReentrantFeeToken();
        vm.etch(address(_ohm), address(template).code);
        token = ReentrantFeeToken(address(_ohm));
        token.mint(address(token), 1);
        vm.prank(address(token));
        token.approve(address(_core), 1);
        vm.prank(_borrower);
        token.approve(address(_core), 100e9);
        token.setCallbackFrom(
            address(_core),
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 1, _borrower))
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
