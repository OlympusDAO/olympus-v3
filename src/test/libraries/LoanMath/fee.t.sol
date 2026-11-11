// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

// Contracts
import {Test} from "forge-std/Test.sol";

// Fixed arithmetic values are independent regression oracles, not configurable defaults.
// forge-lint: disable-start(literal-instead-of-constant)
/// @notice Ports the original BurnerLoansMath fee tests to the current internal LoanMath library.
/// @dev Zero-kink slopes intentionally exercise the math helper directly, as the original tests did.
///      Product configuration validation is covered separately; do not alter these regression inputs.
contract LoanMathFeeTest is Test {
    // Scenarios: BLRISK-FEE-N07.
    function test_whenUtilizationIsNearCap() public pure {
        // debt = 999,999,999; cap = 1,000,000,000
        // Expected: ceil(999_999_999 * 1e18 / 1_000_000_000) = 999_999_999_000_000_000
        // A bps-scaled utilization would collapse this to 10000 bps and lose the fractional detail.
        assertEq(
            LoanMath.assetUtilizationWad(999_999_999, 1_000_000_000),
            999_999_999_000_000_000,
            "asset utilization"
        );
    }

    // Scenarios: BLRISK-FEE-P06.
    function test_givenDefaultCurve_whenUtilizationIsZero() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // base = 25 bps = 25 / 10,000 = 0.0025 WAD
        // Pre-kink contribution = 0; post-kink contribution = 0.
        assertEq(_feeRate(0, feeConfig), 2_500_000_000_000_000, "zero utilization base fee");
    }

    // Scenarios: BLRISK-FEE-P07.
    function test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Pre-kink contribution = 100 bps * 40% / 80% = 50 bps.
        // Total = 25 bps + 50 bps = 75 bps = 0.0075 WAD.
        assertEq(_feeRate(0.4e18, feeConfig), 7_500_000_000_000_000, "pre-kink midpoint fee");
    }

    // Scenarios: BLRISK-FEE-N05.
    function test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // At the kink, the pre-kink contribution is 0.01 WAD.
        // One utilization WAD unit below the kink gives floor((0.8e18 - 1) / 80)
        // = 9,999,999,999,999,999. Adding the 0.0025 WAD base gives:
        // 12,499,999,999,999,999.
        assertEq(
            _feeRate(0.8e18 - 1, feeConfig),
            12_499_999_999_999_999,
            "fee immediately below kink"
        );
    }

    // Scenarios: BLRISK-FEE-P08.
    function test_givenDefaultCurve_whenUtilizationIsAtKink() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Total = 25 bps base + 100 bps pre-kink = 125 bps = 0.0125 WAD.
        assertEq(_feeRate(0.8e18, feeConfig), 12_500_000_000_000_000, "fee at kink");
    }

    // Scenarios: BLRISK-FEE-N06.
    function test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Post-kink contribution = floor(1 * 900e18 / (0.2e18 * 10,000)) = 0.
        // Total therefore remains 25 bps + 100 bps = 125 bps.
        assertEq(
            _feeRate(0.8e18 + 1, feeConfig),
            12_500_000_000_000_000,
            "fee immediately above kink"
        );
    }

    // Scenarios: BLRISK-FEE-P09.
    function test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Post-kink contribution = 900 bps * (90% - 80%) / (100% - 80%) = 450 bps.
        // Total = 25 bps + 100 bps + 450 bps = 575 bps = 0.0575 WAD.
        assertEq(_feeRate(0.9e18, feeConfig), 57_500_000_000_000_000, "post-kink midpoint fee");
    }

    // Scenarios: BLRISK-FEE-P10.
    function test_givenDefaultCurve_whenUtilizationIsFull() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Total = 25 bps + 100 bps + 900 bps = 1,025 bps = 0.1025 WAD.
        assertEq(_feeRate(1e18, feeConfig), 102_500_000_000_000_000, "full utilization fee");
    }

    // Scenarios: BLRISK-FEE-N21.
    function test_givenZeroKink_whenSlopeIsNonzero() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = IBurnerLoansRisk.AssetFeeConfig({
            baseFeeBps: 25,
            kinkBps: 0,
            preKinkSlopeBps: 1000,
            postKinkSlopeBps: 0
        });

        // base = 25 bps = 0.0025e18
        // utilization = 90% = 0.9e18
        // preKinkSlope = 1000 bps = 10%
        // Expected: 0.0025e18 + floor(0.9e18 * 1000 / 10000) = 0.0925e18
        assertEq(_feeRate(0.9e18, feeConfig), 0.0925e18, "single slope fee");
    }

    // Scenarios: BLRISK-FEE-N22.
    function test_givenZeroKink_whenSlopeContributionHasRemainder() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = IBurnerLoansRisk.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 3333,
            postKinkSlopeBps: 0
        });

        // utilization = 999_999_999_000_000_000 / 1e18
        // preKinkSlope = 3333 bps
        // Expected: floor(999_999_999_000_000_000 * 3333 / 10000)
        //         = 333_299_999_666_700_000
        // Dividing utilization by 1e18 before multiplying would incorrectly return zero.
        assertEq(_feeRate(999_999_999_000_000_000, feeConfig), 333_299_999_666_700_000, "fee rate");
    }

    // Scenarios: BLRISK-FEE-N23.
    function test_givenZeroKink_whenUtilizationIsNearCap() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = IBurnerLoansRisk.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });
        uint256 utilizationWad = LoanMath.assetUtilizationWad(999_999_999, 1_000_000_000);

        // utilization = 999_999_999_000_000_000 / 1e18 = 99.9_999_999%
        // preKinkSlope = 10000 bps = 100%, so expected fee rate equals utilization.
        // A bps path would produce either 9999 bps (0.9999e18) if floored or 10000 bps (1e18)
        // if rounded up. The WAD path preserves the exact 0.999999999e18 fee rate.
        assertEq(_feeRate(utilizationWad, feeConfig), 999_999_999_000_000_000, "fee rate");
    }

    // Scenarios: BLRISK-FEE-P22.
    function test_givenDefaultCurve_whenCrossingKink() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        uint256 atKink = _feeRate(0.8e18, feeConfig);
        uint256 justAboveKink = _feeRate(0.8001e18, feeConfig);
        uint256 aboveKink = _feeRate(0.9e18, feeConfig);

        assertEq(atKink, 0.0125e18, "at kink");
        assertGe(justAboveKink, atKink, "kink continuity");
        assertGe(aboveKink, justAboveKink, "monotonic");
    }

    // Scenarios: BLRISK-FEE-N25.
    function test_whenBorrowFeeIsCalculated() public pure {
        // required collateral = 1000e6, fee rate = 1 bps = 0.0001e18
        // Expected: ceil(1000e6 * 0.0001e18 / 1e18) = 100_000
        assertEq(LoanMath.borrowFee(1000e6, 0.0001e18), 100_000, "borrow fee");
    }

    // Scenarios: BLRISK-FEE-N24.
    function test_givenZeroKink_whenNearCapBorrowFeeIsCalculated() public pure {
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = IBurnerLoansRisk.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });
        uint256 utilizationWad = LoanMath.assetUtilizationWad(999_999_999, 1_000_000_000);
        uint256 feeRateWad = _feeRate(utilizationWad, feeConfig);

        // required collateral = 1000e18
        // fee rate = 999_999_999_000_000_000 / 1e18
        // Expected: ceil(1000e18 * 999_999_999_000_000_000 / 1e18)
        //         = 999_999_999_000_000_000_000
        assertEq(LoanMath.borrowFee(1000e18, feeRateWad), 999_999_999e12, "borrow fee");
    }

    // Scenarios: BLRISK-FEE-P01.
    function test_whenUtilizationIsRoundedUp(uint256 debt_, uint256 cap_) public pure {
        cap_ = bound(cap_, 1, 1e36);
        debt_ = bound(debt_, 0, cap_);

        uint256 utilizationWad = LoanMath.assetUtilizationWad(debt_, cap_);

        assertGe(utilizationWad * cap_, debt_ * 1e18, "rounded up lower bound");
        if (utilizationWad > 0) {
            assertLt((utilizationWad - 1) * cap_, debt_ * 1e18, "minimal rounded up value");
        }
    }

    // Scenarios: BLRISK-FEE-P23.
    function test_givenDefaultCurve_whenUtilizationIncreases(
        uint128 utilizationA_,
        uint128 utilizationB_
    ) public pure {
        uint256 utilizationA = bound(utilizationA_, 0, 1e18);
        uint256 utilizationB = bound(utilizationB_, utilizationA, 1e18);
        IBurnerLoansRisk.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        assertGe(
            _feeRate(utilizationB, feeConfig),
            _feeRate(utilizationA, feeConfig),
            "fee monotonic"
        );
    }

    // Scenarios: BLRISK-FEE-N08.
    function test_whenNonzeroDebtIsTiny() public pure {
        // ceil(1 raw OHM * 1e18 / 1e36 raw cap) = 1 WAD unit, not zero.
        assertEq(LoanMath.assetUtilizationWad(1, 1e36), 1, "tiny debt utilization");
    }

    // Scenarios: BLRISK-FEE-P23.
    function test_givenDefaultCurve_whenUtilizationEndpointsAreCompared() public {
        test_givenDefaultCurve_whenUtilizationIncreases(0, 0);
        test_givenDefaultCurve_whenUtilizationIncreases(0, 1e18);
        test_givenDefaultCurve_whenUtilizationIncreases(1e18, 1e18);
    }

    function _defaultAssetFeeConfig()
        private
        pure
        returns (IBurnerLoansRisk.AssetFeeConfig memory)
    {
        return IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900);
    }

    function _feeRate(
        uint256 utilization_,
        IBurnerLoansRisk.AssetFeeConfig memory curve_
    ) private pure returns (uint256) {
        return
            LoanMath.feeRateWad(
                utilization_,
                curve_.baseFeeBps,
                curve_.kinkBps,
                curve_.preKinkSlopeBps,
                curve_.postKinkSlopeBps
            );
    }
}
// forge-lint: disable-end(literal-instead-of-constant)
