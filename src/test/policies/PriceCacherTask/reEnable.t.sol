// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";

contract PriceCacherTaskReEnableTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-REENABLE-A01, PCACHER-REENABLE-L01.
    function test_givenPaused_whenAdminReEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, PRICE_ADMIN_ROLE));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHER-REENABLE-A01, PCACHER-REENABLE-L01.
    function test_givenPaused_whenPriceAdminReEnables(
        address caller_
    ) public givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantLifecycleRole(PRICE_ADMIN_ROLE, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHER-REENABLE-A01, PCACHER-REENABLE-L01.
    function test_givenPaused_whenBothRolesReEnable(address caller_) public givenLifecycleDisabled {
        _grantLifecycleRole(ADMIN_ROLE, caller_);
        _grantLifecycleRole(PRICE_ADMIN_ROLE, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHER-REENABLE-A01.
    function test_whenPermittedCallerSeedsReEnable() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _pause();
        _reEnableSucceeds(_lifecycleSecondary);
        _pause();
        address overlap = makeAddr("adminAndPriceAdmin");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(PRICE_ADMIN_ROLE, overlap);
        _reEnableSucceeds(overlap);
    }

    // Scenarios: PCACHER-REENABLE-A02.
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

    // Scenarios: PCACHER-REENABLE-A02.
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

    // Scenarios: PCACHER-REENABLE-L02.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(address caller_) public {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHER-REENABLE-L03.
    function test_givenInactivePaused_whenReEnabled_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _activationRejected(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-L04.
    function test_givenInactiveEnabled_whenAnyCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHER-REENABLE-L05.
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

    // Scenarios: PCACHER-REENABLE-L06.
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

    // Scenarios: PCACHER-REENABLE-I01.
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

    // Scenarios: PCACHER-REENABLE-N01.
    function test_whenIndependentGraceAndTimeWithinWindow(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 elapsed_
    ) public {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace));
        _setGrace(grace);
        _pauseAt(disabledAt);
        vm.warp(uint256(disabledAt) + bound(elapsed_, 0, grace));
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-REENABLE-N02.
    function test_whenIndependentGraceAndTimeExpired_reverts(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace - 1));
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

    // Scenarios: PCACHER-REENABLE-N03.
    function test_whenImmediately() public {
        _setGrace(1);
        _pauseAt(100);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-N03.
    function test_whenOneBeforeDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 6);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-N03.
    function test_whenAtDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 7);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-N03.
    function test_whenAtMaximumGraceDeadline() public {
        _setGrace(type(uint32).max);
        _pauseAt(100);
        vm.warp(100 + uint256(type(uint32).max));
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-N03.
    function test_whenDeadlineIsMaximumTimestamp() public {
        _setGrace(1);
        _pauseAt(type(uint48).max - 1);
        vm.warp(type(uint48).max);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-N04.
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

    // Scenarios: PCACHER-REENABLE-N05.
    function test_whenDeadlineOverflows_reverts(uint32 grace_, uint48 disabledAt_) public {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
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

    // Scenarios: PCACHER-REENABLE-N05.
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

    // Scenarios: PCACHER-REENABLE-I02.
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

    // Scenarios: PCACHER-REENABLE-P01.
    function test_givenReactivated_whenReEnabled()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-P02.
    function test_whenRepeatedCyclesRestartGrace() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(107);
        _reEnableSucceeds(_lifecycleSecondary);
        _pauseAt(200);
        vm.warp(207);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHER-REENABLE-D01.
    function test_givenMissingPriceCacheInterface_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        priceCache.setInterfaceSupport(false, true, true);
        _activationRejected(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_InvalidPriceCache.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D02.
    function test_givenMissingEnablerInterface_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        priceCache.setInterfaceSupport(true, false, true);
        _activationRejected(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_InvalidPriceCache.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D05.
    function test_givenForeignKernelAndPausedCache_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        priceCache.disable("");
        vm.mockCall(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBEEF))
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(priceCache),
                address(kernel),
                address(0xBEEF)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D08.
    function test_givenKernelReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D10.
    function test_givenStatusReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D09.
    function test_givenNoncanonicalKernel_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D09.
    function test_givenMalformedKernelLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(priceCache), abi.encodeWithSignature("kernel()"), data_);
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D11.
    function test_givenNoncanonicalStatus_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(priceCache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D11.
    function test_givenMalformedStatusLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(priceCache), abi.encodeWithSignature("isEnabled()"), data_);
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D14.
    function test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-REENABLE-D15.
    function test_givenCacheActiveTrueEnabledFalse_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        priceCache.disable("");
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D16.
    function test_givenCacheActiveFalseEnabledTrue_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(priceCache));
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D17.
    function test_givenCacheActiveFalseEnabledFalse_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        priceCache.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(priceCache));
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-D13.
    function test_givenCacheReadinessRestored_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        priceCache.disable("");
        priceCache.enable("");
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-REENABLE-I08.
    function test_givenInactiveAndBrokenDependency_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        _setMembership(false);
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _activationRejected(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: PCACHER-REENABLE-I03.
    function test_givenBrokenDependency_whenExpiredGrace_reverts() public givenLifecycleDisabled {
        uint48 deadline = IEnablerV2(_lifecycleTarget).lastTransitionAt() +
            IGracePeriod(_lifecycleTarget).gracePeriod();
        vm.warp(uint256(deadline) + 1);
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _activationRejected(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
    }

    // Scenarios: PCACHER-REENABLE-N06.
    function test_givenZeroTransitionTimestamp_whenReEnabled_reverts() public {
        _pauseAt(0);
        _activationRejected(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
    }

    // Scenarios: PCACHER-REENABLE-N02.
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

    // Scenarios: PCACHER-REENABLE-L02.
    function test_givenEnabled_whenCallerSeedsReEnable_reverts() public {
        _activationRejected(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
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

    // Scenarios: PCACHER-REENABLE-D18.
    function test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(priceCache));
        vm.mockCall(
            address(priceCache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _activationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
    }

    function _activationRejected(bytes memory reason_) internal {
        _lifecycleReverts(_lifecycleAdmin, abi.encodeCall(IReEnabler.reEnable, ()), reason_);
    }

    // Scenarios: PCACHER-REENABLE-D03.
    function test_givenNoVersionInterface_whenActivated_thenAccepted()
        public
        givenLifecycleDisabled
    {
        priceCache.setInterfaceSupport(true, true, false);
        _forbidCacheVersionReads(priceCache);
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-REENABLE-D06.
    function test_givenVersionGetterReverts_whenActivated_thenIgnored()
        public
        givenLifecycleDisabled
    {
        _forbidCacheVersionReads(priceCache);
        _reEnableSucceeds(_lifecycleAdmin);
    }
}
