// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockLifecycleTest} from "./fixtures/DepositManagerConfigTimelockLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";

contract DepositManagerConfigTimelockReEnableTest is DepositManagerConfigTimelockLifecycleTest {
    // Scenarios: DMCT-REENABLE-A01, DMCT-REENABLE-L01.
    function test_givenPaused_whenAdminReEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        vm.assume(!_lifecycleRoles.hasRole(caller_, _lifecycleSecondaryRole));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DMCT-REENABLE-A01.
    function test_givenSecondaryOnly_whenReEnabled(address caller_) public givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantLifecycleRole(_lifecycleSecondaryRole, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DMCT-REENABLE-A01.
    function test_givenAdminAndSecondary_whenReEnabled(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _grantLifecycleRole(_lifecycleSecondaryRole, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DMCT-REENABLE-A01.
    function test_whenPermittedCallerSeedsReEnable() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _pause();
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-A02.
    function test_givenPaused_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _excludeReEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-A02.
    function test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts()
        public
        givenLifecycleDisabled
    {
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-L02.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(address caller_) public {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-L03.
    function test_givenInactivePaused_whenReEnabled_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: DMCT-REENABLE-L04.
    function test_givenInactiveEnabled_whenAnyCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-L05.
    function test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts(
        address caller_
    ) public {
        _freshSubject(true);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-L06.
    function test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts(
        address caller_
    ) public {
        _freshSubject(false);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-I01.
    function test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        _excludeReEnableCallers(caller_);
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-N01.
    function test_whenIndependentGraceAndTimeWithinWindow(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 elapsed_
    ) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        vm.warp(uint256(disabledAt) + bound(elapsed_, 0, grace));
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-REENABLE-N01.
    function test_givenSecondary_whenIndependentGraceAndTimeWithinWindow(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 elapsed_
    ) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        vm.warp(uint256(disabledAt) + bound(elapsed_, 0, grace));
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N02.
    function test_whenIndependentGraceAndTimeExpired_reverts(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace - 1)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        uint48 deadline = disabledAt + grace;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
    }

    // Scenarios: DMCT-REENABLE-N03.
    function test_whenImmediately() public {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(100 + 0);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N03.
    function test_whenOneBeforeDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 6);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N03.
    function test_whenAtDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 7);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N03.
    function test_whenAtMaximumGraceDeadline() public {
        _setGrace(4294967295);
        _pauseAt(100);
        vm.warp(100 + 4294967295);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N03.
    function test_whenDeadlineIsMaximumTimestamp() public {
        _setGrace(1);
        _pauseAt(type(uint48).max - 1);
        vm.warp(type(uint48).max);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-N04.
    function test_whenFirstTimestampAfterDeadline_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(102);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DMCT-REENABLE-N05.
    function test_whenDeadlineOverflows_reverts(uint32 grace_, uint48 disabledAt_) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace + 1, type(uint48).max)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt) + grace
            )
        );
    }

    // Scenarios: DMCT-REENABLE-N05.
    function test_whenMaximumTimestampMakesDeadlineOverflow_reverts() public {
        _setGrace(1);
        _pauseAt(type(uint48).max);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 1
            )
        );
    }

    // Scenarios: DMCT-REENABLE-I02.
    function test_givenInactive_whenGraceExpired_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        _setMembership(false);
        vm.warp(102);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DMCT-REENABLE-P01.
    function test_givenReactivated_whenReEnabled()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-P02.
    function test_whenRepeatedCyclesRestartGrace() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(107);
        _reEnableSucceeds(_lifecycleSecondary);
        _pauseAt(200);
        vm.warp(207);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: DMCT-REENABLE-D08.
    function test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-REENABLE-D09.
    function test_givenManagerActiveTrueEnabledFalse_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D10.
    function test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D11.
    function test_givenManagerActiveFalseEnabledFalse_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D01.
    function test_givenForeignKernelAndPausedManager_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBEEF))
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(depositManager),
                address(kernel),
                address(0xBEEF)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D02.
    function test_givenKernelReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D04.
    function test_givenStatusReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D03.
    function test_givenNoncanonicalKernel_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D03.
    function test_givenMalformedKernelLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(depositManager), abi.encodeWithSignature("kernel()"), data_);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D05.
    function test_givenNoncanonicalStatus_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D05.
    function test_givenMalformedStatusLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(depositManager), abi.encodeWithSignature("isEnabled()"), data_);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-REENABLE-D06.
    function test_givenDifferentConfigOperator_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-REENABLE-D07.
    function test_givenManagerReadinessRestored_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(ADMIN);
        depositManager.reEnable();
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-REENABLE-I08.
    function test_givenInactiveAndBrokenDependency_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        _setMembership(false);
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: DMCT-REENABLE-I03.
    function test_givenBrokenDependency_whenExpiredGrace_reverts() public givenLifecycleDisabled {
        uint48 deadline = IEnablerV2(_lifecycleTarget).lastTransitionAt() +
            IGracePeriod(_lifecycleTarget).gracePeriod();
        vm.warp(uint256(deadline) + 1);
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
    }

    // Scenarios: DMCT-REENABLE-N06.
    function test_givenZeroTransitionTimestamp_whenReEnabled_reverts() public {
        _pauseAt(0);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-N02.
    function test_whenMaximumTimestampIsExpired_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(type(uint48).max);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DMCT-REENABLE-L02.
    function test_givenEnabled_whenCallerSeedsReEnable_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-REENABLE-D12.
    function test_givenDepositManagerBecomesInactive_reEnableReverts() public {
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.stopPrank();
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
    }

    // Scenarios: DMCT-REENABLE-D13.
    function test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }
}
