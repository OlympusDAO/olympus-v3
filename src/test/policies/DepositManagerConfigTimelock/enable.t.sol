// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
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
    function test_givenManagerActiveTrueEnabledFalse_whenActivationSucceeds()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        _enableSucceeds(_lifecycleAdmin);
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
    function test_givenStatusReadReverts_whenActivationSucceeds() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _enableSucceeds(_lifecycleAdmin);
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
    function test_givenNoncanonicalStatus_whenActivationSucceeds() public givenLifecycleDisabled {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(uint256(2))
        );
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-D05.
    function test_givenMalformedStatusLength_whenActivationSucceeds(
        bytes memory data_
    ) public givenLifecycleDisabled {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(depositManager), abi.encodeWithSignature("isEnabled()"), data_);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-ENABLE-D06.
    function test_givenDifferentConfigOperator_whenActivation_reverts()
        public
        givenLifecycleDisabled
    {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
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
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-ENABLE-D14.
    function test_givenMissingConsumedInterface_whenActivation_reverts(uint8 index_) public {
        _pausePolicy(address(_configTimelock));
        bytes4[5] memory interfaces = [
            type(IDepositManager).interfaceId,
            type(IDepositManagerV1_1).interfaceId,
            type(IAssetManagerV1_1).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        uint256 index = bound(index_, 0, interfaces.length - 1);
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("supportsInterface(bytes4)", interfaces[index]),
            abi.encode(false)
        );
        uint48 beforeAt = _configTimelock.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        vm.prank(_lifecycleAdmin);
        _configTimelock.enable("");

        assertFalse(_configTimelock.isEnabled(), "Incompatible target prevents activation");
        assertEq(
            _configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected activation preserves timestamp"
        );
    }

    // Scenarios: DMCT-ENABLE-D14.
    function test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenMissingConsumedInterface_whenActivation_reverts(0);
        assertTrue(vm.revertToState(checkpoint), "Restore interface seed");
        test_givenMissingConsumedInterface_whenActivation_reverts(1);
        assertTrue(vm.revertToState(checkpoint), "Restore interface seed");
        test_givenMissingConsumedInterface_whenActivation_reverts(2);
        assertTrue(vm.revertToState(checkpoint), "Restore interface seed");
        test_givenMissingConsumedInterface_whenActivation_reverts(3);
        assertTrue(vm.revertToState(checkpoint), "Restore interface seed");
        test_givenMissingConsumedInterface_whenActivation_reverts(4);
        assertTrue(vm.revertToState(checkpoint), "Restore interface seed");
    }

    // Scenarios: DMCT-ENABLE-D15.
    function test_givenOperatorReadReverts_whenActivation_reverts() public {
        _pausePolicy(address(_configTimelock));
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        vm.prank(_lifecycleAdmin);
        _configTimelock.enable("");
    }

    // Scenarios: DMCT-ENABLE-D15.
    function test_givenMalformedOperatorLength_whenActivation_reverts(bytes memory data_) public {
        vm.assume(data_.length <= 256 && data_.length != 32);
        _pausePolicy(address(_configTimelock));
        vm.mockCall(address(depositManager), abi.encodeWithSignature("configOperator()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        vm.prank(_lifecycleAdmin);
        _configTimelock.enable("");
    }

    // Scenarios: DMCT-ENABLE-D15.
    function test_givenNoncanonicalOperator_whenActivation_reverts() public {
        _pausePolicy(address(_configTimelock));
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        vm.prank(_lifecycleAdmin);
        _configTimelock.enable("");
    }

    // Scenarios: DMCT-ENABLE-D16.
    function test_givenUnselectedOperator_whenActivation_reverts(address operator_) public {
        vm.assume(operator_ != address(_configTimelock));
        _pausePolicy(address(_configTimelock));
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(operator_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        vm.prank(_lifecycleAdmin);
        _configTimelock.enable("");
    }

    // Scenarios: DMCT-ENABLE-D16.
    function test_givenZeroOperator_whenActivation_reverts() public {
        test_givenUnselectedOperator_whenActivation_reverts(address(0));
    }
}
