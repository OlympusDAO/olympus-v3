// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries

// Contracts

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensIsSeizableTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-IS-SEIZABLE-L01.
    function test_givenActiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, true);
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-L02.
    function test_givenActiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, false);
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-L03.
    function test_givenInactiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, true);
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-L04.
    function test_givenInactiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, false);
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-I01.
    function test_whenUnknownAsset_reverts(address caller_) public {
        address asset = makeAddr("unknown asset");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.isSeizable(asset, _ALICE);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-I02.
    function test_whenZeroAsset_reverts(address caller_) public {
        address asset = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.isSeizable(asset, _ALICE);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P01.
    function test_givenNoPosition_whenQueried(address caller_) public {
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P06.
    function test_givenCollateralOnly_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 100e6, 0, 0, 0);
        _expectNoRiskReads();
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P02.
    function test_givenExactExpiry_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, 100_000, 1);
        vm.warp(100_000);
        _expectNoRiskReads();
        _assertSeizable(caller_, true);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P07.
    function test_givenPastExpiry_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, 100_000, 1);
        vm.warp(100_001);
        _expectNoRiskReads();
        _assertSeizable(caller_, true);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P08.
    function test_givenBeforeExpiry_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(2e18);
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P03.
    function test_givenZeroHealth_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(0);
        _assertSeizable(caller_, true);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-N01.
    function test_givenBelowOne_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(1e18 - 1);
        _assertSeizable(caller_, true);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P04.
    function test_givenExactlyOne_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(1e18);
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-P05.
    function test_givenAboveOne_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(1e18 + 1);
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-N02.
    function test_givenMaximumHealth_whenQueried(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(type(uint256).max);
        _assertSeizable(caller_, false);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-T01.
    function test_givenSnapshotFailure_whenQueried_reverts(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(2e18);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        vm.expectRevert(SnapshotReadFailed.selector);
        vm.prank(caller_);
        _lens.isSeizable(address(_asset), _ALICE);
    }

    // Scenarios: BLLENS-IS-SEIZABLE-T02.
    function test_givenHealthFailure_whenQueried_reverts(address caller_) public {
        _mockPosition(_ALICE, 1000e6, 100e9, uint48(block.timestamp + 1), 1);
        _mockRisk(2e18);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        vm.expectRevert(RiskHealthFailed.selector);
        vm.prank(caller_);
        _lens.isSeizable(address(_asset), _ALICE);
    }

    function _assertSeizable(address caller_, bool expected_) internal {
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(_lens.isSeizable(address(_asset), _ALICE), expected_, "Exact eligibility");
        assertEq(vm.getRecordedLogs().length, 0, "Eligibility emits no logs");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
