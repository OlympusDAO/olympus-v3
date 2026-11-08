// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryModularTest} from "./fixtures/BurnerLoansInventoryModularTest.sol";

import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract BurnerLoansInventorySetConfigOperatorIntegrationTest is BurnerLoansInventoryModularTest {
    // Scenarios: BLINV-CONFIGURATOR-D01.
    function test_givenCoreControllerReplaced_whenInventoryOperatorRead_thenUnchanged() public {
        address replacement = _replaceCoreController();
        assertEq(
            _inventory.configOperator(),
            _inventoryConfigurator,
            "Inventory recovery selection unchanged"
        );
        _expectNotAuthorised();
        vm.prank(replacement);
        _inventory.rescueSurplus();
    }

    // Scenarios: BLINV-CONFIGURATOR-C03.
    function test_givenFeeReceiptCallback_whenOperatorRejectionCaught_succeeds() public {
        ReentrantFeeToken token = _prepareFeeReceiptCallback();
        token.setCallbackFrom(
            address(_core),
            address(_inventory),
            abi.encodeCall(_inventory.setConfigOperator, (address(token)))
        );
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        _assertCoreCallbackCaught(token);
    }

    // Scenarios: BLINV-CONFIGURATOR-C03.
    function test_givenFeeReceiptCallback_whenOperatorRejectionPropagates_reverts() public {
        ReentrantFeeToken token = _prepareFeeReceiptCallback();
        token.setCallbackFrom(
            address(_core),
            address(_inventory),
            abi.encodeCall(_inventory.setConfigOperator, (address(token)))
        );
        token.setBubbleCallbackFailure(true);
        uint256 payerBalance = token.balanceOf(_borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 7, address(0));
        _assertCoreCallbackRolledBack(token, payerBalance);
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
