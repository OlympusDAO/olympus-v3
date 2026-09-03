// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";
import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

contract BurnerLoansYieldClaimerConstructorTest is BurnerLoansYieldClaimerTest {
    function test_givenBurnerLoansIsZero_reverts() public {
        vm.expectRevert(IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_ZeroAddress.selector);
        new BurnerLoansYieldClaimer(kernel, address(0), _EXECUTION_GAS_LIMIT);
    }

    function test_givenBurnerLoansDoesNotSupportYieldClaim_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(this)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(this), _EXECUTION_GAS_LIMIT);
    }

    function test_givenBurnerLoansUsesDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockBurnerLoansYieldClaimerTarget otherTarget = new MockBurnerLoansYieldClaimerTarget(
            otherKernel
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_KernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(otherTarget), _EXECUTION_GAS_LIMIT);
    }

    function test_givenExecutionGasLimitIsZero_reverts() public {
        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        new BurnerLoansYieldClaimer(kernel, address(target), 0);
    }

    function test_givenValidConfiguration_setsImmutableTargetAndGasLimit() public {
        BurnerLoansYieldClaimer deployed = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            _EXECUTION_GAS_LIMIT
        );

        assertEq(deployed.burnerLoans(), address(target), "Burner Loans target");
        assertEq(deployed.executionGasLimit(), _EXECUTION_GAS_LIMIT, "execution gas limit");
    }
}
