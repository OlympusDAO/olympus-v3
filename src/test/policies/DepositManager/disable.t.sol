// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerLifecycleTest} from "./fixtures/DepositManagerLifecycleTest.sol";

contract DepositManagerDisableTest is DepositManagerLifecycleTest {
    // Scenarios: DM-DISABLE-A01, DM-DISABLE-L01.
    function test_givenAdminOnly_whenDisabled(
        address caller_
    ) public givenLifecycleAdminOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DM-DISABLE-A01, DM-DISABLE-L01.
    function test_givenEmergencyOnly_whenDisabled(
        address caller_
    ) public givenLifecycleEmergencyOnly(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DM-DISABLE-A01, DM-DISABLE-L01.
    function test_givenAdminAndEmergency_whenDisabled(
        address caller_
    ) public givenLifecycleOverlap(caller_) {
        _disableSucceeds(caller_);
    }

    // Scenarios: DM-DISABLE-A01, DM-DISABLE-L01.
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

    // Scenarios: DM-DISABLE-A03.
    function test_whenUnauthorizedCallerDisables_reverts(address caller_) public {
        _excludeDisableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DM-DISABLE-A03.
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

    // Scenarios: DM-DISABLE-L02.
    function test_givenDisabled_whenAdminDisables_reverts() public givenLifecycleDisabled {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DM-DISABLE-L03.
    function test_givenInactive_whenAdminDisables() public givenLifecycleInactive {
        _disableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-DISABLE-L04.
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

    // Scenarios: DM-DISABLE-I01.
    function test_givenAdminOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdminOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-DISABLE-I01.
    function test_givenEmergencyOnly_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleEmergencyOnly(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-DISABLE-I01.
    function test_givenAdminAndEmergency_whenNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleOverlap(caller_) givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-DISABLE-I01.
    function test_whenCallerAndPayloadBoundarySeeds_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (hex"00")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (hex"01")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            overlap,
            abi.encodeCall(IEnabler.disable, (new bytes(256))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-DISABLE-I03.
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

    // Scenarios: DM-DISABLE-I04.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DM-DISABLE-I05.
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

    // Scenarios: DM-DISABLE-I06.
    function test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DM-DISABLE-I07.
    function test_givenInactive_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.disable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-DISABLE-P01.
    function test_givenReEnabled_whenDisabled() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: DM-DISABLE-P02.
    function test_givenReactivated_whenDisabled() public {
        _setMembership(false);
        _setMembership(true);
        _disableSucceeds(_lifecycleEmergency);
    }

    // Scenarios: DM-DISABLE-D01.
    function test_givenVaultDeliveryReverts_whenTransitionSucceeds() public {
        vm.mockCallRevert(
            address(vault),
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            abi.encodeWithSignature("VaultDeliveryFailed()")
        );
        _disableSucceeds(_lifecycleAdmin);
    }
}
