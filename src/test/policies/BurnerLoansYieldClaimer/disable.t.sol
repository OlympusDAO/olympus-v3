// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerDisableTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-DISABLE-P01, BLYC-DISABLE-P02.
    function test_whenPermittedCallerDisables_preservesConfiguration(
        bool adminCalls_,
        bool taskActive_,
        bool targetActive_,
        bytes calldata data_
    ) public {
        address caller = adminCalls_ ? admin : _emergency;
        address[] memory assets = new address[](2);
        assets[0] = address(0xA11CE);
        assets[1] = address(0xB0B);
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        _setClaimerLifecycle(taskActive_, true);
        _setTargetLifecycle(targetActive_, true);
        uint32 executionLimit = claimer.executionGasLimit();
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserve = claimer.gasReserve();
        uint256 cursor = claimer.nextAssetIndex();
        uint48 transitionTime = 2 days;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(claimer));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(claimer));
        emit IEnablerV2.Transition(caller, false, data_, transitionTime);
        vm.prank(caller);
        claimer.disable(data_);

        assertFalse(claimer.isEnabled(), "permitted caller disables claimer");
        assertEq(claimer.lastTransitionAt(), transitionTime, "disable records timestamp");
        assertEq(claimer.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(claimer.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(claimer.gasReserve(), reserve, "reserve preserved");
        assertEq(claimer.nextAssetIndex(), cursor, "cursor preserved");
    }

    // Scenarios: BLYC-DISABLE-A01.
    function test_givenEnabled_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        bytes calldata data_,
        bool taskActive_,
        bool targetActive_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != _emergency);
        _setClaimerLifecycle(taskActive_, true);
        _setTargetLifecycle(targetActive_, true);
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.disable(data_);

        assertTrue(claimer.isEnabled(), "claimer remains enabled");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: BLYC-DISABLE-I01.
    function test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_,
        bool taskActive_,
        bool targetActive_
    ) public {
        vm.prank(_emergency);
        claimer.disable("");
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        _setTargetLifecycle(targetActive_, true);
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        claimer.disable(data_);

        assertFalse(claimer.isEnabled(), "claimer remains disabled");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }
}
