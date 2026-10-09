// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockDisableTest is RevenueDistributorTest {
    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    // Scenarios: LC-P02, LC-L02
    function testFuzz_whenPermittedCallerDisables_recordsTransitionAndPreservesQueue(
        bool useAdmin_,
        bool active_,
        bytes calldata data_,
        uint48 timestamp_
    ) public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, routes);
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        }
        address caller = useAdmin_ ? admin : emergency;
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = uint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);

        vm.expectEmit(address(configTimelock));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(caller, false, data_, timestamp_);
        vm.prank(caller);
        configTimelock.disable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock disabled");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "transition timestamp");
        assertEq(configTimelock.getQueuedActionLength(actionId), 1, "queued action preserved");
    }

    // Scenarios: LC-I05
    function testFuzz_whenAlreadyDisabled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_
    ) public {
        vm.prank(emergency);
        configTimelock.disable("");
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-A03
    function testFuzz_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }
}
