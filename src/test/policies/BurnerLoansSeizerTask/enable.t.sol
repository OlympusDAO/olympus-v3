// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansSeizerTaskEnableTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-ENABLE-D08.
    function test_givenKernelDrift_whenEnabled_reverts(address otherKernel_) public {
        vm.assume(otherKernel_ != address(_kernel));
        _task.disable("");
        vm.mockCall(
            address(_liquidation),
            abi.encodeCall(_liquidation.kernel, ()),
            abi.encode(otherKernel_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_liquidation),
                address(_kernel),
                otherKernel_
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Kernel mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Kernel identity permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D09.
    function test_givenLensCoreDrift_whenEnabled_reverts(address otherCore_) public {
        vm.assume(otherCore_ != address(_core));
        _task.disable("");
        vm.mockCall(
            address(_lens),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(otherCore_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidLens.selector,
                address(_lens)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Lens mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Lens binding permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D02, BLSEIZ-ENABLE-D05, BLSEIZ-ENABLE-D06.
    function test_givenSeizeInactiveOrDisabled_whenEnabled_reverts(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _task.disable("");
        if (!enabled_) _liquidation.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_liquidation)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Unavailable Seize preserves disabled state");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        if (!enabled_) _liquidation.enable("");
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Seize permits retry");
    }

    function test_givenSeizeReady_whenAdminEnables() public {
        _task.disable("");
        _task.enable("");
        assertTrue(_task.isEnabled(), "Ready Seize permits enable");
    }

    function test_givenCoreMetadataUnreadable_whenEnabled_succeeds() public {
        _task.disable("");
        bytes memory kernelRead = abi.encodeCall(_core.kernel, ());
        bytes memory interfaceRead = abi.encodeWithSignature("supportsInterface(bytes4)");
        vm.mockCallRevert(address(_core), kernelRead, hex"aabbccdd");
        vm.mockCallRevert(address(_core), interfaceRead, hex"aabbccdd");
        vm.expectCall(address(_core), kernelRead, uint64(0));
        vm.expectCall(address(_core), interfaceRead, uint64(0));
        _task.enable("");
        assertTrue(
            _task.isEnabled(),
            "Activation validates Seize without repeating its Core admission"
        );
    }
}
