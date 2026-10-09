// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract BurnerLoansYieldClaimerSetExecutionGasLimitTest is BurnerLoansYieldClaimerTest {
    uint32 internal constant _UPDATED_EXECUTION_GAS_LIMIT = 500_000;

    function test_givenAdmin_setsLimit() public {
        vm.prank(admin);
        claimer.setExecutionGasLimit(_UPDATED_EXECUTION_GAS_LIMIT);

        assertEq(claimer.executionGasLimit(), _UPDATED_EXECUTION_GAS_LIMIT, "execution gas limit");
    }

    function test_givenBurnerLoansAdmin_setsLimit() public {
        vm.prank(burnerLoansAdmin);
        claimer.setExecutionGasLimit(_UPDATED_EXECUTION_GAS_LIMIT);

        assertEq(claimer.executionGasLimit(), _UPDATED_EXECUTION_GAS_LIMIT, "execution gas limit");
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        claimer.setExecutionGasLimit(_UPDATED_EXECUTION_GAS_LIMIT);
    }

    function test_givenZeroLimit_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        claimer.setExecutionGasLimit(0);
    }

    function test_whenLimitIsValid_setsLimit(uint32 gasLimit_) public {
        gasLimit_ = uint32(bound(gasLimit_, 1, type(uint32).max));

        vm.prank(admin);
        claimer.setExecutionGasLimit(gasLimit_);

        assertEq(claimer.executionGasLimit(), gasLimit_, "execution gas limit");
    }
}

// forge-lint: disable-end(unsafe-typecast)
