// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

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

contract BurnerLoansCoreSetPayoutTest is BurnerLoansCoreTest {
    CoreService internal _next;

    function setUp() public override {
        super.setUp();
        _next = _service();
    }

    // Scenarios: BLCORE-CUSTODY-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_, address candidate_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        bytes32 before = _state();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setPayout(candidate_);
        assertEq(_state(), before, "Unauthorized selection preserves the complete Core state");
    }

    // Scenarios: BLCORE-CUSTODY-P04, BLCORE-CUSTODY-P05.
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
        _core.setPayout(candidate_);
        assertEq(_state(), before, "Inactive Core does not probe or replace a service");
    }

    // Scenarios: BLCORE-CUSTODY-P06.
    function test_whenCurrentAddressIsSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        address current = _core.payout();
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
        _core.setPayout(current);
        assertEq(_state(), before, "Equality rejects before live compatibility reads");
    }

    // Scenarios: BLCORE-CUSTODY-P01, BLCORE-CUSTODY-P02, BLCORE-CUSTODY-P03, BLCORE-CUSTODY-D01.
    function test_givenCompatibleReadyService_whenSelected(address caller_, bool enabled_) public {
        _grantAdmin(caller_);
        _deposit(2000e6);
        _borrow(100e9);
        bytes32 ledger = _ledger();
        address previous = _core.payout();
        address operatorBefore = _next.configOperator();
        if (!enabled_) _core.disable("");
        vm.expectEmit(true, true, false, true, address(_core));
        emit IBurnerLoansCore.PayoutSet(previous, address(_next));
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_core.payout(), address(_next), "Selected pointer changes exactly");
        assertEq(_ledger(), ledger, "No token, position, principal or claim changes");
        assertEq(
            _next.configOperator(),
            operatorBefore,
            "Core does not change independent service authority"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D06, BLCORE-CUSTODY-D03, BLCORE-CUSTODY-D04.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Unavailable compatible candidate cannot replace the pointer");
    }

    // Scenarios: BLCORE-CUSTODY-I01.
    function test_givenZero_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(0));
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-CUSTODY-I02.
    function test_givenEOA_whenSelected_reverts(address caller_, address candidate_) public {
        _grantAdmin(caller_);
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                candidate_
            )
        );
        vm.prank(caller_);
        _core.setPayout(candidate_);
        assertEq(_state(), before, "Invalid address preserves the selection and accounting");
    }

    // Scenarios: BLCORE-CUSTODY-D05.
    function test_givenWrongKernel_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _next.changeKernel(other);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        _expectDependencyKernelMismatch(address(_next), address(other));
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I04.
    function test_givenServiceInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansPayout).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I08.
    function test_givenEnabledInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IEnabler).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I09.
    function test_givenVersionInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IVersioned).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I03.
    function test_givenOtherCore_whenSelected_reverts(address caller_, address core_) public {
        _grantAdmin(caller_);
        vm.assume(core_ != address(_core));
        _next.setCore(core_);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I05.
    function test_givenMissingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCallRevert(address(_next), abi.encodeWithSignature("core()"), bytes(""));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I06.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I07.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I10.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-I11.
    function test_givenMalformedERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(address(_next), abi.encodeWithSignature("supportsInterface(bytes4)"), hex"01");
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D07.
    function test_givenBoundInterface_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setUnsupportedInterface(type(IBurnerLoansCoreBound).interfaceId);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D09.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D10.
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
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D11.
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
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D12.
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
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D13.
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
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D14.
    function test_givenNoncanonicalERC165_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansPayout).interfaceId
            ),
            abi.encode(uint256(2))
        );
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D15.
    function test_givenWritingCore_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setWriteIdentity(true);
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D16.
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
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-D17.
    function test_givenBadBindingAndUnavailable_whenSelected_reverts(address caller_) public {
        _grantAdmin(caller_);
        _next.setCore(address(0));
        _next.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_next));
        bytes32 before = _state();
        uint256 writes = _next.identityWrites();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_state(), before, "Invalid metadata leaves all Core state unchanged");
        assertEq(
            _next.identityWrites(),
            writes,
            "Compatibility probes cannot write candidate storage"
        );
    }

    // Scenarios: BLCORE-CUSTODY-C01.
    function test_givenBusyCore_whenSelected_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("setPayout(address)", address(_next)),
            false
        );
        address before = _core.payout();
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized callback reaches Core guard"
        );
        assertEq(_core.payout(), before, "Callback cannot replace the selected service");
    }

    // Scenarios: BLCORE-CUSTODY-D06, BLCORE-CUSTODY-D03, BLCORE-CUSTODY-D04.
    function test_whenUnavailableServiceStatesSeeded_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, true, false);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, true);
        vm.revertToState(snapshot);
        test_givenServiceUnavailable_whenSelected_reverts(_recipient, false, false);
    }

    // Scenarios: BLCORE-CUSTODY-I06.
    function test_whenCoreReturnLengthSeeds_reverts() public {
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 256];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_next), abi.encodeWithSignature("core()"), new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                    address(_next)
                )
            );
            _core.setPayout(address(_next));
        }
    }

    // Scenarios: BLCORE-CUSTODY-D11.
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
            _core.setPayout(address(_next));
        }
    }

    // Scenarios: BLCORE-CUSTODY-D11.
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
        _core.setPayout(address(_next));
    }

    // Scenarios: BLCORE-CUSTODY-D13.
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
            _core.setPayout(address(_next));
        }
    }

    // Scenarios: BLCORE-CUSTODY-D09.
    function test_givenSingleDirtyCorePaddingBit_whenSelected_reverts() public {
        vm.mockCall(
            address(_next),
            abi.encodeWithSignature("core()"),
            abi.encode((uint256(1) << 160) | uint160(address(_core)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(_next)
            )
        );
        _core.setPayout(address(_next));
    }

    // Scenarios: BLCORE-CUSTODY-P01, BLCORE-CUSTODY-P02, BLCORE-CUSTODY-P03.
    function test_givenOldPendingObligations_whenPayoutSelected(
        address caller_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        _deposit(2000e6);
        _borrow(100e9);
        address treasury = _payout.treasury();
        _asset.mint(address(_payout), 25);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", treasury),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", _recipient),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_asset), 17);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_asset), _recipient, 3, 5);
        if (!enabled_) _core.disable("");
        bytes32 ledger = _ledger();
        uint256 allowance = _asset.allowance(_borrower, address(_core));
        vm.expectEmit(true, true, false, true, address(_core));
        emit IBurnerLoansCore.PayoutSet(address(_payout), address(_next));
        vm.prank(caller_);
        _core.setPayout(address(_next));
        assertEq(_ledger(), ledger, "Pointer replacement preserves all old custody and loans");
        (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(fee, 17, "Old fee bucket retained");
        assertEq(seized, 5, "Old Treasury bucket retained");
        assertEq(total, 25, "Old aggregate includes original keeper reward");
        assertEq(
            _payout.pendingPayout(address(_asset), _recipient),
            3,
            "Original keeper entitlement retained"
        );
        assertEq(
            _asset.allowance(_borrower, address(_core)),
            allowance,
            "Selection creates no token approval"
        );
        vm.clearMockedCalls();
        assertEq(
            _payout.transferPendingPayout(address(_asset), treasury),
            22,
            "Retired Payout can service old fee and Treasury claims"
        );
        assertEq(
            _payout.transferPendingPayout(address(_asset), _recipient),
            3,
            "Retired Payout can service original keeper"
        );
        (, , total) = _payout.payoutReserves(address(_asset));
        assertEq(total, 0, "All old obligations settle exactly once");
    }
}
