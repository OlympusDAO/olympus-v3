// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerLifecycleTest} from "./fixtures/DepositManagerLifecycleTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract DepositManagerSetGracePeriodTest is DepositManagerLifecycleTest {
    // Scenarios: DM-GRACE-P01.
    function test_whenAdminSetsGrace(
        address caller_,
        uint32 grace_
    ) public givenLifecycleAdmin(caller_) {
        _graceSucceeds(caller_, uint32(bound(grace_, 1, type(uint32).max)));
    }

    // Scenarios: DM-GRACE-P01, DM-GRACE-P02.
    function test_whenGraceBoundarySeeds() public {
        _graceSucceeds(_lifecycleAdmin, 1);
        _graceSucceeds(_lifecycleAdmin, 1);
        _graceSucceeds(_lifecycleAdmin, type(uint32).max);
        _graceSucceeds(_lifecycleAdmin, type(uint32).max);
    }

    // Scenarios: DM-GRACE-P02.
    function test_whenGraceUnchanged(uint32 grace_) public {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        _setGrace(grace);
        _graceSucceeds(_lifecycleAdmin, grace);
    }

    // Scenarios: DM-GRACE-A01.
    function test_whenUnauthorizedCallerSetsGrace_reverts(address caller_) public {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(1))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: DM-GRACE-I01.
    function test_whenGraceIsZero_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector)
        );
    }

    // Scenarios: DM-GRACE-L01.
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

    // Scenarios: DM-GRACE-L02.
    function test_givenInactive_whenAdminSetsGrace() public givenLifecycleInactive {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IGracePeriod.setGracePeriod, (type(uint32).max)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
    }

    // Scenarios: DM-GRACE-L03.
    function test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 grace_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (grace_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
    }

    // Scenarios: DM-GRACE-L04.
    function test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 grace_
    ) public {
        _freshSubject(false);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (grace_)),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
    }

    // Scenarios: DM-GRACE-I02.
    function test_whenUnauthorizedCallerSetsZero_reverts(address caller_) public {
        _excludeEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IGracePeriod.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: DM-GRACE-A01, DM-GRACE-I02.
    function test_whenUnauthorizedCallerSeedsSetGrace_reverts() public {
        address[3] memory callers = [address(0), _lifecycleSecondary, _lifecycleEmergency];
        for (uint256 i; i < callers.length; ++i)
            for (uint32 grace; grace < 2; ++grace)
                _lifecycleReverts(
                    callers[i],
                    abi.encodeCall(IGracePeriod.setGracePeriod, (grace)),
                    abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
                );
    }

    // Scenarios: DM-GRACE-L01.
    function test_givenDisabled_whenGraceBoundarySeeds_reverts() public givenLifecycleDisabled {
        _disabledGraceBoundarySeeds();
    }

    // Scenarios: DM-GRACE-L03.
    function test_givenInactiveDisabled_whenGraceBoundarySeeds_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _inactiveGraceBoundarySeeds();
    }

    // Scenarios: DM-GRACE-L04.
    function test_givenNeverConfigured_whenGraceBoundarySeeds_reverts() public {
        _freshSubject(false);
        _inactiveGraceBoundarySeeds();
    }

    function _disabledGraceBoundarySeeds() internal {
        uint32[3] memory periods = [uint32(0), uint32(1), type(uint32).max];
        for (uint256 i; i < periods.length; ++i)
            _lifecycleReverts(
                _lifecycleAdmin,
                abi.encodeCall(IGracePeriod.setGracePeriod, (periods[i])),
                abi.encodeWithSelector(IEnabler.NotEnabled.selector)
            );
    }

    function _inactiveGraceBoundarySeeds() internal {
        uint32[3] memory periods = [uint32(0), uint32(1), type(uint32).max];
        for (uint256 i; i < periods.length; ++i)
            _lifecycleReverts(
                _lifecycleAdmin,
                abi.encodeCall(IGracePeriod.setGracePeriod, (periods[i])),
                abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
            );
    }
}
