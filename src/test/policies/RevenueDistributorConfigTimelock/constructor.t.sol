// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {MockRevenueDistributorTarget} from "./fixtures/MockRevenueDistributorTarget.sol";
import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockConstructorTest is RevenueDistributorTest {
    // Scenarios: RDCT-CTOR-P01.
    function test_whenConstructedWithValidTarget_setsTargetAndDefaults() public {
        RevenueDistributorConfigTimelock timelock = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );

        assertEq(timelock.distributor(), address(distributor), "distributor target");
        assertFalse(timelock.isEnabled(), "initially disabled");
        assertEq(timelock.lastTransitionAt(), 0, "no transition recorded");
        assertEq(timelock.gracePeriod(), 7 days, "default grace period");
        assertEq(timelock.timelockDelay(), 1 days, "default timelock delay");
        assertEq(timelock.nextActionId(), 1, "first action ID");
        assertEq(timelock.EXECUTION_WINDOW(), 3 days, "execution window");
        assertEq(timelock.maxConfigKeysPerBatch(), 15, "maximum batch keys");
    }

    // Scenarios: RDCT-CTOR-I01.
    function test_whenConstructedWithZeroTarget_reverts() public {
        _expectInvalidTarget(address(0));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(0)));
    }

    // Scenarios: RDCT-CTOR-I02.
    function test_whenConstructedWithEoaTarget_reverts() public {
        address target = makeAddr("non-contract distributor");

        _expectInvalidTarget(target);
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(target));
    }

    // Scenarios: RDCT-CTOR-I03.
    function test_whenTargetLacksRevenueDistributorInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            false,
            true,
            true,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I04.
    function test_whenTargetLacksRescueInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            false,
            true,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I05.
    function test_whenTargetLacksConfigOperatorInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            true,
            false,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I06.
    function test_whenTargetLacksEnablerInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            true,
            true,
            false
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I07.
    function test_whenTargetUsesDifferentKernel_reverts() public {
        Kernel targetKernel = new Kernel();
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            targetKernel,
            true,
            true,
            true,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(target),
                address(kernel),
                address(targetKernel)
            )
        );
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    function _expectInvalidTarget(address target_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidDistributor
                    .selector,
                target_
            )
        );
    }

    // Scenarios: RDCT-CTOR-D01.
    function test_whenDistributorKernelReadIsMalformed_reverts(bytes memory output_) public {
        if (output_.length == 32) vm.assume(abi.decode(output_, (uint256)) > type(uint160).max);
        vm.mockCall(address(distributor), abi.encodeWithSignature("kernel()"), output_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(distributor)
            )
        );
        new RevenueDistributorConfigTimelock(kernel, distributor);
    }

    // Scenarios: RDCT-CTOR-D02.
    function test_whenDistributorEnabledReadIsMalformed_thenConstructed(
        bytes memory output_
    ) public {
        vm.mockCall(address(distributor), abi.encodeWithSignature("isEnabled()"), output_);
        RevenueDistributorConfigTimelock fresh = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        assertEq(
            fresh.distributor(),
            address(distributor),
            "Construction does not read enabled status"
        );
        assertFalse(fresh.isEnabled(), "New queue disabled");
    }

    // Scenarios: RDCT-CTOR-D01.
    function test_whenDistributorMetadataBoundaries_reverts() public {
        test_whenDistributorKernelReadIsMalformed_reverts(hex"");
        test_whenDistributorKernelReadIsMalformed_reverts(hex"00");
        test_whenDistributorKernelReadIsMalformed_reverts(abi.encode(type(uint256).max));
        test_whenDistributorKernelReadIsMalformed_reverts(new bytes(64));
        vm.clearMockedCalls();
    }

    // Scenarios: RDCT-CTOR-D03.
    function test_whenDistributorMetadataReverts_reverts() public {
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("MetadataFailed()")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(distributor)
            )
        );
        new RevenueDistributorConfigTimelock(kernel, distributor);
    }

    // Scenarios: RDCT-CTOR-D02.
    function test_whenEnabledMetadataBoundarySeeds_thenConstructed() public {
        test_whenDistributorEnabledReadIsMalformed_thenConstructed(hex"");
        test_whenDistributorEnabledReadIsMalformed_thenConstructed(hex"00");
        test_whenDistributorEnabledReadIsMalformed_thenConstructed(abi.encode(uint256(2)));
        test_whenDistributorEnabledReadIsMalformed_thenConstructed(new bytes(64));
    }

    // Scenarios: RDCT-CTOR-P02.
    function test_givenRuntimeReadinessGettersRevert_whenConstructed(address deployer_) public {
        vm.mockCallRevert(address(distributor), abi.encodeWithSignature("isEnabled()"), hex"ff");
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("configOperator()"),
            hex"ff"
        );
        vm.mockCallRevert(
            address(kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(distributor)),
            hex"ff"
        );
        vm.prank(deployer_);
        RevenueDistributorConfigTimelock fresh = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        assertEq(
            fresh.distributor(),
            address(distributor),
            "Compatible target bound without readiness reads"
        );
        assertFalse(fresh.isEnabled(), "Construction leaves queue disabled");
    }

    // Scenarios: RDCT-CTOR-P03.
    function test_givenAnyTargetLifecycle_whenConstructed(bool active_, bool enabled_) public {
        if (!enabled_) _disableDistributor();
        _setPolicyActive(address(distributor), active_);
        RevenueDistributorConfigTimelock fresh = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        assertEq(
            fresh.distributor(),
            address(distributor),
            "Construction permits every target lifecycle pair"
        );
        assertFalse(fresh.isEnabled(), "Queue disabled independently of target");
    }

    // Scenarios: RDCT-CTOR-P03.
    function test_givenTargetLifecycleSeeds_whenConstructed() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAnyTargetLifecycle_whenConstructed(true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore target lifecycle seed");
        test_givenAnyTargetLifecycle_whenConstructed(true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore target lifecycle seed");
        test_givenAnyTargetLifecycle_whenConstructed(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore target lifecycle seed");
        test_givenAnyTargetLifecycle_whenConstructed(false, false);
    }
}
