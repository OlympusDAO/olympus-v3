// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Actions} from "src/Kernel.sol";

contract PriceCacherTaskDisableTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-DISABLE-A01, PCACHER-DISABLE-L01.
    function test_givenAdminOnly_whenDisabled(
        address caller_
    ) public givenLifecycleAdminOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: PCACHER-DISABLE-A01.
    function test_givenEmergencyOnly_whenDisabled(
        address caller_
    ) public givenLifecycleEmergencyOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: PCACHER-DISABLE-A01.
    function test_givenAdminAndEmergency_whenDisabled(
        address caller_
    ) public givenLifecycleOverlap(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: PCACHER-DISABLE-A01.
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

    // Scenarios: PCACHER-DISABLE-A03.
    function test_whenUnauthorizedCallerDisables_reverts(address caller_) public {
        _excludeDisableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-A03.
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
    }

    // Scenarios: PCACHER-DISABLE-L02.
    function test_givenDisabled_whenAdminDisables_reverts() public givenLifecycleDisabled {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-L03.
    function test_givenInactive_whenAdminDisables() public givenLifecycleInactive {
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-DISABLE-L04.
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

    // Scenarios: PCACHER-DISABLE-I01.
    function test_givenAdminOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdminOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-I01.
    function test_givenEmergencyOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleEmergencyOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-I01.
    function test_givenAdminAndEmergency_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleOverlap(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-I01.
    function test_whenCallerAndPayloadBoundarySeeds_reverts() public {
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        address[3] memory callers = [_lifecycleAdmin, _lifecycleEmergency, overlap];
        bytes[4] memory payloads = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < callers.length; ++i)
            for (uint256 j; j < payloads.length; ++j)
                _lifecycleReverts(
                    callers[i],
                    abi.encodeCall(IEnabler.disable, (payloads[j])),
                    abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
                );
    }

    // Scenarios: PCACHER-DISABLE-I03.
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

    // Scenarios: PCACHER-DISABLE-I04.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-I05.
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

    // Scenarios: PCACHER-DISABLE-I06.
    function test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-I07.
    function test_givenInactive_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_InvalidData.selector)
        );
    }

    // Scenarios: PCACHER-DISABLE-P01.
    function test_givenReEnabled_whenDisabled() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: PCACHER-DISABLE-P02.
    function test_givenReactivated_whenDisabled() public {
        _setMembership(false);
        _setMembership(true);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: PCACHER-DISABLE-D01.
    function test_givenDependencyReadsRevert_whenDisabled() public {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("DependencyReadFailed()")
        );
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-DISABLE-D02.
    function test_givenDependencyActiveTrueEnabledTrue_whenDisabled() public {
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-DISABLE-D03.
    function test_givenDependencyActiveTrueEnabledFalse_whenDisabled() public {
        priceCache.disable("");
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-DISABLE-D04.
    function test_givenDependencyActiveFalseEnabledTrue_whenDisabled() public {
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(priceCache));
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHER-DISABLE-D05.
    function test_givenDependencyActiveFalseEnabledFalse_whenDisabled() public {
        priceCache.disable("");
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(Actions.DeactivatePolicy, address(priceCache));
        _disableSucceeds(_lifecycleAdmin);
    }
}
