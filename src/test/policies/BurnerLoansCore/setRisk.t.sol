// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSetRiskTest is BurnerLoansCoreTest {
    CoreService internal _next;

    function setUp() public override {
        super.setUp();
        _next = _service();
    }

    // Scenarios: BLCORE-RISK-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_, address candidate_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        bytes32 before = _state();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setRisk(candidate_);
        assertEq(_state(), before, "Unauthorized selection preserves the complete Core state");
    }

    // Scenarios: BLCORE-RISK-P04, BLCORE-RISK-P05.
    function test_givenCoreInactive_whenSelected_reverts(
        address caller_,
        bool enabled_,
        address candidate_
    ) public {
        _grantAdmin(caller_);
        _setCoreLifecycle(false, enabled_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        _core.setRisk(candidate_);
        assertEq(_state(), before, "Inactive Core does not probe or replace a service");
    }

    // Scenarios: BLCORE-RISK-P06.
    function test_whenCurrentAddressIsSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        address current = _core.risk();
        bytes32 before = _state();
        vm.mockCallRevert(
            current,
            abi.encodeWithSignature("core()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.mockCallRevert(
            current,
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                current
            )
        );
        vm.prank(caller_);
        _core.setRisk(current);
        assertEq(_state(), before, "Equality rejects before live compatibility reads");
    }

    // Scenarios: BLCORE-RISK-P01, BLCORE-RISK-P02, BLCORE-RISK-P03, BLCORE-RISK-D04.
    function test_givenCompatibleReadyService_whenSelected(address caller_, bool enabled_) public {
        _grantAdmin(caller_);
        _deposit(2000e6);
        _borrow(100e9);
        bytes32 ledger = _ledger();
        address previous = _core.risk();
        address operatorBefore = _next.configOperator();
        if (!enabled_) _core.disable("");
        vm.expectEmit(false, false, false, true, address(_core));
        emit IBurnerLoansCore.RiskSet(address(_next));
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_core.risk(), address(_next), "Selected pointer changes exactly");
        assertEq(_ledger(), ledger, "No token, position, principal or claim changes");
        assertEq(
            _next.configOperator(),
            operatorBefore,
            "Core does not change independent service authority"
        );
    }

    // Scenarios: BLCORE-RISK-D08, BLCORE-RISK-D06, BLCORE-RISK-D07.
    function test_givenServiceUnavailable_whenSelected_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _grantAdmin(caller_);
        if (!enabled_) _next.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_next));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Unavailable compatible candidate cannot replace the pointer");
    }

    // Scenarios: BLCORE-RISK-I01.
    function test_givenZero_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(0));
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-RISK-I02.
    function test_givenEOA_whenSelected_reverts(address caller_, address candidate_) public {
        _grantAdmin(caller_);
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                candidate_
            )
        );
        vm.prank(caller_);
        _core.setRisk(candidate_);
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-RISK-I03.
    function test_givenWrongKernel_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _next.changeKernel(other);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        _expectDependencyKernelMismatch(address(_next), address(other));
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I04.
    function test_givenServiceInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansRisk).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I05.
    function test_givenEnabledInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IEnabler).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I06.
    function test_givenVersionInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IVersioned).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I10.
    function test_givenOtherOhm_whenSelected_reverts(address caller_, address ohm_) public {
        _grantAdmin(caller_);
        vm.assume(ohm_ != address(_ohm));
        _next.setOhm(ohm_);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I11.
    function test_givenOtherCore_whenSelected_reverts(address caller_, address core_) public {
        _grantAdmin(caller_);
        vm.assume(core_ != address(_core));
        _next.setCore(core_);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I11.
    function test_givenZeroCoreBinding_whenSelected_reverts() public {
        test_givenOtherCore_whenSelected_reverts(_recipient, address(0));
    }

    // Scenarios: BLCORE-RISK-I12.
    function test_givenMissingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(address(_next), abi.encodeWithSignature("core()"), bytes(""));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I13.
    function test_givenMalformedCore_whenSelected_reverts(
        address caller_,
        uint16 length_,
        bool long_
    ) public {
        _grantAdmin(caller_);
        uint256 length = long_ ? bound(length_, 33, 256) : bound(length_, 0, 31);
        vm.mockCall(address(_next), abi.encodeWithSignature("core()"), new bytes(length));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I14.
    function test_givenRevertingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(
            address(_next),
            abi.encodeWithSignature("core()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I15.
    function test_givenRevertingERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(
            address(_next),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-I16.
    function test_givenMalformedERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(address(_next), abi.encodeWithSignature("supportsInterface(bytes4)"), hex"01");
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D09.
    function test_givenBoundInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansCoreBound).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D11.
    function test_givenDirtyCore_whenSelected_reverts(address caller_, uint96 padding_) public {
        _grantAdmin(caller_);
        padding_ = uint96(bound(padding_, 1, type(uint96).max));
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("core()"),
            abi.encode((uint256(padding_) << 160) | uint160(address(_core)))
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D12.
    function test_givenRevertingKernel_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(
            address(_next),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D13.
    function test_givenMalformedKernel_whenSelected_reverts(
        address caller_,
        uint16 length_,
        bool long_
    ) public {
        _grantAdmin(caller_);
        uint256 length = long_ ? bound(length_, 33, 256) : bound(length_, 0, 31);
        vm.mockCall(address(_next), abi.encodeWithSignature("kernel()"), new bytes(length));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D14.
    function test_givenRevertingEnabled_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(
            address(_next),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D15.
    function test_givenMalformedEnabled_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(address(_next), abi.encodeWithSignature("isEnabled()"), abi.encode(uint256(2)));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D16.
    function test_givenNoncanonicalERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansRisk).interfaceId
            ),
            abi.encode(uint256(2))
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D17.
    function test_givenWritingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setWriteIdentity(true);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D18.
    function test_givenLyingERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encode(true)
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D19.
    function test_givenBadBindingAndUnavailable_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setCore(address(0));
        _next.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_next));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setRisk(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-RISK-D01, BLCORE-RISK-P01, BLCORE-RISK-P02, BLCORE-RISK-P03.
    function test_givenIndependentRiskOperator_whenSelected(
        address operator_,
        bool enabled_
    ) public {
        _next.setConfigOperator(operator_);
        if (!enabled_) _core.disable("");
        bytes32 ledger = _ledger();
        address config = _core.configOperator();
        address inventoryOperator = _inventory.configOperator();
        address payoutOperator = _payout.configOperator();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IBurnerLoansCore.RiskSet(address(_next));
        _core.setRisk(address(_next));
        assertEq(_core.risk(), address(_next), "Risk selection is independent of its controller");
        assertEq(_next.configOperator(), operator_, "No controller synchronization");
        assertEq(_core.configOperator(), config, "Core authority unchanged");
        assertEq(_inventory.configOperator(), inventoryOperator, "Inventory authority unchanged");
        assertEq(_payout.configOperator(), payoutOperator, "Payout authority unchanged");
        assertEq(_ledger(), ledger, "Selection changes no loans");
    }

    // Scenarios: BLCORE-RISK-D02.
    function test_givenRevertingAuthorityGetters_whenSelected() public {
        vm.mockCallRevert(address(_next), abi.encodeWithSignature("configOperator()"), hex"01");
        vm.mockCallRevert(address(_next), abi.encodeWithSignature("configurator()"), hex"01");
        vm.expectCall(address(_next), abi.encodeWithSignature("configOperator()"), uint64(0));
        vm.expectCall(address(_next), abi.encodeWithSignature("configurator()"), uint64(0));
        _core.setRisk(address(_next));
        assertEq(_core.risk(), address(_next), "No Risk authority getter is consumed");
    }

    // Scenarios: BLCORE-RISK-D03.
    function test_givenMalformedAuthorityGetters_whenSelected() public {
        vm.mockCall(address(_next), abi.encodeWithSignature("configOperator()"), hex"01");
        vm.mockCall(address(_next), abi.encodeWithSignature("configurator()"), hex"01");
        vm.expectCall(address(_next), abi.encodeWithSignature("configOperator()"), uint64(0));
        vm.expectCall(address(_next), abi.encodeWithSignature("configurator()"), uint64(0));
        _core.setRisk(address(_next));
        assertEq(_core.risk(), address(_next), "No Risk authority getter is consumed");
    }

    // Scenarios: BLCORE-RISK-C01.
    function test_givenBusyCore_whenSelected_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("setRisk(address)", address(_next)),
            false
        );
        address before = _core.risk();
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized callback reaches Core guard"
        );
        assertEq(_core.risk(), before, "Callback cannot replace the selected service");
    }

    // Scenarios: BLCORE-RISK-D08, BLCORE-RISK-D06, BLCORE-RISK-D07.
    function test_whenUnavailableServiceStatesSeeded_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, true, false);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, true);
        vm.revertToState(snapshot);
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, false);
    }

    // Scenarios: BLCORE-RISK-I13.
    function test_whenCoreReturnLengthSeeds_reverts() public {
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 256];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_next), abi.encodeWithSignature("core()"), new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                    address(_next)
                )
            );
            _core.setRisk(address(_next));
        }
    }

    // Scenarios: BLCORE-RISK-D13.
    function test_whenKernelReturnLengthSeeds_reverts() public {
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 256];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_next), abi.encodeWithSignature("kernel()"), new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(_next)
                )
            );
            _core.setRisk(address(_next));
        }
    }

    // Scenarios: BLCORE-RISK-D13.
    function test_givenDirtyKernelPadding_whenSelected_reverts() public {
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("kernel()"),
            abi.encode((uint256(1) << 160) | uint160(address(_kernel)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_next)
            )
        );
        _core.setRisk(address(_next));
    }

    // Scenarios: BLCORE-RISK-D15.
    function test_whenEnabledReturnShapeSeeds_reverts() public {
        bytes[4] memory responses = [
            bytes(""),
            bytes(hex"01"),
            abi.encode(uint256(2)),
            new bytes(64)
        ];
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(_next), abi.encodeWithSignature("isEnabled()"), responses[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(_next)
                )
            );
            _core.setRisk(address(_next));
        }
    }

    // Scenarios: BLCORE-RISK-D11.
    function test_givenSingleDirtyCorePaddingBit_whenSelected_reverts() public {
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("core()"),
            abi.encode((uint256(1) << 160) | uint160(address(_core)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(_next)
            )
        );
        _core.setRisk(address(_next));
    }

    // Scenarios: BLCORE-RISK-D01, BLCORE-RISK-P01, BLCORE-RISK-P02, BLCORE-RISK-P03.
    function test_whenIndependentOperatorSeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenIndependentRiskOperator_whenSelected(address(0), true);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenIndependentRiskOperator_whenSelected(address(_config), false);
        vm.revertToState(snapshot);
        test_givenIndependentRiskOperator_whenSelected(_recipient, true);
    }
}
