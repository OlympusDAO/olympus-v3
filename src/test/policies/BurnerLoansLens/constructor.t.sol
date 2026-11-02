// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces

import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";

// Libraries

// Contracts

import {BurnerLoansLens} from "src/policies/burnerloans/BurnerLoansLens.sol";

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensConstructorTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-CONSTRUCTOR-I01.
    function test_givenZeroCore_whenDeployed_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        new BurnerLoansLens(address(0));
    }

    // Scenarios: BLLENS-CONSTRUCTOR-I02.
    function test_givenEoaCore_whenDeployed_reverts(address caller_) public {
        address candidate = makeAddr("EOA Core");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate
            )
        );
        vm.prank(caller_);
        new BurnerLoansLens(candidate);
    }

    // Scenarios: BLLENS-CONSTRUCTOR-I05.
    function test_givenIncompatibleCore_whenDeployed_reverts(address caller_) public {
        address candidate = address(_asset);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate
            )
        );
        vm.prank(caller_);
        new BurnerLoansLens(candidate);
    }

    // Scenarios: BLLENS-CONSTRUCTOR-I03.
    function test_givenRevertingInterface_whenDeployed_reverts(address caller_) public {
        address candidate = address(_core);
        vm.mockCallRevert(
            candidate,
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate
            )
        );
        vm.prank(caller_);
        new BurnerLoansLens(candidate);
    }

    // Scenarios: BLLENS-CONSTRUCTOR-I04.
    function test_givenMalformedInterface_whenDeployed_reverts(address caller_) public {
        address candidate = address(_core);
        vm.mockCall(candidate, abi.encodeWithSelector(IERC165.supportsInterface.selector), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate
            )
        );
        vm.prank(caller_);
        new BurnerLoansLens(candidate);
    }

    // Scenarios: BLLENS-CONSTRUCTOR-P02.
    function test_givenActiveEnabledCore_whenDeployed(address caller_) public {
        _setCoreLifecycle(true, true);
        vm.recordLogs();
        vm.prank(caller_);
        BurnerLoansLens lens = new BurnerLoansLens(address(_core));
        assertEq(lens.core(), address(_core), "Exact immutable binding");
        assertEq(_ohm.allowance(address(lens), address(_inventory)), 0, "No token approval");
        assertEq(vm.getRecordedLogs().length, 0, "Deployment emits no logs");
        vm.etch(address(_core), hex"");
        assertEq(lens.core(), address(_core), "Binding getter makes no dependency read");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-L01.
    function test_givenActiveDisabledCore_whenDeployed(address caller_) public {
        _setCoreLifecycle(true, false);
        vm.recordLogs();
        vm.prank(caller_);
        BurnerLoansLens lens = new BurnerLoansLens(address(_core));
        assertEq(lens.core(), address(_core), "Exact immutable binding");
        assertEq(_ohm.allowance(address(lens), address(_inventory)), 0, "No token approval");
        assertEq(vm.getRecordedLogs().length, 0, "Deployment emits no logs");
        vm.etch(address(_core), hex"");
        assertEq(lens.core(), address(_core), "Binding getter makes no dependency read");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-L02.
    function test_givenInactiveEnabledCore_whenDeployed(address caller_) public {
        _setCoreLifecycle(false, true);
        vm.recordLogs();
        vm.prank(caller_);
        BurnerLoansLens lens = new BurnerLoansLens(address(_core));
        assertEq(lens.core(), address(_core), "Exact immutable binding");
        assertEq(_ohm.allowance(address(lens), address(_inventory)), 0, "No token approval");
        assertEq(vm.getRecordedLogs().length, 0, "Deployment emits no logs");
        vm.etch(address(_core), hex"");
        assertEq(lens.core(), address(_core), "Binding getter makes no dependency read");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-L03.
    function test_givenInactiveDisabledCore_whenDeployed(address caller_) public {
        _setCoreLifecycle(false, false);
        vm.recordLogs();
        vm.prank(caller_);
        BurnerLoansLens lens = new BurnerLoansLens(address(_core));
        assertEq(lens.core(), address(_core), "Exact immutable binding");
        assertEq(_ohm.allowance(address(lens), address(_inventory)), 0, "No token approval");
        assertEq(vm.getRecordedLogs().length, 0, "Deployment emits no logs");
        vm.etch(address(_core), hex"");
        assertEq(lens.core(), address(_core), "Binding getter makes no dependency read");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
