// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract PriceCacherTaskEnableTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-ENABLE-A01, PCACHER-ENABLE-L01.
    function test_givenDisabled_whenAdminEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _enableSucceeds(caller_);
    }

    // Scenarios: PCACHER-ENABLE-A01.
    function test_whenAdminAndOverlapSeedsEnable() public givenLifecycleDisabled {
        _enableSucceeds(_lifecycleAdmin);
        _pause();
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _enableSucceeds(overlap);
    }

    // Scenarios: PCACHER-ENABLE-A02.
    function test_givenDisabled_whenUnauthorizedCallerEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHER-ENABLE-A02.
    function test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts()
        public
        givenLifecycleDisabled
    {
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
        _lifecycleReverts(
            heart,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHER-ENABLE-L02.
    function test_givenEnabled_whenAdminEnables_reverts() public {
        _activationRejected(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    // Scenarios: PCACHER-ENABLE-L03.
    function test_givenInactiveDisabled_whenAdminEnables_reverts()
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

    // Scenarios: PCACHER-ENABLE-L04.
    function test_givenInactiveEnabled_whenAdminEnables_reverts() public givenLifecycleInactive {
        _activationRejected(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    // Scenarios: PCACHER-ENABLE-I01.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-I01.
    function test_givenDisabled_whenPayloadBoundarySeeds_reverts() public givenLifecycleDisabled {
        bytes[4] memory payloads = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < payloads.length; ++i)
            _lifecycleReverts(
                _lifecycleAdmin,
                abi.encodeCall(IEnabler.enable, (payloads[i])),
                abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
            );
    }

    // Scenarios: PCACHER-ENABLE-I02.
    function test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleDisabled givenNonemptyPayload(data_) {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHER-ENABLE-I03.
    function test_givenEnabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-I04.
    function test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-I05.
    function test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts(
        address caller_
    ) public {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-I06.
    function test_givenInactiveDisabled_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-I07.
    function test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHER-ENABLE-P01.
    function test_givenReactivated_whenAdminEnables()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-P02.
    function test_givenNeverEnabled_whenAdminEnables() public {
        _freshSubject(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-P03.
    function test_givenExpiredGrace_whenAdminEnables() public givenLifecycleDisabled {
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-D01.
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

    // Scenarios: PCACHER-ENABLE-D02.
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

    // Scenarios: PCACHER-ENABLE-D05.
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

    // Scenarios: PCACHER-ENABLE-D08.
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

    // Scenarios: PCACHER-ENABLE-D10.
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

    // Scenarios: PCACHER-ENABLE-D09.
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

    // Scenarios: PCACHER-ENABLE-D09.
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

    // Scenarios: PCACHER-ENABLE-D11.
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

    // Scenarios: PCACHER-ENABLE-D11.
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

    // Scenarios: PCACHER-ENABLE-L05.
    function test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-L06.
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

    // Scenarios: PCACHER-ENABLE-L07.
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

    // Scenarios: PCACHER-ENABLE-L08.
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

    // Scenarios: PCACHER-ENABLE-D13.
    function test_givenCacheReadinessRestored_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        priceCache.disable("");
        priceCache.enable("");
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-I08.
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

    // Scenarios: PCACHER-ENABLE-I09.
    function test_givenBrokenDependency_whenNonemptyPayload_reverts()
        public
        givenLifecycleDisabled
    {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(hex"00"))),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-ENABLE-D18.
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
        _lifecycleReverts(_lifecycleAdmin, abi.encodeCall(IEnabler.enable, (bytes(""))), reason_);
    }

    // Scenarios: PCACHER-ENABLE-D03.
    function test_givenNoVersionInterface_whenActivated_thenAccepted()
        public
        givenLifecycleDisabled
    {
        priceCache.setInterfaceSupport(true, true, false);
        _forbidCacheVersionReads(priceCache);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-ENABLE-D06.
    function test_givenVersionGetterReverts_whenActivated_thenIgnored()
        public
        givenLifecycleDisabled
    {
        _forbidCacheVersionReads(priceCache);
        _enableSucceeds(_lifecycleAdmin);
    }
}
