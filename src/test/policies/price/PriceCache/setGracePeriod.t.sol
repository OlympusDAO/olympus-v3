// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
import {IPriceCache} from "src/interfaces/IPriceCache.sol";

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract PriceCacheSetGracePeriodTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-GRACE-P01.
    function test_whenAdminSetsGrace(
        address caller_,
        uint32 grace_
    ) public givenLifecycleAdmin(caller_) {
        _graceSucceeds(caller_, SafeCast.toUint32(bound(grace_, 1, type(uint32).max)));
    }

    // Scenarios: PCACHE-GRACE-P01.
    function test_whenGraceBoundarySeeds() public {
        _graceSucceeds(_lifecycleAdmin, 1);
        _graceSucceeds(_lifecycleAdmin, type(uint32).max);
    }

    // Scenarios: PCACHE-GRACE-P02.
    function test_whenGraceUnchanged(uint32 grace_) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        _setGrace(grace);
        _graceSucceeds(_lifecycleAdmin, grace);
    }

    // Scenarios: PCACHE-GRACE-A01.
    function test_whenUnauthorizedCallerSetsGrace_reverts(address caller_) public {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(1))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: PCACHE-GRACE-I01.
    function test_whenGraceIsZero_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector)
        );
    }

    // Scenarios: PCACHE-GRACE-L01.
    function test_givenDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 grace_
    ) public givenLifecycleDisabled {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (grace_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: PCACHE-GRACE-L02.
    function test_givenInactive_whenAdminSetsGrace() public givenLifecycleInactive {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IGracePeriod.setGracePeriod, (type(uint32).max)),
            abi.encodeWithSelector(IPriceCache.PriceCache_PolicyNotActive.selector)
        );
    }

    // Scenarios: PCACHE-GRACE-L03.
    function test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 grace_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (grace_)),
            abi.encodeWithSelector(IPriceCache.PriceCache_PolicyNotActive.selector)
        );
    }

    // Scenarios: PCACHE-GRACE-L04.
    function test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 grace_
    ) public {
        _freshSubject(false);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (grace_)),
            abi.encodeWithSelector(IPriceCache.PriceCache_PolicyNotActive.selector)
        );
    }

    // Scenarios: PCACHE-GRACE-I02.
    function test_whenUnauthorizedCallerSetsZero_reverts(address caller_) public {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }
}
