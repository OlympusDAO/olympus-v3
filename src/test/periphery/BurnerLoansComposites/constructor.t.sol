// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./BurnerLoansCompositesTest.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCompositesConstructorTest is BurnerLoansCompositesTest {
    function test_givenInvalidBurnerLoansTarget_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansComposites.BurnerLoansComposites_InvalidBurnerLoans.selector,
                address(_asset)
            )
        );
        new BurnerLoansComposites(address(_asset), address(_ohm), _collateral, _debt);
    }

    function test_givenDifferentOhm_reverts() public {
        MockERC20 otherOhm = new MockERC20("Other OHM", "oOHM", 9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansComposites.BurnerLoansComposites_OhmMismatch.selector,
                address(_ohm),
                address(otherOhm)
            )
        );
        new BurnerLoansComposites(address(_core), address(otherOhm), _collateral, _debt);
    }
}
