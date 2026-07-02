// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansConstructorTest is BurnerLoansTest {
    function test_constructor_givenOhmIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(kernel, IERC20(address(0)), depositManager);
    }

    function test_constructor_givenDepositManagerIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(kernel, IERC20(address(ohm)), IDepositManager(address(0)));
    }

    function test_constructor_givenDepositManagerDoesNotSupportInterface_reverts() public {
        MockInvalidDepositManager invalidDepositManager = new MockInvalidDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(invalidDepositManager)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(invalidDepositManager))
        );
    }

    function test_constructor_givenValidParams_setsImmutableDependencies() public view {
        assertEq(burnerLoans.ohm(), address(ohm), "ohm");
        assertEq(burnerLoans.depositManager(), address(depositManager), "deposit manager");
    }
}

contract MockInvalidDepositManager is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
