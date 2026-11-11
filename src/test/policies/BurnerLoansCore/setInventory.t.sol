// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSetInventoryTest is BurnerLoansCoreTest {
    using stdStorage for StdStorage;
    CoreService internal _next;

    function setUp() public override {
        super.setUp();
        _next = _service();
    }

    // Scenarios: BLCORE-INVENTORY-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_, address candidate_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        bytes32 before = _state();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setInventory(candidate_);
        assertEq(_state(), before, "Unauthorized selection preserves the complete Core state");
    }

    // Scenarios: BLCORE-INVENTORY-L03, BLCORE-INVENTORY-L04.
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
        _core.setInventory(candidate_);
        assertEq(_state(), before, "Inactive Core does not probe or replace a service");
    }

    // Scenarios: BLCORE-INVENTORY-P02.
    function test_whenCurrentAddressIsSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        address current = _core.inventory();
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
        _core.setInventory(current);
        assertEq(_state(), before, "Equality rejects before live compatibility reads");
    }

    // Scenarios: BLCORE-INVENTORY-L01, BLCORE-INVENTORY-L02, BLCORE-INVENTORY-L05.
    function test_givenCompatibleReadyService_whenSelected(address caller_, bool enabled_) public {
        _grantAdmin(caller_);
        _deposit(2000e6);
        bytes32 ledger = _ledger();
        address previous = _core.inventory();
        address operatorBefore = _next.configOperator();
        if (!enabled_) _core.disable("");
        vm.expectEmit(true, false, false, true, address(_core));
        emit IBurnerLoansCore.InventorySet(address(_next));
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "Selected pointer changes exactly");
        assertEq(_ledger(), ledger, "No token, position, principal or claim changes");
        assertEq(
            _next.configOperator(),
            operatorBefore,
            "Core does not change independent service authority"
        );
    }

    // Scenarios: BLCORE-INVENTORY-L06, BLCORE-INVENTORY-D01, BLCORE-INVENTORY-D02.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Unavailable compatible candidate cannot replace the pointer");
    }

    // Scenarios: BLCORE-INVENTORY-I06.
    function test_givenZero_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(0));
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-INVENTORY-D04.
    function test_givenEOA_whenSelected_reverts(address caller_, address candidate_) public {
        _grantAdmin(caller_);
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                candidate_
            )
        );
        vm.prank(caller_);
        _core.setInventory(candidate_);
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-INVENTORY-D03.
    function test_givenWrongKernel_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _next.changeKernel(other);
        assertTrue(_kernel.isPolicyActive(_next), "Old Kernel retains stale membership");
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        _expectDependencyKernelMismatch(address(_next), address(other));
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D05.
    function test_givenServiceInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansInventory).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D06.
    function test_givenEnabledInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IEnabler).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D07.
    function test_givenVersionInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IVersioned).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-I02.
    function test_givenOtherOhm_whenSelected_reverts(address caller_, address ohm_) public {
        _grantAdmin(caller_);
        vm.assume(ohm_ != address(_ohm));
        _next.setOhm(ohm_);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-I01.
    function test_givenOtherCore_whenSelected_reverts(address caller_, address core_) public {
        _grantAdmin(caller_);
        vm.assume(core_ != address(_core));
        _next.setCore(core_);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D12.
    function test_givenMissingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(address(_next), abi.encodeWithSignature("core()"), bytes(""));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D11.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D10.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D08.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D09.
    function test_givenMalformedERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(address(_next), abi.encodeWithSignature("supportsInterface(bytes4)"), hex"01");
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D13.
    function test_givenBoundInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansCoreBound).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D15.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D16.
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
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D17.
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
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D18.
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
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D19.
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
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D20.
    function test_givenNoncanonicalERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansInventory).interfaceId
            ),
            abi.encode(uint256(2))
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D21.
    function test_givenWritingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setWriteIdentity(true);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D22.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-INVENTORY-D23.
    function test_givenBadBindingAndUnavailable_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setCore(address(0));
        _next.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_next));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setInventory(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: .
    function test_givenBusyCore_whenSelected_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("setInventory(address)", address(_next)),
            false
        );
        address before = _core.inventory();
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized callback reaches Core guard"
        );
        assertEq(_core.inventory(), before, "Callback cannot replace the selected service");
    }

    // Scenarios: BLCORE-INVENTORY-P01.
    function test_givenOldInventoryUnset_whenEmptyInventorySelected() public {
        stdstore.target(address(_core)).sig(bytes4(keccak256("inventory()"))).checked_write(
            address(0)
        );
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "First empty installation supported");
    }

    // Scenarios: BLCORE-INVENTORY-P03, BLCORE-INVENTORY-P04, BLCORE-INVENTORY-P05.
    function test_givenMigratedLedger_whenSelected(
        uint128 principal_,
        uint128 supplied_,
        uint128 idle_
    ) public {
        vm.assume(idle_ <= supplied_);
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature(
                "getFacilityPrincipalDue(address,address)",
                address(_core),
                address(_ohm)
            ),
            abi.encode(uint256(principal_))
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("activePrincipalOhm()"),
            abi.encode(principal_)
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("suppliedOhm()"),
            abi.encode(supplied_)
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("suppliedIdleOhm()"),
            abi.encode(idle_)
        );
        _next.setLedger(principal_, supplied_, idle_);
        _next.setProviderClaim(_borrower, supplied_);
        uint256 before = _ohm.balanceOf(address(_next));
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "Matching nonzero migrated ledgers accepted");
        assertEq(_next.activePrincipalOhm(), principal_, "Principal preserved");
        assertEq(_next.suppliedOhm(), supplied_, "Provider claims aggregate preserved");
        assertEq(_next.suppliedIdleOhm(), idle_, "Idle supply preserved");
        assertEq(_next.providerClaims(_borrower), supplied_, "Prepared individual claim untouched");
        assertEq(_ohm.balanceOf(address(_next)), before, "Core performs no migration transfers");
    }

    // Scenarios: BLCORE-INVENTORY-P03, BLCORE-INVENTORY-P04, BLCORE-INVENTORY-P05.
    function test_whenMigratedLedgerBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenMigratedLedger_whenSelected(0, 100e9, 0);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenMigratedLedger_whenSelected(60e9, 100e9, 40e9);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenMigratedLedger_whenSelected(0, 100e9, 100e9);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenMigratedLedger_whenSelected(1, 1, 1);
        vm.revertToState(snapshot);
        test_givenMigratedLedger_whenSelected(
            type(uint128).max,
            type(uint128).max,
            type(uint128).max
        );
    }

    // Scenarios: BLCORE-INVENTORY-I03.
    function test_givenCanonicalMismatch_whenInventorySelected_reverts() public {
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("activePrincipalOhm()"),
            abi.encode(uint128(0))
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("suppliedOhm()"),
            abi.encode(uint128(0))
        );
        _next.setLedger(1, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        _core.setInventory(address(_next));
        assertEq(
            _core.inventory(),
            address(_inventory),
            "Inconsistent migration cannot replace selection"
        );
    }

    // Scenarios: BLCORE-INVENTORY-I07.
    function test_givenOldPrincipalMismatch_whenInventorySelected_reverts() public {
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("activePrincipalOhm()"),
            abi.encode(uint128(1))
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("suppliedOhm()"),
            abi.encode(uint128(0))
        );
        _next.setLedger(0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        _core.setInventory(address(_next));
        assertEq(
            _core.inventory(),
            address(_inventory),
            "Inconsistent migration cannot replace selection"
        );
    }

    // Scenarios: BLCORE-INVENTORY-I08.
    function test_givenClaimMismatch_whenInventorySelected_reverts() public {
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("activePrincipalOhm()"),
            abi.encode(uint128(0))
        );
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("suppliedOhm()"),
            abi.encode(uint128(1))
        );
        _next.setLedger(0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        _core.setInventory(address(_next));
        assertEq(
            _core.inventory(),
            address(_inventory),
            "Inconsistent migration cannot replace selection"
        );
    }

    // Scenarios: BLCORE-INVENTORY-L06, BLCORE-INVENTORY-D01, BLCORE-INVENTORY-D02.
    function test_whenUnavailableServiceStatesSeeded_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, true, false);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, true);
        vm.revertToState(snapshot);
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, false);
    }

    // Scenarios: BLCORE-INVENTORY-D11.
    function test_whenCoreReturnLengthSeeds_reverts() public {
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 256];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_next), abi.encodeWithSignature("core()"), new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                    address(_next)
                )
            );
            _core.setInventory(address(_next));
        }
    }

    // Scenarios: BLCORE-INVENTORY-D17.
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
            _core.setInventory(address(_next));
        }
    }

    // Scenarios: BLCORE-INVENTORY-D17.
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
        _core.setInventory(address(_next));
    }

    // Scenarios: BLCORE-INVENTORY-D19.
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
            _core.setInventory(address(_next));
        }
    }

    // Scenarios: BLCORE-INVENTORY-D15.
    function test_givenSingleDirtyCorePaddingBit_whenSelected_reverts() public {
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("core()"),
            abi.encode((uint256(1) << 160) | uint160(address(_core)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(_next)
            )
        );
        _core.setInventory(address(_next));
    }

    // Scenarios: BLCORE-INVENTORY-P03.
    function test_givenDefaultedProviderClaims_whenInventorySelected() public {
        _supplyInventory(_borrower, 100e9);
        _deposit(2000e6);
        _borrow(100e9);
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        vm.prank(address(_liquidation));
        _core.settleSeize(
            address(_asset),
            borrowers,
            _recipient,
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18)
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Default clears active principal");
        assertEq(_inventory.suppliedOhm(), 100e9, "Default preserves historical provider claim");
        assertEq(_inventory.suppliedIdleOhm(), 0, "Default leaves no idle recapitalization");
        _next.setLedger(0, 100e9, 0);
        _next.setProviderClaim(_borrower, 100e9);
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "Prepared Inventory is selected");
        assertEq(
            _next.providerClaims(_borrower),
            100e9,
            "Matching completed migration preserves provider claim"
        );
        assertEq(_ohm.balanceOf(address(_next)), 0, "Pointer selection mints no recapitalization");
    }

    // Scenarios: BLCORE-INVENTORY-P04.
    function test_givenMigratedTwoProviderLedger_whenInventorySelected() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        _supplyInventory(alice, 70e9);
        _supplyInventory(bob, 30e9);
        _deposit(2000e6);
        _borrow(60e9);
        // Governance completed the migration before selection; Core is not a migration mechanism.
        vm.prank(address(_inventory));
        _ohm.transfer(address(_next), 40e9);
        _next.setLedger(60e9, 100e9, 40e9);
        _next.setProviderClaim(alice, 70e9);
        _next.setProviderClaim(bob, 30e9);
        bytes32 position = keccak256(abi.encode(_position()));
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "Prepared Inventory is selected");
        assertEq(_next.activePrincipalOhm(), 60e9, "Migrated principal preserved");
        assertEq(_next.suppliedOhm(), 100e9, "Aggregate provider claims preserved");
        assertEq(_next.suppliedIdleOhm(), 40e9, "Migrated idle supply preserved");
        assertEq(_next.providerClaims(alice), 70e9, "Alice claim preserved");
        assertEq(_next.providerClaims(bob), 30e9, "Bob claim preserved");
        assertEq(
            _ohm.balanceOf(address(_next)),
            40e9,
            "Core performs no transfer after prepared migration"
        );
        assertEq(keccak256(abi.encode(_position())), position, "Canonical loan unchanged");
    }

    // Scenarios: BLCORE-INVENTORY-P05.
    function test_givenMigratedIdleProviderFunds_whenInventorySelected() public {
        _supplyInventory(_borrower, 100e9);
        vm.prank(address(_inventory));
        _ohm.transfer(address(_next), 100e9);
        _next.setLedger(0, 100e9, 100e9);
        _next.setProviderClaim(_borrower, 100e9);
        _core.setInventory(address(_next));
        assertEq(_core.inventory(), address(_next), "Prepared Inventory is selected");
        assertEq(_next.providerClaims(_borrower), 100e9, "Idle claim retained");
        assertEq(_ohm.balanceOf(address(_next)), 100e9, "Idle backing preserved");
        assertEq(_core.totalActiveDebtOhm(), 0, "No debt created by selection");
    }
}
