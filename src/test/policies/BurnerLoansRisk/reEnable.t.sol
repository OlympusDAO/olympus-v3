// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskReEnableTest is BurnerLoansRiskTest {
    function _transition(address caller_) private {
        bytes32 beforeConfig = _configurationHash();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(_risk));
        emit IEnablerV2.Transition(caller_, true, "", uint48(block.timestamp));
        vm.recordLogs();
        vm.prank(caller_);
        _risk.reEnable();
        assertEq(vm.getRecordedLogs().length, 2, "exact lifecycle event count");
        assertEq(_risk.isEnabled(), true, "transition flag");
        assertEq(_risk.lastTransitionAt(), block.timestamp, "transition time");
        assertEq(
            _configurationHash(),
            beforeConfig,
            "transition preserves configuration and token supply"
        );
    }

    // Scenarios: BLRISK-REENABLE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(this));
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.reEnable();
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed transition preserves time");
        assertEq(_risk.isEnabled(), false, "failed transition preserves flag");
    }

    // Scenarios: BLRISK-REENABLE-A02, BLRISK-REENABLE-L01.
    function test_givenAdmin_whenTransition(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-L02.
    function test_givenAdminActive_whenAlreadyEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-L04.
    function test_givenAdminInactive_whenAlreadyEnabled_reverts(
        address caller_
    ) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-L03.
    function test_givenAdminInactive_whenTransition_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _expectInactive();
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-D01.
    function test_givenAdminOracleInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IBackingOracle).interfaceId)),
            abi.encode(false)
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-REENABLE-D02.
    function test_givenAdminCacheInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        bytes4[3] memory interfaces = [
            type(IPriceCache).interfaceId,
            type(IEnabler).interfaceId,
            type(IVersioned).interfaceId
        ];
        for (uint256 i; i < interfaces.length; ++i) {
            _cache.setInterfaceSupport(interfaces[i], false);
            uint48 beforeTime = _risk.lastTransitionAt();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                    address(_cache)
                )
            );
            vm.prank(caller_);
            _risk.reEnable();
            assertFalse(_risk.isEnabled(), "failed activation remains disabled");
            assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
            _cache.setInterfaceSupport(interfaces[i], true);
        }
    }

    // Scenarios: BLRISK-REENABLE-D03.
    function test_givenAdminCacheKernel_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_cache),
                address(_kernel),
                address(0xBAD)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenAdminCache11_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenAdminCache10_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenAdminCache01_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenAdminCache00_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D05.
    function test_givenAdmin_whenDependencyRestored(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                address(_cache)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, true);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N01.
    function test_givenAdminNeverEnabled_whenReEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        BurnerLoansRisk fresh = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(_oracle),
            address(0),
            0,
            address(this)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenAdmin_whenWithinGrace(
        address caller_,
        uint32 grace_,
        uint48 last_,
        uint48 now_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 last = uint48(bound(last_, 1, type(uint48).max - grace));
        _risk.setGracePeriod(grace);
        vm.warp(last);
        _risk.disable("");
        vm.warp(bound(now_, last, uint256(last) + grace));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenAdmin_whenAtDisable(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _risk.disable("");
        vm.warp(uint256(_risk.lastTransitionAt()) + 0);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenAdmin_whenAtDeadline(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _risk.disable("");
        vm.warp(uint256(_risk.lastTransitionAt()) + _risk.gracePeriod());
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenAdmin_whenGraceExpired_reverts(
        address caller_,
        uint48 now_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenAdmin_whenAfterDeadline_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(uint256(deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenAdmin_whenMaxTimestamp_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(type(uint48).max);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenAdmin_whenDeadlineOverflows_reverts(
        address caller_,
        uint32 grace_,
        uint48 last_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        _risk.setGracePeriod(grace);
        uint48 last = uint48(bound(last_, uint256(type(uint48).max) - grace + 1, type(uint48).max));
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last) + grace
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenAdmin_whenOverflowStart_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint256 last = uint256(type(uint48).max) - _risk.gracePeriod() + 1;
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                last + _risk.gracePeriod()
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenAdmin_whenOverflowEnd_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        uint256 last = type(uint48).max;
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                last + _risk.gracePeriod()
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-A02, BLRISK-REENABLE-L01.
    function test_givenLoanAdmin_whenTransition(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-L02.
    function test_givenLoanAdminActive_whenAlreadyEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-L04.
    function test_givenLoanAdminInactive_whenAlreadyEnabled_reverts(
        address caller_
    ) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-L03.
    function test_givenLoanAdminInactive_whenTransition_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        _expectInactive();
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-D01.
    function test_givenLoanAdminOracleInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IBackingOracle).interfaceId)),
            abi.encode(false)
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-REENABLE-D02.
    function test_givenLoanAdminCacheInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        bytes4[3] memory interfaces = [
            type(IPriceCache).interfaceId,
            type(IEnabler).interfaceId,
            type(IVersioned).interfaceId
        ];
        for (uint256 i; i < interfaces.length; ++i) {
            _cache.setInterfaceSupport(interfaces[i], false);
            uint48 beforeTime = _risk.lastTransitionAt();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                    address(_cache)
                )
            );
            vm.prank(caller_);
            _risk.reEnable();
            assertFalse(_risk.isEnabled(), "failed activation remains disabled");
            assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
            _cache.setInterfaceSupport(interfaces[i], true);
        }
    }

    // Scenarios: BLRISK-REENABLE-D03.
    function test_givenLoanAdminCacheKernel_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_cache),
                address(_kernel),
                address(0xBAD)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenLoanAdminCache11_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenLoanAdminCache10_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenLoanAdminCache01_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D04.
    function test_givenLoanAdminCache00_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-D05.
    function test_givenLoanAdmin_whenDependencyRestored(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                address(_cache)
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, true);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N01.
    function test_givenLoanAdminNeverEnabled_whenReEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        BurnerLoansRisk fresh = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(_oracle),
            address(0),
            0,
            address(this)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenLoanAdmin_whenWithinGrace(
        address caller_,
        uint32 grace_,
        uint48 last_,
        uint48 now_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        uint48 last = uint48(bound(last_, 1, type(uint48).max - grace));
        _risk.setGracePeriod(grace);
        vm.warp(last);
        _risk.disable("");
        vm.warp(bound(now_, last, uint256(last) + grace));
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenLoanAdmin_whenAtDisable(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        _risk.disable("");
        vm.warp(uint256(_risk.lastTransitionAt()) + 0);
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N02.
    function test_givenLoanAdmin_whenAtDeadline(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        _risk.disable("");
        vm.warp(uint256(_risk.lastTransitionAt()) + _risk.gracePeriod());
        _transition(caller_);
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenLoanAdmin_whenGraceExpired_reverts(
        address caller_,
        uint48 now_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenLoanAdmin_whenAfterDeadline_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(uint256(deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N03.
    function test_givenLoanAdmin_whenMaxTimestamp_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint48 deadline = _risk.lastTransitionAt() + _risk.gracePeriod();
        vm.warp(type(uint48).max);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenLoanAdmin_whenDeadlineOverflows_reverts(
        address caller_,
        uint32 grace_,
        uint48 last_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint32 grace = uint32(bound(grace_, 1, type(uint32).max));
        _risk.setGracePeriod(grace);
        uint48 last = uint48(bound(last_, uint256(type(uint48).max) - grace + 1, type(uint48).max));
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last) + grace
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenLoanAdmin_whenOverflowStart_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint256 last = uint256(type(uint48).max) - _risk.gracePeriod() + 1;
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                last + _risk.gracePeriod()
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }

    // Scenarios: BLRISK-REENABLE-N04.
    function test_givenLoanAdmin_whenOverflowEnd_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        uint256 last = type(uint48).max;
        vm.warp(last);
        _risk.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                last + _risk.gracePeriod()
            )
        );
        vm.prank(caller_);
        _risk.reEnable();
    }
}
