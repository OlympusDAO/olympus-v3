// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";

import {BurnerLoansCompositesTest} from "./BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesConstructorTest is BurnerLoansCompositesTest {
    function test_givenInvalidBurnerLoansTarget_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansComposites.BurnerLoansComposites_InvalidBurnerLoans.selector,
                address(usds)
            )
        );
        new BurnerLoansComposites(address(usds), address(ohm));
    }

    function test_givenDifferentOhm_reverts() public {
        MockERC20 otherOhm = new MockERC20("Other OHM", "oOHM", 9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansComposites.BurnerLoansComposites_OhmMismatch.selector,
                address(ohm),
                address(otherOhm)
            )
        );
        new BurnerLoansComposites(address(burnerLoans), address(otherOhm));
    }
}
