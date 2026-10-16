// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockEnableTest is RevenueDistributorTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    // Scenarios: LC-P01, LC-L02
    function testFuzz_whenAdminEnablesDisabledPolicy_recordsTransition(
        bytes calldata data_,
        bool active_,
        uint48 timestamp_
    ) public {
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = uint48(bound(timestamp_, 1, type(uint48).max));
        vm.prank(emergency);
        configTimelock.disable("prior disable");
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        }
        uint64 nextActionId = configTimelock.nextActionId();
        vm.warp(timestamp_);

        vm.expectEmit(address(configTimelock));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(admin, true, data_, timestamp_);
        vm.prank(admin);
        configTimelock.enable(data_);

        assertTrue(configTimelock.isEnabled(), "timelock enabled");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "transition timestamp");
        assertEq(configTimelock.nextActionId(), nextActionId, "queue state preserved");
    }

    // Scenarios: LC-I01
    function testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_
    ) public {
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.enable(data_);

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-A01
    function testFuzz_whenNonAdminEnables_reverts(address caller_, bytes calldata data_) public {
        vm.assume(caller_ != admin);
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        configTimelock.enable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-I04
    function testFuzz_whenDistributorKernelMismatches_reverts(
        bool active_,
        bytes calldata data_
    ) public {
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 transitionAt = configTimelock.lastTransitionAt();
        Kernel otherKernel = new Kernel();
        vm.prank(address(kernel));
        distributor.changeKernel(otherKernel);
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidDistributor
                    .selector,
                address(distributor)
            )
        );
        vm.prank(admin);
        configTimelock.enable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-P01
    function test_whenNeverEnabled_adminCanEnable() public {
        RevenueDistributorConfigTimelock freshTimelock = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(freshTimelock));

        vm.prank(admin);
        freshTimelock.enable("");

        assertTrue(freshTimelock.isEnabled(), "fresh timelock enabled");
        assertEq(freshTimelock.lastTransitionAt(), block.timestamp, "transition recorded");
    }
}
