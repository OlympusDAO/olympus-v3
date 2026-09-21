// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

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

    function test_givenBurnerLoansDoesNotSupportAssetView_reverts() public {
        target.setSupportsAssetView(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(target), _EXECUTION_GAS_LIMIT);
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

    function test_givenValidConfiguration_whenDeployed() public {
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimer.ExecutionGasLimitSet(_EXECUTION_GAS_LIMIT);

        BurnerLoansYieldClaimer deployed = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            _EXECUTION_GAS_LIMIT
        );

        assertEq(deployed.burnerLoans(), address(target), "Burner Loans target");
        assertEq(deployed.executionGasLimit(), _EXECUTION_GAS_LIMIT, "execution gas limit");
        assertEq(
            deployed.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "grace period"
        );
        assertFalse(deployed.isEnabled(), "starts disabled");
    }
}
