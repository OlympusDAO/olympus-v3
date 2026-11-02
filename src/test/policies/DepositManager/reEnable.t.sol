// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerLifecycleTest} from "./fixtures/DepositManagerLifecycleTest.sol";

contract DepositManagerReEnableTest is DepositManagerLifecycleTest {
    // Scenarios: DM-REENABLE-A01, DM-REENABLE-L01.
    function test_givenPaused_whenAdminReEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        vm.assume(!_lifecycleRoles.hasRole(caller_, _lifecycleSecondaryRole));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-A01, DM-REENABLE-L01.
    function test_givenSecondaryOnly_whenReEnabled(address caller_) public givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantLifecycleRole(_lifecycleSecondaryRole, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-A01, DM-REENABLE-L01.
    function test_givenAdminAndSecondary_whenReEnabled(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        _grantLifecycleRole(_lifecycleSecondaryRole, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-A01, DM-REENABLE-L01.
    function test_whenPermittedCallerSeedsReEnable() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _pause();
        _reEnableSucceeds(_lifecycleSecondary);
        _pause();
        _grantLifecycleRole(_lifecycleSecondaryRole, _lifecycleAdmin);
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-REENABLE-A02.
    function test_givenPaused_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled {
        _excludeReEnableCallers(caller_);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DM-REENABLE-A02.
    function test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts()
        public
        givenLifecycleDisabled
    {
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DM-REENABLE-L02.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(address caller_) public {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DM-REENABLE-L03.
    function test_givenInactivePaused_whenReEnabled_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
    }

    // Scenarios: DM-REENABLE-L04.
    function test_givenInactiveEnabled_whenAnyCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: DM-REENABLE-L05.
    function test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts(
        address caller_
    ) public {
        _freshSubject(true);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DM-REENABLE-L06.
    function test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts(
        address caller_
    ) public {
        _freshSubject(false);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DM-REENABLE-I01.
    function test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        _excludeReEnableCallers(caller_);
        vm.warp(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()) +
                IGracePeriod(_lifecycleTarget).gracePeriod() +
                1
        );
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DM-REENABLE-N01.
    function test_whenIndependentGraceAndTimeWithinWindow(
        address caller_,
        bool admin_,
        bool secondary_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 elapsed_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace));
        _setGrace(grace);
        _pauseAt(disabledAt);
        vm.warp(uint256(disabledAt) + bound(elapsed_, 0, grace));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N02.
    function test_whenIndependentGraceAndTimeExpired_reverts(
        address caller_,
        bool admin_,
        bool secondary_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace - 1));
        _setGrace(grace);
        _pauseAt(disabledAt);
        uint48 deadline = disabledAt + grace;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
    }

    // Scenarios: DM-REENABLE-N03.
    function test_whenImmediately(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(1);
        _pauseAt(100);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N03.
    function test_whenOneBeforeDeadline(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 6);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N03.
    function test_whenAtDeadline(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 7);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N03.
    function test_whenAtMaximumGraceDeadline(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(type(uint32).max);
        _pauseAt(100);
        vm.warp(100 + uint256(type(uint32).max));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N03.
    function test_whenDeadlineIsMaximumTimestamp(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(1);
        _pauseAt(type(uint48).max - 1);
        vm.warp(type(uint48).max);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: DM-REENABLE-N04.
    function test_whenFirstTimestampAfterDeadline_reverts(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(102);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DM-REENABLE-N05.
    function test_whenDeadlineOverflows_reverts(
        address caller_,
        bool admin_,
        bool secondary_,
        uint32 grace_,
        uint48 disabledAt_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace + 1, type(uint48).max)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt) + grace
            )
        );
    }

    // Scenarios: DM-REENABLE-N05.
    function test_whenMaximumTimestampMakesDeadlineOverflow_reverts(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(1);
        _pauseAt(type(uint48).max);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 1
            )
        );
    }

    // Scenarios: DM-REENABLE-I02.
    function test_givenInactive_whenGraceExpired_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        _setMembership(false);
        vm.warp(102);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DM-REENABLE-P01.
    function test_givenReactivated_whenReEnabled()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-REENABLE-P02.
    function test_whenRepeatedCyclesRestartGrace() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(107);
        _reEnableSucceeds(_lifecycleAdmin);
        _pauseAt(200);
        vm.warp(207);
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-REENABLE-D01.
    function test_givenVaultDeliveryReverts_whenTransitionSucceeds() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(vault),
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            abi.encodeWithSignature("VaultDeliveryFailed()")
        );
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: DM-REENABLE-N06.
    function test_givenZeroTransitionTimestamp_whenReEnabled_reverts(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _pauseAt(0);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: DM-REENABLE-N02.
    function test_whenMaximumTimestampIsExpired_reverts(
        address caller_,
        bool admin_,
        bool secondary_
    ) public givenReEnableCaller(caller_, admin_, secondary_) {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(type(uint48).max);
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: DM-REENABLE-L02.
    function test_givenEnabled_whenCallerSeedsReEnable_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            _lifecycleEmergency,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
        _lifecycleReverts(
            address(0),
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }
}
