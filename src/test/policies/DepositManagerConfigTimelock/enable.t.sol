// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockLifecycleTest} from "./fixtures/DepositManagerConfigTimelockLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";

contract DepositManagerConfigTimelockEnableTest is DepositManagerConfigTimelockLifecycleTest {
    // Scenarios: DMCT-ENABLE-A01, DMCT-ENABLE-L01.
    function test_givenDisabled_whenAdminEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _enableSucceeds(caller_);
    }

    // Scenarios: DMCT-ENABLE-A01.
    function test_whenAdminAndOverlapSeedsEnable() public givenLifecycleDisabled {
        _enableSucceeds(_lifecycleAdmin);
        _pause();
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _enableSucceeds(overlap);
    }

    // Scenarios: DMCT-ENABLE-A02.
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

    // Scenarios: DMCT-ENABLE-A02.
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
            DEPOSIT_MANAGER_ADMIN,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: DMCT-ENABLE-L02.
    function test_givenEnabled_whenAdminEnables_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-ENABLE-L03.
    function test_givenInactiveDisabled_whenAdminEnables_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: DMCT-ENABLE-L04.
    function test_givenInactiveEnabled_whenAdminEnables_reverts() public givenLifecycleInactive {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-ENABLE-I01.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-ENABLE-I01.
    function test_givenDisabled_whenPayloadBoundarySeeds_reverts() public givenLifecycleDisabled {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (hex"00")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (hex"01")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (new bytes(256))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-ENABLE-I02.
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

    // Scenarios: DMCT-ENABLE-I03.
    function test_givenEnabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DMCT-ENABLE-I04.
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

    // Scenarios: DMCT-ENABLE-I05.
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

    // Scenarios: DMCT-ENABLE-I06.
    function test_givenInactiveDisabled_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-ENABLE-I07.
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

    // Scenarios: DMCT-ENABLE-P01.
    function test_givenReactivated_whenAdminEnables()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-P02.
    function test_givenNeverEnabled_whenAdminEnables() public {
        _freshSubject(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-P03.
    function test_givenExpiredGrace_whenAdminEnables() public givenLifecycleDisabled {
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-L05.
    function test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-L06.
    function test_givenManagerActiveTrueEnabledFalse_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-L07.
    function test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-L08.
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
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D01.
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
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(depositManager),
                address(kernel),
                address(0xBEEF)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D02.
    function test_givenKernelReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D04.
    function test_givenStatusReadReverts_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D03.
    function test_givenNoncanonicalKernel_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D03.
    function test_givenMalformedKernelLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(depositManager), abi.encodeWithSignature("kernel()"), data_);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D05.
    function test_givenNoncanonicalStatus_whenActivation_reverts() public givenLifecycleDisabled {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D05.
    function test_givenMalformedStatusLength_whenActivation_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(depositManager), abi.encodeWithSignature("isEnabled()"), data_);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D06.
    function test_givenDifferentConfigOperator_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-D07.
    function test_givenManagerReadinessRestored_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(ADMIN);
        depositManager.reEnable();
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-I08.
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
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                _lifecycleTarget
            )
        );
    }

    // Scenarios: DMCT-ENABLE-I09.
    function test_givenBrokenDependency_whenNonemptyPayload_reverts()
        public
        givenLifecycleDisabled
    {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(hex"00"))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-ENABLE-L08.
    function test_givenDepositManagerIsInactive_enableReverts() public {
        DepositManager inactiveDepositManager = new DepositManager(
            address(kernel),
            address(receiptTokenManager)
        );
        DepositManagerConfigTimelock inactiveTargetTimelock = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(inactiveDepositManager))
        );
        vm.prank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(inactiveTargetTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(inactiveDepositManager)
            )
        );
        vm.prank(ADMIN);
        inactiveTargetTimelock.enable("");
    }

    // Scenarios: DMCT-ENABLE-D13.
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
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }
}
