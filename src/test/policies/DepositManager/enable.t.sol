// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerLifecycleTest} from "./fixtures/DepositManagerLifecycleTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract DepositManagerEnableTest is DepositManagerLifecycleTest {
    // Scenarios: DM-ENABLE-A01, DM-ENABLE-L01.
    function test_givenDisabled_whenAdminEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _enableSucceeds(caller_);
    }

    // Scenarios: DM-ENABLE-A01.
    function test_whenAdminAndOverlapSeedsEnable() public givenLifecycleDisabled {
        _enableSucceeds(_lifecycleAdmin);
        _pause();
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _enableSucceeds(overlap);
    }

    // Scenarios: DM-ENABLE-A02.
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

    // Scenarios: DM-ENABLE-A02.
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

    // Scenarios: DM-ENABLE-L02.
    function test_givenEnabled_whenAdminEnables_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DM-ENABLE-L03.
    function test_givenInactiveDisabled_whenAdminEnables_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
    }

    // Scenarios: DM-ENABLE-L04.
    function test_givenInactiveEnabled_whenAdminEnables_reverts() public givenLifecycleInactive {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DM-ENABLE-I01.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-ENABLE-I01.
    function test_givenDisabled_whenPayloadBoundarySeeds_reverts() public givenLifecycleDisabled {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (hex"00")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (hex"01")),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (new bytes(256))),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-ENABLE-I02.
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

    // Scenarios: DM-ENABLE-I03.
    function test_givenEnabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DM-ENABLE-I04.
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

    // Scenarios: DM-ENABLE-I05.
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

    // Scenarios: DM-ENABLE-I06.
    function test_givenInactiveDisabled_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_InvalidData.selector)
        );
    }

    // Scenarios: DM-ENABLE-I07.
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

    // Scenarios: DM-ENABLE-P01.
    function test_givenReactivated_whenAdminEnables()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-ENABLE-P02.
    function test_givenNeverEnabled_whenAdminEnables() public {
        _freshSubject(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-ENABLE-P03.
    function test_givenExpiredGrace_whenAdminEnables() public givenLifecycleDisabled {
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-ENABLE-D01.
    function test_givenVaultDeliveryReverts_whenTransitionSucceeds() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(vault),
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            abi.encodeWithSignature("VaultDeliveryFailed()")
        );
        _enableSucceeds(_lifecycleAdmin);
    }
}
