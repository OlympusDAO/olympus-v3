// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries

// Contracts

import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";

import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensPositionHealthFactorTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-POSITION-HEALTH-L01.
    function test_givenActiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, true);
        _mockRisk(7e17);
        _assertHealth(caller_, 123, 456, 7e17);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-L02.
    function test_givenActiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, false);
        _mockRisk(7e17);
        _assertHealth(caller_, 123, 456, 7e17);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-L03.
    function test_givenInactiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, true);
        _mockRisk(7e17);
        _assertHealth(caller_, 123, 456, 7e17);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-L04.
    function test_givenInactiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, false);
        _mockRisk(7e17);
        _assertHealth(caller_, 123, 456, 7e17);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I01.
    function test_givenZeroAsset_whenDebtIsZero(address caller_) public {
        _expectNoRiskReads();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(0), 1, 0),
            type(uint256).max,
            "Debt-free health needs no reads"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P03.
    function test_givenUnknownAsset_whenDebtIsZero(address caller_) public {
        _expectNoRiskReads();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(makeAddr("unknown asset"), 1, 0),
            type(uint256).max,
            "Debt-free health needs no reads"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P04.
    function test_givenUnavailablePrice_whenDebtIsZero(address caller_) public {
        _expectNoRiskReads();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_asset), 1, 0),
            type(uint256).max,
            "Debt-free health needs no reads"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N01.
    function test_givenZeroCollateral_whenDebtIsZero(address caller_) public {
        _expectNoRiskReads();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_asset), 0, 0),
            type(uint256).max,
            "Debt-free health needs no reads"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N02.
    function test_givenMaximumCollateral_whenDebtIsZero(address caller_) public {
        _expectNoRiskReads();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_asset), type(uint256).max, 0),
            type(uint256).max,
            "Debt-free health needs no reads"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I02.
    function test_whenZeroDebtBearingAsset_reverts(address caller_) public {
        address asset = address(0);
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (asset)),
            abi.encode(_snapshot())
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.positionHealthFactor(asset, 1, 1);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I03.
    function test_whenUnknownDebtBearingAsset_reverts(address caller_) public {
        address asset = makeAddr("unknown asset");
        vm.mockCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (asset)),
            abi.encode(_snapshot())
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
        vm.prank(caller_);
        _lens.positionHealthFactor(asset, 1, 1);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P05.
    function test_givenArbitrary_whenHealthForwarded(address caller_) public {
        _mockRisk(7e17);
        _assertHealth(caller_, 123, 456, 7e17);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N03.
    function test_givenMaximumCollateral_whenHealthForwarded(address caller_) public {
        _mockRisk(11);
        _assertHealth(caller_, type(uint256).max, 1, 11);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N04.
    function test_givenMaximumDebt_whenHealthForwarded(address caller_) public {
        _mockRisk(13);
        _assertHealth(caller_, 1, type(uint256).max, 13);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N05.
    function test_givenMaximumHealth_whenHealthForwarded(address caller_) public {
        _mockRisk(type(uint256).max);
        _assertHealth(caller_, 1, 1, type(uint256).max);
    }

    function test_whenFullNumericRangeForwarded(
        address caller_,
        uint256 collateral_,
        uint256 debt_,
        uint256 health_
    ) public {
        vm.assume(debt_ != 0);
        _mockRisk(health_);
        _assertHealth(caller_, collateral_, debt_, health_);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-T01.
    function test_givenSnapshotFailure_whenQuoted_reverts(address caller_) public {
        _mockRisk(7e17);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
        vm.expectRevert(SnapshotReadFailed.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_asset), 123, 456);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-T02.
    function test_givenHealthFailure_whenQuoted_reverts(address caller_) public {
        _mockRisk(7e17);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        vm.expectRevert(RiskHealthFailed.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_asset), 123, 456);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P08.
    function test_givenReplacementRisk_whenQuoted(address caller_) public {
        BurnerLoansRisk replacement = _replaceRisk();
        vm.mockCall(
            address(replacement),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            abi.encode(_snapshot())
        );
        vm.mockCall(
            address(replacement),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(uint256(9e17))
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            uint64(0)
        );
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_asset), 123, 456),
            9e17,
            "Currently selected Risk is used"
        );
    }

    function _assertHealth(
        address caller_,
        uint256 collateral_,
        uint256 debt_,
        uint256 health_
    ) internal {
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            uint64(1)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.health,
                (_snapshot(), _core.marketId(address(_asset)), collateral_, debt_)
            ),
            uint64(1)
        );
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_asset), collateral_, debt_),
            health_,
            "Exact Risk handoff"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Health emits no logs");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
