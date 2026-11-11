// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockLifecycleTest} from "./fixtures/DepositManagerConfigTimelockLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";

contract DepositManagerConfigTimelockDisableTest is DepositManagerConfigTimelockLifecycleTest {
    // Scenarios: DMCT-DISABLE-A01, DMCT-DISABLE-L01.
    function test_givenAdminOnly_whenDisabled(
        address caller_
    ) public givenLifecycleAdminOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DMCT-DISABLE-A01.
    function test_givenEmergencyOnly_whenDisabled(
        address caller_
    ) public givenLifecycleEmergencyOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DMCT-DISABLE-A01.
    function test_givenAdminAndEmergency_whenDisabled(
        address caller_
    ) public givenLifecycleOverlap(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DMCT-DISABLE-A01.
    function test_whenPermittedCallerSeedsDisable() public {
        _disableSucceeds(_lifecycleAdmin);
        _enableSucceeds(_lifecycleAdmin);
        _disableSucceeds(_lifecycleEmergency);
        _enableSucceeds(_lifecycleAdmin);
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _disableSucceeds(overlap);
    }

    // Scenarios: DMCT-DISABLE-A03.
    function test_whenUnauthorizedCallerDisables_reverts(address caller_) public {
        _excludeDisableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-A03.
    function test_whenUnauthorizedCallerSeedsDisable_reverts() public {
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _lifecycleReverts(
            address(_lifecycleRolesAdmin),
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-L02.
    function test_givenDisabled_whenAdminDisables_reverts() public givenLifecycleDisabled {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-L03.
    function test_givenInactive_whenAdminDisables() public givenLifecycleInactive {
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-DISABLE-L04.
    function test_givenInactiveDisabled_whenAdminDisables_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-I01.
    function test_givenAdminOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdminOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-DISABLE-I01.
    function test_givenEmergencyOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleEmergencyOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-DISABLE-I01.
    function test_givenAdminAndEmergency_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleOverlap(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-DISABLE-I01.
    function test_whenCallerAndPayloadBoundarySeeds_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-DISABLE-I03.
    function test_whenUnauthorizedCallerUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _excludeDisableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-I04.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-I05.
    function test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleDisabled givenNonemptyPayload(data_) {
        _excludeDisableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-I06.
    function test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-DISABLE-I07.
    function test_givenInactive_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidData.selector
            )
        );
    }

    // Scenarios: DMCT-DISABLE-P01.
    function test_givenReEnabled_whenDisabled() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: DMCT-DISABLE-P02.
    function test_givenReactivated_whenDisabled() public {
        _setMembership(false);
        _setMembership(true);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: DMCT-DISABLE-D01.
    function test_givenDependencyReadsRevert_whenDisabled() public {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-DISABLE-D02.
    function test_givenDependencyActiveTrueEnabledTrue_whenDisabled() public {
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-DISABLE-D03.
    function test_givenDependencyActiveTrueEnabledFalse_whenDisabled() public {
        vm.prank(ADMIN);
        depositManager.disable("");
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-DISABLE-D04.
    function test_givenDependencyActiveFalseEnabledTrue_whenDisabled() public {
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DMCT-DISABLE-D05.
    function test_givenDependencyActiveFalseEnabledFalse_whenDisabled() public {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _disableSucceeds(_lifecycleAdmin);
    }
}
