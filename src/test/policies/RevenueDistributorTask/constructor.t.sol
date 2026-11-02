// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";

import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {RevenueDistributorTest} from "../RevenueDistributor/RevenueDistributorTest.sol";
import {MockTaskDistributorTarget} from "./fixtures/MockTaskDistributorTarget.sol";

contract RevenueDistributorTaskConstructorTest is RevenueDistributorTest {
    // Scenarios: RDTASK-CTOR-P01, RDTASK-CTOR-P02.
    function test_whenDistributorIsCompatible_initializesDefaults(
        uint32 gasLimit_,
        bool distributorEnabled_
    ) public {
        // bound() keeps the result inside uint32's nonzero interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        gasLimit_ = uint32(bound(gasLimit_, 1, type(uint32).max));
        if (!distributorEnabled_) {
            vm.prank(emergency);
            distributor.disable("");
        }

        RevenueDistributorTask deployed = new RevenueDistributorTask(
            kernel,
            address(distributor),
            gasLimit_
        );

        assertEq(deployed.distributor(), address(distributor), "distributor equals input");
        assertEq(deployed.executionGasLimit(), gasLimit_, "execution limit equals input");
        assertEq(deployed.minimumGasToAttempt(), 250_000, "default attempt threshold");
        assertEq(deployed.gasReserve(), 100_000, "default cleanup reserve");
        assertEq(deployed.nextAssetIndex(), 0, "cursor starts at zero");
        assertFalse(deployed.isEnabled(), "task starts disabled");
        assertEq(deployed.gracePeriod(), 7 days, "default grace period");
        assertEq(deployed.lastTransitionAt(), 0, "transition timestamp starts at zero");
    }

    // Scenarios: RDTASK-CTOR-I01.
    function test_whenDistributorIsZero_reverts() public {
        _expectInvalidDistributor(address(0));
        new RevenueDistributorTask(kernel, address(0), 1);
    }

    // Scenarios: RDTASK-CTOR-I02.
    function test_whenDistributorIsEoa_reverts(address target_) public {
        vm.assume(target_.code.length == 0);
        vm.assume(target_ != address(0));

        _expectInvalidDistributor(target_);
        new RevenueDistributorTask(kernel, target_, 1);
    }

    // Scenarios: RDTASK-CTOR-I03, RDTASK-CTOR-I07.
    function test_whenDistributorInterfaceIsMissing_reverts(
        bool supportsEnabler_,
        bool distributorEnabled_
    ) public {
        MockTaskDistributorTarget target = new MockTaskDistributorTarget(
            kernel,
            false,
            supportsEnabler_
        );
        target.setEnabled(distributorEnabled_);

        _expectInvalidDistributor(address(target));
        new RevenueDistributorTask(kernel, address(target), 1);
    }

    // Scenarios: RDTASK-CTOR-P01, RDTASK-CTOR-P02.
    function test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit() public {
        RevenueDistributorTask minimum = new RevenueDistributorTask(
            kernel,
            address(distributor),
            1
        );
        RevenueDistributorTask maximum = new RevenueDistributorTask(
            kernel,
            address(distributor),
            type(uint32).max
        );

        assertEq(minimum.executionGasLimit(), 1, "minimum execution limit stored");
        assertEq(maximum.executionGasLimit(), type(uint32).max, "maximum execution limit stored");
    }

    // Scenarios: RDTASK-CTOR-I06.
    function test_whenEnablerInterfaceIsMissing_reverts() public {
        MockTaskDistributorTarget target = new MockTaskDistributorTarget(kernel, true, false);

        _expectInvalidDistributor(address(target));
        new RevenueDistributorTask(kernel, address(target), 1);
    }

    // Scenarios: RDTASK-CTOR-I04, RDTASK-CTOR-I08.
    function test_whenDistributorUsesDifferentKernel_reverts(bool distributorEnabled_) public {
        Kernel otherKernel = new Kernel();
        MockTaskDistributorTarget target = new MockTaskDistributorTarget(otherKernel, true, true);
        target.setEnabled(distributorEnabled_);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(target),
                address(kernel),
                address(otherKernel)
            )
        );
        new RevenueDistributorTask(kernel, address(target), 1);
    }

    // Scenarios: RDTASK-CTOR-I05, RDTASK-CTOR-I09.
    function test_whenExecutionGasLimitIsZero_reverts(bool distributorEnabled_) public {
        if (!distributorEnabled_) {
            vm.prank(emergency);
            distributor.disable("");
        }

        vm.expectRevert(
            IRevenueDistributorTask.RevenueDistributorTask_InvalidExecutionGasLimit.selector
        );
        new RevenueDistributorTask(kernel, address(distributor), 0);
    }

    function _expectInvalidDistributor(address target_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_InvalidDistributor.selector,
                target_
            )
        );
    }

    // Scenarios: RDTASK-CTOR-D01.
    function test_whenDistributorKernelReadIsMalformed_reverts(bytes memory output_) public {
        if (output_.length == 32) vm.assume(abi.decode(output_, (uint256)) > type(uint160).max);
        vm.mockCall(address(distributor), abi.encodeWithSignature("kernel()"), output_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(distributor)
            )
        );
        new RevenueDistributorTask(kernel, address(distributor), 5_000_000);
    }

    // Scenarios: RDTASK-CTOR-D02.
    function test_whenDistributorEnabledReadIsMalformed_reverts(bytes memory output_) public {
        if (output_.length == 32) vm.assume(abi.decode(output_, (uint256)) > 1);
        vm.mockCall(address(distributor), abi.encodeWithSignature("isEnabled()"), output_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(distributor)
            )
        );
        new RevenueDistributorTask(kernel, address(distributor), 5_000_000);
    }

    // Scenarios: RDTASK-CTOR-D01, RDTASK-CTOR-D02.
    function test_whenDistributorMetadataBoundaries_reverts() public {
        test_whenDistributorKernelReadIsMalformed_reverts(hex"");
        test_whenDistributorKernelReadIsMalformed_reverts(hex"00");
        test_whenDistributorKernelReadIsMalformed_reverts(abi.encode(type(uint256).max));
        test_whenDistributorKernelReadIsMalformed_reverts(new bytes(64));
        vm.clearMockedCalls();
        test_whenDistributorEnabledReadIsMalformed_reverts(hex"");
        test_whenDistributorEnabledReadIsMalformed_reverts(hex"00");
        test_whenDistributorEnabledReadIsMalformed_reverts(abi.encode(uint256(2)));
        test_whenDistributorEnabledReadIsMalformed_reverts(new bytes(64));
    }

    // Scenarios: RDTASK-CTOR-D03.
    function test_whenDistributorMetadataReverts_reverts(bool kernelRead_) public {
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature(kernelRead_ ? "kernel()" : "isEnabled()"),
            abi.encodeWithSignature("MetadataFailed()")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(distributor)
            )
        );
        new RevenueDistributorTask(kernel, address(distributor), 5_000_000);
    }

    // Scenarios: RDTASK-CTOR-I03, RDTASK-CTOR-I04, RDTASK-CTOR-I05, RDTASK-CTOR-I07, RDTASK-CTOR-I08, RDTASK-CTOR-I09, RDTASK-CTOR-P01, RDTASK-CTOR-P02.
    function test_givenConstructorStateAndLimitSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenDistributorIsCompatible_initializesDefaults(1, false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorIsCompatible_initializesDefaults(type(uint32).max, false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorInterfaceIsMissing_reverts(false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorInterfaceIsMissing_reverts(true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorUsesDifferentKernel_reverts(false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenExecutionGasLimitIsZero_reverts(false);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorIsCompatible_initializesDefaults(1, true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorIsCompatible_initializesDefaults(type(uint32).max, true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorInterfaceIsMissing_reverts(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorInterfaceIsMissing_reverts(true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenDistributorUsesDifferentKernel_reverts(true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
        test_whenExecutionGasLimitIsZero_reverts(true);
        assertTrue(vm.revertToState(checkpoint), "Restore constructor seed");
    }
}
