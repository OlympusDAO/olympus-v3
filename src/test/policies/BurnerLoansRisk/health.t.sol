// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskHealthTest is BurnerLoansRiskTest {
    function _assertHealthy(uint256 collateral_, uint256 backing_, uint256 expected_) internal {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            2e18,
            1e18,
            backing_
        );
        uint32 market = _MARKET;
        assertEq(
            _risk.health(snapshot, market, collateral_, 1e9),
            expected_,
            "Raw health uses independent expected value"
        );
        assertEq(
            _risk.validateHealth(snapshot, market, collateral_, 1e9, false),
            expected_,
            "Current position health is accepted"
        );
        assertEq(
            _risk.validateHealth(snapshot, market, collateral_, 1e9, true),
            expected_,
            "Final position health is accepted"
        );
    }

    function _assertUnhealthy(uint256 collateral_, uint256 backing_, uint256 expected_) internal {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            2e18,
            1e18,
            backing_
        );
        uint32 market = _MARKET;
        assertEq(
            _risk.health(snapshot, market, collateral_, 1e9),
            expected_,
            "Raw health permits an unhealthy quote"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector,
                expected_
            )
        );
        _risk.validateHealth(snapshot, market, collateral_, 1e9, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                expected_
            )
        );
        _risk.validateHealth(snapshot, market, collateral_, 1e9, true);
    }

    // Scenarios: BLRISK-HEALTH-N03.
    function test_givenMarketRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation()
        public
    {
        // 1 OHM (9 decimals) * $2 / 100% LTV = $2; backing requirement = $1.
        // 1,999,999 raw collateral / 1e6 = $1.999999. $1.999999 / $2 = 0.9999995 WAD.
        _assertUnhealthy(1999999, 1e18, 999999500000000000);
    }

    // Scenarios: BLRISK-HEALTH-P04.
    function test_givenMarketRequirementBinds_whenCollateralEqualsRequirement() public {
        // $2 collateral / max($2 market,$1 backing) = 1 WAD.
        _assertHealthy(2000000, 1e18, 1000000000000000000);
    }

    // Scenarios: BLRISK-HEALTH-N04.
    function test_givenMarketRequirementBinds_whenCollateralIsOneUnitAbove() public {
        // $2.000001 / $2 = 1.0000005 WAD.
        _assertHealthy(2000001, 1e18, 1000000500000000000);
    }

    // Scenarios: BLRISK-HEALTH-N05.
    function test_givenRequirementsEqual_whenCollateralIsOneUnitBelow_revertsValidation() public {
        // Both requirements are $2. $1.999999 / $2 = 0.9999995 WAD.
        _assertUnhealthy(1999999, 2e18, 999999500000000000);
    }

    // Scenarios: BLRISK-HEALTH-P05.
    function test_givenRequirementsEqual_whenCollateralEqualsRequirement() public {
        // $2 / max($2,$2) = 1 WAD.
        _assertHealthy(2000000, 2e18, 1000000000000000000);
    }

    // Scenarios: BLRISK-HEALTH-N06.
    function test_givenRequirementsEqual_whenCollateralIsOneUnitAbove() public {
        // $2.000001 / $2 = 1.0000005 WAD.
        _assertHealthy(2000001, 2e18, 1000000500000000000);
    }

    // Scenarios: BLRISK-HEALTH-N07.
    function test_givenBackingRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation()
        public
    {
        // Market requires $2; backing requires $3. floor($2.999999 / $3 * 1e18).
        // 2,999,999 * 1e18 / 3,000,000 = 999999666666666666 remainder 2000000.
        _assertUnhealthy(2999999, 3e18, 999999666666666666);
    }

    // Scenarios: BLRISK-HEALTH-P06.
    function test_givenBackingRequirementBinds_whenCollateralEqualsRequirement() public {
        // $3 / max($2,$3) = 1 WAD.
        _assertHealthy(3000000, 3e18, 1000000000000000000);
    }

    // Scenarios: BLRISK-HEALTH-N08.
    function test_givenBackingRequirementBinds_whenCollateralIsOneUnitAbove() public {
        // 3,000,001 * 1e18 / 3,000,000 = 1000000333333333333 remainder 1000000.
        _assertHealthy(3000001, 3e18, 1000000333333333333);
    }

    // Scenarios: BLRISK-HEALTH-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        assertEq(_risk.health(_prices(), _MARKET, 1e6, 1e9), 1e18, "healthy boundary");
        assertEq(
            _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, false),
            1e18,
            "current boundary"
        );
        assertEq(_risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, true), 1e18, "final boundary");
    }

    // Scenarios: BLRISK-HEALTH-L02.
    function test_givenDisabled_whenCalled_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.health(_prices(), _MARKET, 1e6, 1e9);
    }

    // Scenarios: BLRISK-HEALTH-L03.
    function test_givenInactive_whenCalled_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.health(_prices(), _MARKET, 1e6, 1e9);
    }

    // Scenarios: BLRISK-HEALTH-L04.
    function test_givenInactiveAndDisabled_whenCalled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.health(_prices(), _MARKET, 1e6, 1e9);
    }

    // Scenarios: BLRISK-HEALTH-L01.
    function test_givenReEnabled_whenCalled(address caller_) public givenReEnabled {
        vm.prank(caller_);
        assertEq(_risk.health(_prices(), _MARKET, 1e6, 1e9), 1e18, "healthy boundary");
        assertEq(
            _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, false),
            1e18,
            "current boundary"
        );
        assertEq(_risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, true), 1e18, "final boundary");
    }

    // Scenarios: BLRISK-HEALTH-L02.
    function test_givenDisabled_whenHealthValidated_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, true);
    }

    // Scenarios: BLRISK-HEALTH-L03.
    function test_givenInactive_whenHealthValidated_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, false);
        _expectInactive();
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, true);
    }

    // Scenarios: BLRISK-HEALTH-L04.
    function test_givenInactiveAndDisabled_whenHealthValidated_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, false);
        _expectInactive();
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, 1e6, 1e9, true);
    }

    function _accepted(
        IBurnerLoansCore.PriceSnapshot memory prices_,
        uint32 market_,
        uint256 collateral_,
        uint256 debt_,
        uint256 expected_,
        address caller_
    ) private {
        vm.prank(caller_);
        assertEq(
            _risk.health(prices_, market_, collateral_, debt_),
            expected_,
            "independent health"
        );
        vm.prank(caller_);
        assertEq(
            _risk.validateHealth(prices_, market_, collateral_, debt_, false),
            expected_,
            "current health"
        );
        vm.prank(caller_);
        assertEq(
            _risk.validateHealth(prices_, market_, collateral_, debt_, true),
            expected_,
            "final health"
        );
    }

    function _rejected(
        IBurnerLoansCore.PriceSnapshot memory prices_,
        uint32 market_,
        uint256 collateral_,
        uint256 debt_,
        bytes memory error_,
        address caller_
    ) private {
        vm.expectRevert(error_);
        vm.prank(caller_);
        _risk.health(prices_, market_, collateral_, debt_);
        vm.expectRevert(error_);
        vm.prank(caller_);
        _risk.validateHealth(prices_, market_, collateral_, debt_, false);
        vm.expectRevert(error_);
        vm.prank(caller_);
        _risk.validateHealth(prices_, market_, collateral_, debt_, true);
    }

    // Scenarios: BLRISK-HEALTH-P01.
    function test_whenDebtIsZero(address caller_, uint256 collateral_) public {
        _accepted(
            IBurnerLoansCore.PriceSnapshot(0, 0, 0),
            type(uint32).max,
            collateral_,
            0,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLRISK-HEALTH-P02.
    function test_whenRequirementIsZero(address caller_, uint256 debt_) public {
        _accepted(
            IBurnerLoansCore.PriceSnapshot(0, 0, 0),
            _MARKET,
            type(uint256).max,
            bound(debt_, 1, type(uint256).max),
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLRISK-HEALTH-P03.
    function test_whenPositionIsUnhealthy_revertsValidation(
        address caller_,
        uint256 collateral_
    ) public {
        uint256 collateral = bound(collateral_, 0, 999999);
        // One raw six-decimal collateral unit contributes 1e12 WAD to the $1 requirement.
        uint256 expected = collateral * 1e12;
        vm.prank(caller_);
        assertEq(_risk.health(_prices(), _MARKET, collateral, 1e9), expected, "unhealthy quote");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector,
                expected
            )
        );
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, collateral, 1e9, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                expected
            )
        );
        vm.prank(caller_);
        _risk.validateHealth(_prices(), _MARKET, collateral, 1e9, true);
    }

    // Scenarios: BLRISK-HEALTH-P07.
    function test_whenPositionIsExactlyHealthy(address caller_) public {
        _accepted(_prices(), _MARKET, 1e6, 1e9, 1e18, caller_);
    }

    // Scenarios: BLRISK-HEALTH-P08.
    function test_whenPositionIsHealthy(address caller_, uint256 collateral_) public {
        uint256 collateral = bound(collateral_, 1000001, type(uint256).max / 1e12);
        _accepted(_prices(), _MARKET, collateral, 1e9, collateral * 1e12, caller_);
    }

    // Scenarios: BLRISK-HEALTH-P11.
    function test_whenMarketMissing_reverts(address caller_) public {
        _rejected(
            _prices(),
            type(uint32).max,
            1e6,
            1e9,
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, type(uint32).max),
            caller_
        );
    }

    // Scenarios: BLRISK-HEALTH-I01.
    function test_whenMarketDebtTokenDiffers_reverts(address caller_) public {
        _market.debtToken = address(_asset);
        _mockMarket();
        _rejected(
            _prices(),
            _MARKET,
            1e6,
            1e9,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidMarket.selector,
                _MARKET
            ),
            caller_
        );
    }

    // Scenarios: BLRISK-HEALTH-N01.
    function test_whenHealthQuotientOverflows_reverts() public {
        // collateral USD=MAX256, required USD=1. MAX256*1e18/1 cannot fit.
        _rejected(
            IBurnerLoansCore.PriceSnapshot(1e9, 1e6, 0),
            _MARKET,
            type(uint256).max,
            1,
            stdError.arithmeticError,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-N02.
    function test_whenBackingRoundUpOverflows_reverts() public {
        _data.backingMultiplierBps = 10001;
        _mockMarket();
        // backing*10001 = MAX256*10000+6512: floor fits; ceil overflows.
        uint256 backing = 115780511186197575666004384570230884764793505315109053134144169590954034236512;
        _rejected(
            IBurnerLoansCore.PriceSnapshot(0, 1e18, backing),
            _MARKET,
            1e6,
            1e9,
            stdError.arithmeticError,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P09.
    function test_whenExactEconomicsUse6PriceDecimals() public {
        _price.setPriceDecimals(6);
        // $2 collateral / $1 requirement = 2 WAD at every exact common USD scale.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(1000000, 1000000, 1000000),
            _MARKET,
            2e6,
            1e9,
            2e18,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P10.
    function test_whenInexactEconomicsUse6PriceDecimals() public {
        _price.setPriceDecimals(6);
        // ceil(1000000001*1000000/1e9)=1000001; floor(2000001*1000000/1e6)=2000001.
        // floor(2000001*1e18/1000001)=1999999000000999999 WAD.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(1000000, 1000000, 1000000),
            _MARKET,
            2000001,
            1000000001,
            1999999000000999999,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P09.
    function test_whenExactEconomicsUse8PriceDecimals() public {
        _price.setPriceDecimals(8);
        // $2 collateral / $1 requirement = 2 WAD at every exact common USD scale.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(100000000, 100000000, 100000000),
            _MARKET,
            2e6,
            1e9,
            2e18,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P10.
    function test_whenInexactEconomicsUse8PriceDecimals() public {
        _price.setPriceDecimals(8);
        // ceil(1000000001*100000000/1e9)=100000001; floor(2000001*100000000/1e6)=200000100.
        // floor(200000100*1e18/100000001)=2000000979999990200 WAD.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(100000000, 100000000, 100000000),
            _MARKET,
            2000001,
            1000000001,
            2000000979999990200,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P09.
    function test_whenExactEconomicsUse18PriceDecimals() public {
        _price.setPriceDecimals(18);
        // $2 collateral / $1 requirement = 2 WAD at every exact common USD scale.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(
                1000000000000000000,
                1000000000000000000,
                1000000000000000000
            ),
            _MARKET,
            2e6,
            1e9,
            2e18,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P10.
    function test_whenInexactEconomicsUse18PriceDecimals() public {
        _price.setPriceDecimals(18);
        // ceil(1000000001*1000000000000000000/1e9)=1000000001000000000; floor(2000001*1000000000000000000/1e6)=2000001000000000000.
        // floor(2000001000000000000*1e18/1000000001000000000)=2000000997999999002 WAD.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(
                1000000000000000000,
                1000000000000000000,
                1000000000000000000
            ),
            _MARKET,
            2000001,
            1000000001,
            2000000997999999002,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P09.
    function test_whenExactEconomicsUse36PriceDecimals() public {
        _price.setPriceDecimals(36);
        // $2 collateral / $1 requirement = 2 WAD at every exact common USD scale.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(
                1000000000000000000000000000000000000,
                1000000000000000000000000000000000000,
                1000000000000000000000000000000000000
            ),
            _MARKET,
            2e6,
            1e9,
            2e18,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P10.
    function test_whenInexactEconomicsUse36PriceDecimals() public {
        _price.setPriceDecimals(36);
        // ceil(1000000001*1000000000000000000000000000000000000/1e9)=1000000001000000000000000000000000000; floor(2000001*1000000000000000000000000000000000000/1e6)=2000001000000000000000000000000000000.
        // floor(2000001000000000000000000000000000000*1e18/1000000001000000000000000000000000000)=2000000997999999002 WAD.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(
                1000000000000000000000000000000000000,
                1000000000000000000000000000000000000,
                1000000000000000000000000000000000000
            ),
            _MARKET,
            2000001,
            1000000001,
            2000000997999999002,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P07.
    function test_whenSnapshotFieldsAreMaximum() public {
        // Equal MAX256 values cancel in the full-precision ratio: health=1e18.
        _accepted(
            IBurnerLoansCore.PriceSnapshot(type(uint256).max, type(uint256).max, type(uint256).max),
            _MARKET,
            1e6,
            1e9,
            1e18,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-P01, BLRISK-HEALTH-P02.
    function test_whenDebtAndCollateralEndpoints() public {
        _accepted(
            IBurnerLoansCore.PriceSnapshot(0, 0, 0),
            type(uint32).max,
            0,
            0,
            type(uint256).max,
            address(this)
        );
        _accepted(
            IBurnerLoansCore.PriceSnapshot(0, 0, 0),
            _MARKET,
            0,
            1,
            type(uint256).max,
            address(this)
        );
        _accepted(
            IBurnerLoansCore.PriceSnapshot(0, 0, 0),
            _MARKET,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            address(this)
        );
    }

    // Scenarios: BLRISK-HEALTH-D01.
    function test_givenBackingUnavailable_whenConsumed_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _oracle.setEnabled(enabled_);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_oracle)
            )
        );
        _risk.health(_prices(), _MARKET, 2e6, 1e9);
    }

    // Scenarios: BLRISK-HEALTH-D02.
    function test_givenBackingLifecycleBoundaries_whenConsumed_reverts() public {
        uint256 initial = vm.snapshotState();
        test_givenBackingUnavailable_whenConsumed_reverts(true, false);
        vm.revertToState(initial);
        test_givenBackingUnavailable_whenConsumed_reverts(false, true);
        vm.revertToState(initial);
        test_givenBackingUnavailable_whenConsumed_reverts(false, false);
    }

    // Scenarios: BLRISK-HEALTH-D03.
    function test_givenBackingDisabled_whenHealthValidated_reverts(bool final_) public {
        _oracle.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_oracle)
            )
        );
        _risk.validateHealth(_prices(), _MARKET, 2e6, 1e9, final_);
    }

    // Scenarios: BLRISK-HEALTH-D04.
    function test_givenBackingDisabled_whenDebtFreeHealthValidated() public {
        _oracle.setEnabled(false);
        assertEq(
            _risk.health(_prices(), _MARKET, 0, 0),
            type(uint256).max,
            "debt-free health skips backing"
        );
        assertEq(
            _risk.validateHealth(_prices(), _MARKET, 0, 0, true),
            type(uint256).max,
            "debt-free validation skips backing"
        );
    }

    // Scenarios: BLRISK-HEALTH-D05.
    function test_givenCapturedBacking_whenGetterFails_thenHealthUsesCapture() public {
        IBurnerLoansCore.PriceSnapshot memory captured = _risk.snapshot(address(_asset));
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSignature("backing()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        // 1e6 collateral / 1e6 * $2 = $2; 1e9 OHM / 1e9 * max($1 market,$1 backing) = $1.
        // Health = $2 / $1 * 1e18 = 2e18.
        assertEq(
            _risk.health(captured, _MARKET, 1e6, 1e9),
            2e18,
            "health consumes captured values without rereading backing"
        );
        _oracle.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_oracle)
            )
        );
        _risk.health(captured, _MARKET, 1e6, 1e9);
        _oracle.setEnabled(true);
        assertEq(
            _risk.health(captured, _MARKET, 1e6, 1e9),
            2e18,
            "restored readiness permits captured values"
        );
    }
}
