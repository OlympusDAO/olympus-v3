// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "../RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockReEnableTest is RevenueDistributorTest {
    uint48 internal constant DISABLED_AT = 1_000;

    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
    }

    // Scenarios: LC-P03
    function testFuzz_whenPermittedCallerReEnablesWithinGrace_recordsTransition(
        bool useAdmin_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = DISABLED_AT;
        // bound() guarantees that the result fits uint32.
        // forge-lint: disable-next-line(unsafe-typecast)
        elapsed_ = uint32(bound(elapsed_, 0, configTimelock.gracePeriod()));
        vm.warp(disabledAt);
        vm.prank(emergency);
        configTimelock.disable("");
        address caller = useAdmin_ ? admin : alice;
        vm.warp(uint256(disabledAt) + elapsed_);
        // The bounded disabledAt and elapsed values keep the timestamp within uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 transitionAt = uint48(block.timestamp);

        vm.expectEmit(address(configTimelock));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(caller, true, "", transitionAt);
        vm.prank(caller);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "timelock re-enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp");
    }

    // Scenarios: LC-P03
    function test_whenExactGraceDeadline_reenables() public {
        uint48 disabledAt = DISABLED_AT;
        vm.warp(disabledAt);
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 deadline = disabledAt + configTimelock.gracePeriod();
        vm.warp(deadline);

        vm.prank(alice);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "deadline remains inside grace period");
        assertEq(configTimelock.lastTransitionAt(), deadline, "deadline transition recorded");
    }

    // Scenarios: LC-I02
    function test_whenNeverEnabled_reverts() public {
        RevenueDistributorConfigTimelock freshTimelock = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(freshTimelock));

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        freshTimelock.reEnable();

        assertFalse(freshTimelock.isEnabled(), "fresh timelock remains disabled");
        assertEq(freshTimelock.lastTransitionAt(), 0, "timestamp remains zero");
    }

    // Scenarios: LC-A02
    function testFuzz_whenUnauthorizedCallerReEnables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != alice);
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-I06
    function testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization(address caller_) public {
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-I07
    function testFuzz_whenGracePeriodExpired_reverts(uint48 now_) public {
        uint48 disabledAt = DISABLED_AT;
        vm.warp(disabledAt);
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 deadline = disabledAt + configTimelock.gracePeriod();
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        now_ = uint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(alice);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), disabledAt, "timestamp unchanged");
    }

    // Scenarios: LC-L02
    function testFuzz_whenOwnPolicyInactive_permittedCallerCanReEnable(bool useAdmin_) public {
        vm.prank(emergency);
        configTimelock.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        address caller = useAdmin_ ? admin : alice;

        vm.prank(caller);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "inactive timelock re-enabled");
    }

    // Scenarios: LC-I04
    function testFuzz_whenDistributorKernelMismatches_reverts(bool active_, bool useAdmin_) public {
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
        vm.prank(useAdmin_ ? admin : alice);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }
}
