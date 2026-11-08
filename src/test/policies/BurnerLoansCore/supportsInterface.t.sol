// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";

contract BurnerLoansCoreSupportsInterfaceTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-ERC165-P01.
    function test_whenIBurnerLoansCoreQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IBurnerLoansCore).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P02.
    function test_whenIOperatorAuthQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IOperatorAuth).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P03.
    function test_whenIVersionedQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IVersioned).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P04.
    function test_whenIERC165Queried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IERC165).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P05.
    function test_whenIEnablerQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IEnabler).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P06.
    function test_whenIEnablerV2Queried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IEnablerV2).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P07.
    function test_whenIReEnablerQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IReEnabler).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P08.
    function test_whenIGracePeriodQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IGracePeriod).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P12.
    function test_whenIConfigOperatorQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.recordLogs();
        vm.prank(caller_);
        assertTrue(
            _core.supportsInterface(type(IConfigOperator).interfaceId),
            "Declared interface supported"
        );
        assertEq(_state(), before, "ERC165 has no effects");
        assertEq(vm.getRecordedLogs().length, 0, "ERC165 emits no logs");
    }

    // Scenarios: BLCORE-ERC165-P09.
    function test_whenInvalidInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        assertFalse(_core.supportsInterface(0xffffffff), "Reserved interface unsupported");
    }

    // Scenarios: BLCORE-ERC165-P10.
    function test_whenZeroInterfaceQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        assertFalse(_core.supportsInterface(0x00000000), "Reserved interface unsupported");
    }

    // Scenarios: BLCORE-ERC165-P11.
    function test_whenOtherInterfaceQueried(
        address caller_,
        bytes4 id_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(id_ != type(IBurnerLoansCore).interfaceId);
        vm.assume(id_ != type(IOperatorAuth).interfaceId);
        vm.assume(id_ != type(IConfigOperator).interfaceId);
        vm.assume(id_ != type(IVersioned).interfaceId);
        vm.assume(id_ != type(IERC165).interfaceId);
        vm.assume(id_ != type(IEnabler).interfaceId);
        vm.assume(id_ != type(IEnablerV2).interfaceId);
        vm.assume(id_ != type(IReEnabler).interfaceId);
        vm.assume(id_ != type(IGracePeriod).interfaceId);
        vm.assume(id_ != 0x00000000 && id_ != 0xffffffff);
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        assertFalse(_core.supportsInterface(id_), "No undeclared interface advertised");
    }
}
