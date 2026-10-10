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
    uint32 internal constant _DEFAULT_ATTEMPT_THRESHOLD = 250_000;
    uint32 internal constant _DEFAULT_CLEANUP_RESERVE = 100_000;

    // Scenarios: BLYC-CTOR-I01.
    function test_givenBurnerLoansIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(0)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(0), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CTOR-I03.
    function test_givenBurnerLoansDoesNotSupportYieldClaim_reverts() public {
        target.setSupportsYieldClaim(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(target), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CTOR-I04.
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

    // Scenarios: BLYC-CTOR-I07.
    function test_givenBurnerLoansDoesNotSupportLifecycle_reverts() public {
        target.setSupportsLifecycle(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        new BurnerLoansYieldClaimer(kernel, address(target), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CTOR-I05.
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

    // Scenarios: BLYC-CTOR-I06.
    function test_givenExecutionGasLimitIsZero_reverts() public {
        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        new BurnerLoansYieldClaimer(kernel, address(target), 0);
    }

    // Scenarios: BLYC-CTOR-P01.
    function test_givenValidConfiguration_whenDeployed(
        uint32 gasLimit_,
        bool targetActive_,
        bool targetEnabled_
    ) public {
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        _setTargetLifecycle(targetActive_, targetEnabled_);

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimer.ExecutionGasLimitSet(gasLimit_);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimer.MinimumGasToAttemptSet(_DEFAULT_ATTEMPT_THRESHOLD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimer.GasReserveSet(_DEFAULT_CLEANUP_RESERVE);

        BurnerLoansYieldClaimer deployed = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            gasLimit_
        );

        assertEq(deployed.burnerLoans(), address(target), "Burner Loans target");
        assertEq(deployed.executionGasLimit(), gasLimit_, "execution gas limit");
        assertEq(
            deployed.minimumGasToAttempt(),
            _DEFAULT_ATTEMPT_THRESHOLD,
            "default attempt threshold"
        );
        assertEq(deployed.gasReserve(), _DEFAULT_CLEANUP_RESERVE, "default cleanup reserve");
        assertEq(deployed.nextAssetIndex(), 0, "cursor starts at zero");
        assertEq(
            deployed.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "grace period"
        );
        assertEq(deployed.lastTransitionAt(), 0, "transition timestamp starts at zero");
        assertFalse(deployed.isEnabled(), "starts disabled");
    }

    // Scenarios: BLYC-CTOR-P01.
    function test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit() public {
        BurnerLoansYieldClaimer minimum = new BurnerLoansYieldClaimer(kernel, address(target), 1);
        BurnerLoansYieldClaimer maximum = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            type(uint32).max
        );

        assertEq(minimum.executionGasLimit(), 1, "minimum execution limit stored");
        assertEq(maximum.executionGasLimit(), type(uint32).max, "maximum execution limit stored");
    }

    // Scenarios: BLYC-CTOR-I02.
    function test_givenBurnerLoansIsEoa_reverts(address target_) public {
        vm.assume(target_ != address(0));
        vm.assume(target_.code.length == 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                target_
            )
        );
        new BurnerLoansYieldClaimer(kernel, target_, _EXECUTION_GAS_LIMIT);
    }
}
