// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";

import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {RevenueDistributorTest} from "../RevenueDistributor/RevenueDistributorTest.sol";
import {MockTaskDistributorTarget} from "./fixtures/MockTaskDistributorTarget.sol";

contract RevenueDistributorTaskConstructorTest is RevenueDistributorTest {
    // Scenarios: RDTASK-CTOR-P01.
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

    // Scenarios: RDTASK-CTOR-I03.
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

    // Scenarios: RDTASK-CTOR-P01.
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

    // Scenarios: RDTASK-CTOR-I04.
    function test_whenDistributorUsesDifferentKernel_reverts(bool distributorEnabled_) public {
        Kernel otherKernel = new Kernel();
        MockTaskDistributorTarget target = new MockTaskDistributorTarget(otherKernel, true, true);
        target.setEnabled(distributorEnabled_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_KernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new RevenueDistributorTask(kernel, address(target), 1);
    }

    // Scenarios: RDTASK-CTOR-I05.
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
}
