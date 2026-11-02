// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

contract BurnerLoansSeizerTaskReEnableTest is BurnerLoansSeizerTaskTest {
    uint48 internal constant _DISABLED_AT = 1_000;

    function setUp() public override {
        super.setUp();
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _BOB);
    }

    function test_givenNeverEnabled_reverts() public {
        BurnerLoansSeizerTask fresh = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            _lens,
            10,
            5,
            _EXECUTION_GAS_LIMIT
        );

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        fresh.reEnable();
    }

    function test_givenAlreadyEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(_BOB);
        _task.reEnable();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _task.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _task.reEnable();
    }

    function test_givenGracePeriodElapsed_reverts(uint48 elapsedAfterDeadline_) public {
        uint256 elapsedAfterDeadline = bound(
            elapsedAfterDeadline_,
            1,
            type(uint48).max - (_DISABLED_AT + _GRACE_PERIOD)
        );
        vm.warp(_DISABLED_AT);
        _task.disable("");

        // deadline = disabled timestamp + the 7-day default grace period.
        uint48 deadline = _DISABLED_AT + _GRACE_PERIOD;
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(_BOB);
        _task.reEnable();
    }

    function test_givenBurnerLoansAdminWithinGracePeriod_reEnables(uint32 elapsed_) public {
        uint256 elapsed = bound(elapsed_, 0, _GRACE_PERIOD);
        vm.warp(_DISABLED_AT);
        _task.addAsset(address(_asset));
        _task.disable("");
        vm.warp(uint256(_DISABLED_AT) + elapsed);

        vm.prank(_BOB);
        _task.reEnable();

        assertTrue(_task.isEnabled(), "Seizer should be enabled");
        assertEq(uint256(_task.lastTransitionAt()), block.timestamp, "last transition");
        assertTrue(_task.isAssetManaged(address(_asset)), "managed assets should be preserved");
    }

    function test_givenAdminAtGracePeriodDeadline_reEnables() public {
        vm.warp(_DISABLED_AT);
        _task.disable("");
        vm.warp(uint256(_DISABLED_AT) + _GRACE_PERIOD);

        _task.reEnable();

        assertTrue(_task.isEnabled(), "Seizer should be enabled at the deadline");
    }

    // Scenarios: BLSEIZ-REENABLE-D08.
    function test_givenKernelDrift_whenReEnabled_reverts(address otherKernel_) public {
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
        _task.reEnable();
        assertFalse(_task.isEnabled(), "Kernel mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.reEnable();
        assertTrue(_task.isEnabled(), "Restoring Kernel identity permits retry");
    }

    // Scenarios: BLSEIZ-REENABLE-D09.
    function test_givenLensCoreDrift_whenReEnabled_reverts(address otherCore_) public {
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
        _task.reEnable();
        assertFalse(_task.isEnabled(), "Lens mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.reEnable();
        assertTrue(_task.isEnabled(), "Restoring Lens binding permits retry");
    }

    // Scenarios: BLSEIZ-REENABLE-D02, BLSEIZ-REENABLE-D05, BLSEIZ-REENABLE-D06.
    function test_givenSeizeInactiveOrDisabled_whenReEnabled_reverts(
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
        _task.reEnable();
        assertFalse(_task.isEnabled(), "Unavailable Seize preserves disabled state");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        if (!enabled_) _liquidation.enable("");
        _task.reEnable();
        assertTrue(_task.isEnabled(), "Restoring Seize permits retry");
    }

    function test_givenCoreMetadataUnreadable_whenReEnabled_succeeds() public {
        _task.disable("");
        bytes memory kernelRead = abi.encodeCall(_core.kernel, ());
        bytes memory interfaceRead = abi.encodeWithSignature("supportsInterface(bytes4)");
        vm.mockCallRevert(address(_core), kernelRead, hex"aabbccdd");
        vm.mockCallRevert(address(_core), interfaceRead, hex"aabbccdd");
        vm.expectCall(address(_core), kernelRead, uint64(0));
        vm.expectCall(address(_core), interfaceRead, uint64(0));
        _task.reEnable();
        assertTrue(
            _task.isEnabled(),
            "Activation validates Seize without repeating its Core admission"
        );
    }
}
