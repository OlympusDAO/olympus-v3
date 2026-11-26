// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";

contract PriceCacheReEnableTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-REENABLE-A01, PCACHE-REENABLE-L01.
    function test_givenPaused_whenAdminReEnables(
        address caller_
    ) public givenLifecycleAdmin(caller_) givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, PRICE_ADMIN_ROLE));
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHE-REENABLE-A01, PCACHE-REENABLE-L01.
    function test_givenPaused_whenPriceAdminReEnables(
        address caller_
    ) public givenLifecycleDisabled {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantLifecycleRole(PRICE_ADMIN_ROLE, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHE-REENABLE-A01, PCACHE-REENABLE-L01.
    function test_givenPaused_whenBothRolesReEnable(address caller_) public givenLifecycleDisabled {
        _grantLifecycleRole(ADMIN_ROLE, caller_);
        _grantLifecycleRole(PRICE_ADMIN_ROLE, caller_);
        _reEnableSucceeds(caller_);
    }

    // Scenarios: PCACHE-REENABLE-A01.
    function test_whenPermittedCallerSeedsReEnable() public givenLifecycleDisabled {
        _reEnableSucceeds(_lifecycleAdmin);
        _pause();
        _reEnableSucceeds(_lifecycleSecondary);
        _pause();
        address overlap = makeAddr("adminAndPriceAdmin");
        _grantLifecycleRole(ADMIN_ROLE, overlap);
        _grantLifecycleRole(PRICE_ADMIN_ROLE, overlap);
        _reEnableSucceeds(overlap);
    }

    // Scenarios: PCACHE-REENABLE-A02.
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

    // Scenarios: PCACHE-REENABLE-A02.
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

    // Scenarios: PCACHE-REENABLE-L02.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(address caller_) public {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHE-REENABLE-L03.
    function test_givenInactivePaused_whenReEnabled_reverts()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IPriceCache.PriceCache_PolicyInactive.selector)
        );
    }

    // Scenarios: PCACHE-REENABLE-L04.
    function test_givenInactiveEnabled_whenAnyCallerReEnables_reverts(
        address caller_
    ) public givenLifecycleInactive {
        _lifecycleReverts(
            caller_,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: PCACHE-REENABLE-L05.
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

    // Scenarios: PCACHE-REENABLE-L06.
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

    // Scenarios: PCACHE-REENABLE-I01.
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

    // Scenarios: PCACHE-REENABLE-N01.
    function test_whenIndependentGraceAndTimeWithinWindow(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 elapsed_
    ) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        vm.warp(uint256(disabledAt) + bound(elapsed_, 0, grace));
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHE-REENABLE-N02.
    function test_whenIndependentGraceAndTimeExpired_reverts(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace - 1)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        uint48 deadline = disabledAt + grace;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
    }

    // Scenarios: PCACHE-REENABLE-N03.
    function test_whenImmediately() public {
        _setGrace(1);
        _pauseAt(100);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-N03.
    function test_whenOneBeforeDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 6);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-N03.
    function test_whenAtDeadline() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(100 + 7);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-N03.
    function test_whenAtMaximumGraceDeadline() public {
        _setGrace(type(uint32).max);
        _pauseAt(100);
        vm.warp(100 + uint256(type(uint32).max));
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-N03.
    function test_whenDeadlineIsMaximumTimestamp() public {
        _setGrace(1);
        _pauseAt(type(uint48).max - 1);
        vm.warp(type(uint48).max);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-N04.
    function test_whenFirstTimestampAfterDeadline_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(102);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: PCACHE-REENABLE-N05.
    function test_whenDeadlineOverflows_reverts(uint32 grace_, uint48 disabledAt_) public {
        uint32 grace = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        uint48 disabledAt = uint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace + 1, type(uint48).max)
        );
        _setGrace(grace);
        _pauseAt(disabledAt);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt) + grace
            )
        );
    }

    // Scenarios: PCACHE-REENABLE-N05.
    function test_whenMaximumTimestampMakesDeadlineOverflow_reverts() public {
        _setGrace(1);
        _pauseAt(type(uint48).max);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 1
            )
        );
    }

    // Scenarios: PCACHE-REENABLE-I02.
    function test_givenInactive_whenGraceExpired_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        _setMembership(false);
        vm.warp(102);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: PCACHE-REENABLE-P01.
    function test_givenReactivated_whenReEnabled()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        _setMembership(true);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-P02.
    function test_whenRepeatedCyclesRestartGrace() public {
        _setGrace(7);
        _pauseAt(100);
        vm.warp(107);
        _reEnableSucceeds(_lifecycleSecondary);
        _pauseAt(200);
        vm.warp(207);
        _reEnableSucceeds(_lifecycleSecondary);
    }

    // Scenarios: PCACHE-REENABLE-D01.
    function test_givenPriceReadsRevert_whenTransitionSucceeds() public givenLifecycleDisabled {
        vm.mockCallRevert(
            address(priceModule),
            bytes(""),
            abi.encodeWithSignature("PriceReadFailed()")
        );
        _reEnableSucceeds(_lifecycleAdmin);
    }

    // Scenarios: PCACHE-REENABLE-N06.
    function test_givenZeroTransitionTimestamp_whenReEnabled_reverts() public {
        _pauseAt(0);
        _lifecycleReverts(
            _lifecycleAdmin,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: PCACHE-REENABLE-N02.
    function test_whenMaximumTimestampIsExpired_reverts() public {
        _setGrace(1);
        _pauseAt(100);
        vm.warp(type(uint48).max);
        _lifecycleReverts(
            _lifecycleSecondary,
            abi.encodeCall(IReEnabler.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(101))
        );
    }

    // Scenarios: PCACHE-REENABLE-P03.
    function test_whenLifecycleInterfacesQueried(address caller_) public {
        vm.startPrank(caller_);
        assertTrue(
            cache.supportsInterface(type(IEnabler).interfaceId),
            "legacy enabler advertised"
        );
        assertTrue(
            cache.supportsInterface(type(IEnablerV2).interfaceId),
            "timestamp lifecycle advertised"
        );
        assertTrue(cache.supportsInterface(type(IReEnabler).interfaceId), "reEnable advertised");
        assertTrue(cache.supportsInterface(type(IGracePeriod).interfaceId), "grace advertised");
        assertTrue(
            cache.supportsInterface(type(IPriceCache).interfaceId),
            "cache interface retained"
        );
        vm.stopPrank();
        assertEq(cache.gracePeriod(), 7 days, "initial grace matches related policies");
    }

    // Scenarios: PCACHE-REENABLE-L02.
    function test_givenEnabled_whenCallerSeedsReEnable_reverts() public {
        _lifecycleReverts(
            _lifecycleAdmin,
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
