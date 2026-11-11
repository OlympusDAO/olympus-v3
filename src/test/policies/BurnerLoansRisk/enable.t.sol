// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskEnableTest is BurnerLoansRiskTest {
    function _transition(address caller_) private {
        bytes32 beforeConfig = _configurationHash();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(_risk));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.recordLogs();
        vm.prank(caller_);
        _risk.enable("");
        assertEq(vm.getRecordedLogs().length, 2, "exact lifecycle event count");
        assertEq(_risk.isEnabled(), true, "transition flag");
        assertEq(_risk.lastTransitionAt(), vm.getBlockTimestamp(), "transition time");
        assertEq(
            _configurationHash(),
            beforeConfig,
            "transition preserves configuration and token supply"
        );
    }

    // Scenarios: BLRISK-ENABLE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(this));
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.enable("");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed transition preserves time");
        assertEq(_risk.isEnabled(), false, "failed transition preserves flag");
    }

    // Scenarios: BLRISK-ENABLE-A02, BLRISK-ENABLE-L01.
    function test_givenAdmin_whenTransition(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-L02.
    function test_givenAdminActive_whenAlreadyEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-L04.
    function test_givenAdminInactive_whenAlreadyEnabled_reverts(
        address caller_
    ) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-L03.
    function test_givenAdminInactive_whenTransition_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _expectInactive();
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-I01.
    function test_givenAdmin_whenDataIsNonempty_reverts(
        address caller_,
        bytes memory data_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.assume(data_.length > 0 && data_.length <= 256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _risk.enable(data_);
    }

    // Scenarios: BLRISK-ENABLE-I01.
    function test_givenAdmin_whenPayloadBoundarySeeds_reverts(
        address caller_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        bytes[4] memory seeds = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < seeds.length; ++i) {
            vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
            vm.prank(caller_);
            _risk.enable(seeds[i]);
        }
    }

    // Scenarios: BLRISK-ENABLE-D01.
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
        _risk.enable("");
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-ENABLE-D02.
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
            _risk.enable("");
            assertFalse(_risk.isEnabled(), "failed activation remains disabled");
            assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
            _cache.setInterfaceSupport(interfaces[i], true);
        }
    }

    // Scenarios: BLRISK-ENABLE-D03.
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
        _risk.enable("");
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-ENABLE-D04.
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

    // Scenarios: BLRISK-ENABLE-D04.
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

    // Scenarios: BLRISK-ENABLE-D04.
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

    // Scenarios: BLRISK-ENABLE-D04.
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

    // Scenarios: BLRISK-ENABLE-D05.
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
        _risk.enable("");
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, true);
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-K03.
    function test_givenMalformedCoreKernel_whenActivated_revertsThenRestored(
        bytes memory data_
    ) public {
        _risk.disable("");
        vm.assume(data_.length != 32);
        vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), data_);
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(this)
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-K03.
    function test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored() public {
        _risk.disable("");
        bytes[6] memory responses = [
            new bytes(0),
            new bytes(1),
            new bytes(31),
            new bytes(33),
            new bytes(64),
            abi.encode(type(uint256).max)
        ];
        // Every response must fail with the same owned error and preserve state.
        // forge-lint: disable-next-line(calls-loop)
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), responses[i]);
            _expectCoreRejected(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(this)
                )
            );
        }
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-K01.
    function test_givenDifferentCoreKernel_whenActivated_revertsThenRestored() public {
        _risk.disable("");
        address otherKernel = address(new Kernel());
        vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), abi.encode(otherKernel));
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(this),
                address(_kernel),
                otherKernel
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-K02.
    function test_givenRevertingCoreKernel_whenActivated_revertsThenRestored(
        bytes memory data_
    ) public {
        _risk.disable("");
        vm.mockCallRevert(address(this), abi.encodeWithSignature("kernel()"), data_);
        _expectCoreRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(this)
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-I20.
    function test_givenMissingCoreInterface_whenActivated_revertsThenRestored() public {
        _risk.disable("");
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(this), probe, abi.encode(false));
        vm.mockCallRevert(address(this), abi.encodeWithSignature("kernel()"), hex"01");
        _expectCoreRejected(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-I21.
    function test_givenRevertingCoreInterface_whenActivated_revertsThenRestored() public {
        _risk.disable("");
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(
            address(this),
            probe,
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _expectCoreRejected(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-I22.
    function test_givenMalformedCoreInterface_whenActivated_revertsThenRestored() public {
        _risk.disable("");
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(this), probe, hex"01");
        _expectCoreRejected(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        vm.clearMockedCalls();
        _transition(address(this));
    }

    function _expectCoreRejected(bytes memory reason_) private {
        bytes32 configuration = _configurationHash();
        uint48 transition = _risk.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(reason_);
        _risk.enable("");
        assertFalse(_risk.isEnabled(), "Rejected activation preserves paused state");
        assertEq(_risk.lastTransitionAt(), transition, "Rejected activation preserves history");
        assertEq(
            _configurationHash(),
            configuration,
            "Rejected activation preserves configuration"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected activation emits no events");
    }

    // Scenarios: BLRISK-ENABLE-K05.
    function test_givenCoreLifecycle_whenCompatible(
        bool active_,
        bool enabled_
    ) public givenDisabled {
        _mockCoreReadiness(active_, enabled_);
        _transition(address(this));
    }

    // Scenarios: BLRISK-ENABLE-K05.
    function test_whenCoreLifecycleSeeds() public {
        _expectNoCoreReadinessReads();
        for (uint8 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreLifecycle_whenCompatible(flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToState(checkpoint), "Restores lifecycle seed state");
        }
    }

    // Scenarios: BLRISK-ENABLE-D06.
    function test_givenBackingUnavailable_whenConsumed_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _risk.disable("");
        _oracle.setEnabled(enabled_);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_oracle)
            )
        );
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-D07.
    function test_givenBackingLifecycleBoundaries_whenConsumed_reverts() public {
        uint256 initial = vm.snapshotState();
        test_givenBackingUnavailable_whenConsumed_reverts(true, false);
        vm.revertToState(initial);
        test_givenBackingUnavailable_whenConsumed_reverts(false, true);
        vm.revertToState(initial);
        test_givenBackingUnavailable_whenConsumed_reverts(false, false);
    }

    // Scenarios: BLRISK-ENABLE-D08.
    function test_givenBackingForeignKernel_whenAdmitted_reverts() public {
        _risk.disable("");
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_oracle),
                address(_kernel),
                address(0xBAD)
            )
        );
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-D09.
    function test_givenBackingMalformedKernel_whenAdmitted_reverts() public {
        _risk.disable("");
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_oracle)
            )
        );
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-D10.
    function test_givenBackingMissingEnabler_whenAdmitted_reverts() public {
        _risk.disable("");
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IEnabler).interfaceId)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        _risk.enable("");
    }
}
