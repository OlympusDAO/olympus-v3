// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerSetExecutionGasLimitTest is BurnerLoansSeizerTest {
    function test_givenAdminOrBurnerLoansAdmin_setsExecutionGasLimit() public {
        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ExecutionGasLimitSet(8_000_000);
        vm.prank(admin);
        seizer.setExecutionGasLimit(8_000_000);
        assertEq(seizer.executionGasLimit(), 8_000_000, "admin gas limit");

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ExecutionGasLimitSet(9_000_000);
        vm.prank(burnerLoansAdmin);
        seizer.setExecutionGasLimit(9_000_000);
        assertEq(seizer.executionGasLimit(), 9_000_000, "Burner Loans admin gas limit");
    }

    function test_givenZeroExecutionGasLimit_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_InvalidExecutionGasLimit.selector);
        vm.prank(admin);
        seizer.setExecutionGasLimit(0);
    }

    function testFuzz_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        seizer.setExecutionGasLimit(8_000_000);
    }
}
