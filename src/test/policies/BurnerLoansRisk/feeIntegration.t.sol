// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// These literals are independently derived regression oracles and deliberate scale boundaries.
// forge-lint: disable-start(literal-instead-of-constant)
/// @notice Ports original fee regressions through real Risk, LoanMath and FLOAN markets.
contract BurnerLoansRiskFeeIntegrationTest is BurnerLoansModularTest {
    // Scenarios: BLRISK-FEE-P06.
    function test_givenDefaultCurve_whenUtilizationIsZero_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(0, 1e18);
        // Base=25 bps, so fee on 1e18 collateral is 0.0025e18.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            2_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P07.
    function test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(400_000_000_000_000_000, 1e18);
        // 25 + 100*(40/80) = 75 bps; 1e18*75/10000 = 7.5e15.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            7_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N05.
    function test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(799_999_999_999_999_999, 1e18);
        // floor((8e17-1)/80) + 2.5e15 = 12_499_999_999_999_999.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            12_499_999_999_999_999,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P08.
    function test_givenDefaultCurve_whenUtilizationIsAtKink_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(800_000_000_000_000_000, 1e18);
        // 25+100 = 125 bps; fee = 1e18*125/10000 = 1.25e16.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            12_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N06.
    function test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(800_000_000_000_000_001, 1e18);
        // First post-kink step floors 900/2000 to zero; fee stays 1.25e16.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            12_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P09.
    function test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(900_000_000_000_000_000, 1e18);
        // 25+100+900*(90-80)/(100-80) = 575 bps; fee = 5.75e16.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            57_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P10.
    function test_givenDefaultCurve_whenUtilizationIsFull_whenRiskIsCalled() public {
        uint32 market = _defaultCurveMarket(1_000_000_000_000_000_000, 1e18);
        // 25+100+900 = 1025 bps; fee = 0.1025e18.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            102_500_000_000_000_000,
            "fixed curve collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N07.
    function test_givenLinearCurve_whenUtilizationIsNearCap() public {
        uint32 market = _feeMarket(
            999_999_999,
            1_000_000_000,
            18,
            IBurnerLoansRisk.AssetFeeConfig(0, 5000, 5000, 5000)
        );
        // The legal 50% kink and equal 50% increases give rate=utilization.
        // U=999_999_999_000_000_000; R=1000e18; fee=999_999_999_000_000_000_000.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1000e9, 1),
            999_999_999_000_000_000_000,
            "near-cap fee retains WAD precision"
        );
    }

    // Scenarios: BLRISK-FEE-N08.
    function test_givenLinearCurve_whenDebtIsTiny() public {
        uint32 market = _feeMarket(
            1,
            1e36,
            18,
            IBurnerLoansRisk.AssetFeeConfig(0, 5000, 5000, 5000)
        );
        // ceil(1*1e18/1e36)=1 utilization WAD unit; rate=1; R=1e18 gives one raw fee unit.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            1,
            "nonzero utilization is retained"
        );
    }

    // Scenarios: BLRISK-FEE-N09.
    function test_givenFlatCurve_whenPrincipalIsOneRawOhmUnit() public {
        uint32 market = _feeMarket(0, 1e18, 6, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // Debt USD=1e9 raw PRICE units; required asset=ceil(1e9*1e6/1e18)=1.
        // One basis point on one raw collateral unit rounds up to one.
        assertEq(_risk.fee(_oneDollarSnapshot(), market, 1, 1), 1, "dust fee rounds up");
    }

    // Scenarios: BLRISK-FEE-N10.
    function test_givenFlatCurve_whenThreeTermsAreQuoted() public {
        uint32 market = _feeMarket(0, 1e18, 6, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // R=1000e6 collateral; fee/term=1000e6/10000=100_000; three terms cost 300_000 raw units.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1000e9, 3),
            300_000,
            "extension fee scales by three terms"
        );
    }

    // Scenarios: BLRISK-FEE-N11.
    function test_givenDustFee_whenThreeTermsAreQuoted() public {
        uint32 market = _feeMarket(0, 1e18, 6, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // R=1; ceil(R/10000)=1 each term. Three individually rounded terms cost 3, not 1.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1, 3),
            3,
            "round each term before multiplying"
        );
    }

    // Scenarios: BLRISK-FEE-N12.
    function test_givenDustFee_whenMaximumTermsAreQuoted() public {
        uint32 market = _feeMarket(0, 1e18, 6, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // Fee/term=1 raw collateral unit; uint16 maximum terms=65535.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1, type(uint16).max),
            65535,
            "maximum term count is not narrowed"
        );
    }

    // Scenarios: BLRISK-FEE-N13.
    function test_givenFlatCurve_whenFeeIsImmediatelyBelowAnInteger() public {
        uint32 market = _feeMarket(0, 1e18, 0, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // R=9999 whole zero-decimal tokens; ceil(9999/10000)=1.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 9999e9, 1),
            1,
            "below-integer fee rounds up"
        );
    }

    // Scenarios: BLRISK-FEE-N14.
    function test_givenFlatCurve_whenFeeIsExactlyAnInteger() public {
        uint32 market = _feeMarket(0, 1e18, 0, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // R=10000 whole zero-decimal tokens; 10000/10000=1 exactly.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 10000e9, 1),
            1,
            "exact fee does not round past the integer"
        );
    }

    // Scenarios: BLRISK-FEE-N15.
    function test_givenFlatCurve_whenFeeIsImmediatelyAboveAnInteger() public {
        uint32 market = _feeMarket(0, 1e18, 0, IBurnerLoansRisk.AssetFeeConfig(1, 0, 0, 0));
        // R=10001 whole zero-decimal tokens; ceil(10001/10000)=2.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 10001e9, 1),
            2,
            "above-integer fee rounds to the next unit"
        );
    }

    // Scenarios: BLRISK-FEE-P19.
    function test_givenExistingMarketDebt_whenRequestedPrincipalDoubles() public {
        uint32 market = _defaultCurveMarket(4e17, 1e18);
        // Pre-borrow U stays 40%; rate=75 bps. R=2e18 gives fee=15e15.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 2e9, 1),
            15_000_000_000_000_000,
            "requested debt is excluded from utilization"
        );
        assertEq(
            _floan.getMarketPrincipalDue(market),
            4e17,
            "fee quote leaves canonical debt unchanged"
        );
    }

    // Scenarios: BLRISK-FEE-P18.
    function test_givenAnotherMarketHasDebt_whenSelectedMarketFeeIsQuoted() public {
        uint32 selected = _defaultCurveMarket(3, 4);
        uint32 other = _defaultCurveMarket(9e17, 1e18);
        // Original asset-only inputs: U=3/4=75%, despite other market U=90%.
        // Rate=25+100*(75/80)=118.75 bps; R=1e18 gives 11_875_000_000_000_000.
        assertEq(
            _risk.fee(_oneDollarSnapshot(), selected, 1e9, 1),
            11_875_000_000_000_000,
            "other market utilization is excluded"
        );
        assertEq(_floan.getMarketPrincipalDue(selected), 3, "selected principal stays unchanged");
        assertEq(_floan.getMarketPrincipalDue(other), 9e17, "other principal stays unchanged");
    }

    // With $1 prices/backing, 100% LTV/backing multiplier and 18-decimal collateral,
    // one whole OHM (1e9) requires 1e18 collateral units. Debt/cap sets market utilization.
    function _defaultCurveMarket(uint128 debt_, uint128 cap_) private returns (uint32) {
        return _feeMarket(debt_, cap_, 18, IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900));
    }

    function _oneDollarSnapshot() private pure returns (IBurnerLoansCore.PriceSnapshot memory) {
        return IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18);
    }

    function _feeMarket(
        uint128 debt_,
        uint128 cap_,
        uint8 collateralDecimals_,
        IBurnerLoansRisk.AssetFeeConfig memory curve_
    ) private returns (uint32 market) {
        // Real policy validation separates reachable product curves from direct math-only regressions.
        _risk.validateFeeConfig(curve_);
        MockERC20 collateral = new MockERC20("Fee collateral", "FEE", collateralDecimals_);
        LoanMarket.Data memory data = LoanMarket.Data(
            false,
            0,
            10000,
            0,
            curve_.kinkBps,
            curve_.preKinkSlopeBps,
            curve_.postKinkSlopeBps
        );
        vm.prank(address(_config));
        market = _floan.createMarket(
            IFLOANv1.MarketInput(
                address(collateral),
                address(_ohm),
                address(_config),
                address(_core),
                LoanMarket.CONFIG_ID,
                cap_,
                1 days,
                30 days,
                10000,
                curve_.baseFeeBps
            ),
            abi.encode(data)
        );
        if (debt_ != 0) {
            vm.startPrank(address(_core));
            uint64 position = _floan.createPosition(market, _borrower);
            // The fixture timestamp is fixed near genesis; adding one day fits uint48.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint48 maturity = uint48(block.timestamp + 1 days);
            IFLOANv1.Position memory seeded = _floan.increaseDebt(position, debt_, 0, maturity);
            assertEq(seeded.principalDue, debt_, "fixture principal matches requested utilization");
            vm.stopPrank();
        }
    }

    // Scenarios: BLRISK-FEE-P18.
    function test_givenGlobalFundingChanges_whenSelectedMarketFeeQuoted() public {
        uint32 market = _defaultCurveMarket(3, 4);
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            11875000000000000,
            "initial selected market fee"
        );
        _inventory.setGlobalDebtCap(200000e9);
        _supplyInventory(address(0xF00D), 100e9);
        assertEq(_inventory.suppliedOhm(), 100e9, "global funding changed");
        assertEq(_ohm.balanceOf(address(_inventory)), 100e9, "funding reached Inventory");
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            11875000000000000,
            "global context does not affect market quote"
        );
        assertEq(_floan.getMarketPrincipalDue(market), 3, "quote preserves principal");
    }

    // Scenarios: BLRISK-FEE-P21.
    function test_givenReplacementSelected_whenOldRiskQuoted() public {
        uint32 market = _defaultCurveMarket(4e17, 1e18);
        BurnerLoansRisk replacement = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            _risk.backingOracle(),
            address(0),
            0,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.setConfigOperator(address(_config));
        replacement.enable("");
        _core.setRisk(address(replacement));
        assertTrue(_risk.isEnabled(), "old Risk remains enabled");
        assertTrue(_kernel.isPolicyActive(_risk), "old Risk remains active");
        assertEq(
            _risk.fee(_oneDollarSnapshot(), market, 1e9, 1),
            7500000000000000,
            "selection does not retire old calculator"
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant)
