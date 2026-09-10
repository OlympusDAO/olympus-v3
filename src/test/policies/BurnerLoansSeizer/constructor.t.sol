// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";
import {MockBurnerLoansSeizerTarget} from "./MockBurnerLoansSeizerTarget.sol";

contract BurnerLoansSeizerConstructorTest is BurnerLoansSeizerTest {
    // constructor
    // given valid parameters
    //  when the seizer is deployed
    //   then it stores its immutable target and initial scan state
    //   then it emits the initial mutable configuration
    function test_givenValidParameters_whenDeployed() public {
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansSeizer.ScanLimitsSet(10, 5);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansSeizer.ExecutionGasLimitSet(_EXECUTION_GAS_LIMIT);

        BurnerLoansSeizer deployed = new BurnerLoansSeizer(
            kernel,
            address(target),
            10,
            5,
            _EXECUTION_GAS_LIMIT
        );

        assertEq(deployed.burnerLoans(), address(target), "burner loans");
        assertEq(deployed.maxBorrowersToCheck(), 10, "borrowers to check");
        assertEq(deployed.maxBorrowersToSeize(), 5, "borrowers to seize");
        assertEq(deployed.executionGasLimit(), _EXECUTION_GAS_LIMIT, "execution gas limit");
        assertEq(deployed.nextAssetIndex(), 0, "next asset index");
        assertEq(deployed.getAssets().length, 0, "managed assets");
    }

    // constructor
    // given zero burner loans
    //  when constructor is called
    //   then it reverts
    function test_givenZeroBurnerLoans_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_ZeroAddress.selector);
        new BurnerLoansSeizer(kernel, address(0), 10, 5, _EXECUTION_GAS_LIMIT);
    }

    // constructor
    // given invalid initial limits
    //  when constructor is called
    //   then it reverts
    function test_givenInvalidInitialLimits_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidScanLimits.selector,
                4,
                5
            )
        );
        new BurnerLoansSeizer(kernel, address(target), 4, 5, _EXECUTION_GAS_LIMIT);
    }

    // constructor
    // given the Burner Loans target does not expose the required interfaces
    //  when the seizer is deployed
    //   then it reverts
    function test_givenInvalidBurnerLoansTarget_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidBurnerLoans.selector,
                assetOne
            )
        );
        new BurnerLoansSeizer(kernel, assetOne, 10, 5, _EXECUTION_GAS_LIMIT);
    }

    // constructor
    // given the Burner Loans target belongs to a different Kernel
    //  when the seizer is deployed
    //   then it reverts
    function test_givenBurnerLoansTargetHasDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockBurnerLoansSeizerTarget otherTarget = new MockBurnerLoansSeizerTarget(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_KernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new BurnerLoansSeizer(kernel, address(otherTarget), 10, 5, _EXECUTION_GAS_LIMIT);
    }

    // constructor
    // given a zero execution gas limit
    //  when the seizer is deployed
    //   then it reverts
    function test_givenZeroExecutionGasLimit_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_InvalidExecutionGasLimit.selector);
        new BurnerLoansSeizer(kernel, address(target), 10, 5, 0);
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
