// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract PriceCacheEnableTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-ENABLE-A01, PCACHE-ENABLE-L01.
    function test_givenDisabled_whenAdminEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _enableSucceeds(caller_);
    }

    // Scenarios: PCACHE-ENABLE-A01.
    function test_whenAdminAndOverlapSeedsEnable() public givenLifecycleDisabled {
        _enableSucceeds(_lifecycleAdmin);
        _pause();
        address overlap = makeAddr("adminEmergencyOverlap");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(EMERGENCY_ROLE, overlap);
        _enableSucceeds(overlap);
    }

    // Scenarios: PCACHE-ENABLE-A02.
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

    // Scenarios: PCACHE-ENABLE-A02.
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
            priceManager,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHE-ENABLE-L02.
    function test_givenEnabled_whenAdminEnables_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-L03.
    function test_givenInactiveDisabled_whenAdminEnables_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IPriceCache.PriceCache_PolicyInactive.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-L04.
    function test_givenInactiveEnabled_whenAdminEnables_reverts() public givenLifecycleInactive {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-I01.
    function test_givenDisabled_whenAdminUsesNonemptyPayload_reverts(
        address caller_,
        bytes memory data_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled givenNonemptyPayload(data_) {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidData.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-I01.
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
                abi.encodeWithSelector(IPriceCache.PriceCache_InvalidData.selector)
            );
    }

    // Scenarios: PCACHE-ENABLE-I02.
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

    // Scenarios: PCACHE-ENABLE-I03.
    function test_givenEnabled_whenAdminUsesNonemptyPayload_reverts(
        bytes memory data_
    ) public givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-I04.
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

    // Scenarios: PCACHE-ENABLE-I05.
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

    // Scenarios: PCACHE-ENABLE-I06.
    function test_givenInactiveDisabled_whenNonemptyPayload_reverts(
        bytes memory data_
    ) public givenLifecycleDisabled givenLifecycleInactive givenNonemptyPayload(data_) {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IEnabler.enable, (data_)),
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidData.selector)
        );
    }

    // Scenarios: PCACHE-ENABLE-I07.
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

    // Scenarios: PCACHE-ENABLE-P01.
    function test_givenReactivated_whenAdminEnables()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHE-ENABLE-P02.
    function test_givenNeverEnabled_whenAdminEnables() public {
        _freshSubject(true);
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHE-ENABLE-P03.
    function test_givenExpiredGrace_whenAdminEnables() public givenLifecycleDisabled {
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _enableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHE-ENABLE-D01.
    function test_givenPriceReadsRevert_whenTransitionSucceeds() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(priceModule),
            bytes(""),
            abi.encodeWithSignature("PriceReadFailed()")
        );
        _enableSucceeds(_lifecycleAdmin);
    }
}
