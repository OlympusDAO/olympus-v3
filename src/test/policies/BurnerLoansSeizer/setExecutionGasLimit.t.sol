// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract BurnerLoansSeizerSetExecutionGasLimitTest is BurnerLoansSeizerTest {
    uint32 internal constant _ADMIN_GAS_LIMIT = 8_000_000;
    uint32 internal constant _BURNER_LOANS_ADMIN_GAS_LIMIT = 9_000_000;

    function test_givenAdminOrBurnerLoansAdmin_setsExecutionGasLimit() public {
        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ExecutionGasLimitSet(_ADMIN_GAS_LIMIT);
        vm.prank(admin);
        seizer.setExecutionGasLimit(_ADMIN_GAS_LIMIT);
        assertEq(seizer.executionGasLimit(), _ADMIN_GAS_LIMIT, "admin gas limit");

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ExecutionGasLimitSet(_BURNER_LOANS_ADMIN_GAS_LIMIT);
        vm.prank(burnerLoansAdmin);
        seizer.setExecutionGasLimit(_BURNER_LOANS_ADMIN_GAS_LIMIT);
        assertEq(
            seizer.executionGasLimit(),
            _BURNER_LOANS_ADMIN_GAS_LIMIT,
            "Burner Loans admin gas limit"
        );
    }

    function test_givenZeroExecutionGasLimit_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_InvalidExecutionGasLimit.selector);
        vm.prank(admin);
        seizer.setExecutionGasLimit(0);
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        seizer.setExecutionGasLimit(_ADMIN_GAS_LIMIT);
    }

    function test_whenExecutionGasLimitIsValid(uint32 executionGasLimit_) public {
        uint32 executionGasLimit = uint32(bound(executionGasLimit_, 1, type(uint32).max));

        vm.prank(admin);
        seizer.setExecutionGasLimit(executionGasLimit);

        assertEq(seizer.executionGasLimit(), executionGasLimit, "valid execution gas limit");
    }

    function test_whenExecutionGasLimitIsOne_setsMinimum() public {
        vm.prank(admin);
        seizer.setExecutionGasLimit(1);

        assertEq(seizer.executionGasLimit(), 1, "minimum execution gas limit");
    }

    function test_whenExecutionGasLimitIsUint32Max_setsMaximum() public {
        vm.prank(admin);
        seizer.setExecutionGasLimit(type(uint32).max);

        assertEq(seizer.executionGasLimit(), type(uint32).max, "maximum execution gas limit");
    }

    function test_givenDisabled_setsExecutionGasLimit() public {
        vm.prank(admin);
        seizer.disable("");

        vm.prank(burnerLoansAdmin);
        seizer.setExecutionGasLimit(_ADMIN_GAS_LIMIT);

        assertEq(seizer.executionGasLimit(), _ADMIN_GAS_LIMIT, "disabled execution gas limit");
    }
}

// forge-lint: disable-end(unsafe-typecast)
