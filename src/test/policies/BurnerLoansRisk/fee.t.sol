// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskFeeTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-FEE-I08.
    function test_whenCollateralPriceIsZero_whenTermsAreZero_reverts(address caller_) public {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            1e18,
            0,
            1e18
        );
        uint32 market = _MARKET;
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.fee(snapshot, market, 1e9, 0);
    }

    // Scenarios: BLRISK-FEE-N03.
    function test_whenRequiredDebtValueOverflows_reverts(address caller_) public {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            2e18,
            1e18,
            1e18
        );
        uint32 market = _MARKET;
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.fee(snapshot, market, type(uint256).max, 1);
    }

    // Scenarios: BLRISK-FEE-N02.
    function test_whenFeePerTermTimesTermsOverflows_reverts(address caller_) public {
        _market.maxLtvBps = 10000;
        _market.baseFeeBps = 10000;
        _data.backingMultiplierBps = 10000;
        _data.kinkBps = 0;
        _data.preKinkSlopeBps = 0;
        _data.postKinkSlopeBps = 0;
        _mockMarket();
        // USD inputs use one common synthetic scale. Each raw OHM unit needs one raw collateral
        // unit: debtPrice / 1e9 = collateralPrice / 1e6 = 1. At a 100% fee, fee/term=principal.
        // principal=2**255 is representable; two terms need 2**256, which is not.
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            1e9,
            1e6,
            1e9
        );
        uint32 market = _MARKET;
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.fee(snapshot, market, 2 ** 255, 2);
    }

    // Scenarios: BLRISK-FEE-N04, BLRISK-HEALTH-N02.
    function test_whenBackingRoundUpOverflows_thenFeeAndHealthRevert(address caller_) public {
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10001;
        _mockMarket();
        // One whole OHM makes backing USD equal to this supplied raw backing value.
        // backing * 10001 = MAX256 * 10000 + 6512. The floor fits MAX256, but ceil needs MAX256+1.
        uint256 backing = 115780511186197575666004384570230884764793505315109053134144169590954034236512;
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            0,
            1e18,
            backing
        );
        uint32 market = _MARKET;
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.fee(snapshot, market, 1e9, 1);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.health(snapshot, market, 1e6, 1e9);
    }

    // Scenarios: BLRISK-FEE-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 10000, "flat one percent fee");
    }

    // Scenarios: BLRISK-FEE-L02.
    function test_givenDisabled_whenCalled_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-L03.
    function test_givenInactive_whenCalled_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-L04.
    function test_givenInactiveAndDisabled_whenCalled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-L01.
    function test_givenReEnabled_whenCalled(address caller_) public givenReEnabled {
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 10000, "flat one percent fee");
    }

    function _curve(uint16 base_, uint16 kink_, uint16 pre_, uint16 post_) private {
        _market.baseFeeBps = base_;
        _data.kinkBps = kink_;
        _data.preKinkSlopeBps = pre_;
        _data.postKinkSlopeBps = post_;
        _mockMarket();
    }

    // Scenarios: BLRISK-FEE-I02.
    function test_givenZeroCap_whenFeeQuoted_reverts(address caller_) public {
        _market.principalCap = 0;
        _mockMarket();
        _mockDebt(1);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector);
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-I03.
    function test_givenDebtAboveCap_whenFeeQuoted_reverts(address caller_) public {
        _mockDebt(uint256(_market.principalCap) + 1);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector);
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-I07.
    function test_givenZeroTermsAndZeroCap_whenFeeQuoted_reverts(address caller_) public {
        _market.principalCap = 0;
        _mockMarket();
        _mockDebt(1);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector);
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 0);
    }

    // Scenarios: BLRISK-FEE-I09.
    function test_whenMarketMissing_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, type(uint32).max)
        );
        vm.prank(caller_);
        _risk.fee(_prices(), type(uint32).max, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-I01.
    function test_givenEmptyMarketZeroCap_whenFeeQuoted(address caller_) public {
        _market.principalCap = 0;
        _mockMarket();
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 10000, "independent flat fee");
    }

    // Scenarios: BLRISK-FEE-I04.
    function test_givenZeroKinkFlatCurve_whenFeeQuoted(address caller_) public {
        _curve(100, 0, 0, 0);
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 10000, "independent flat fee");
    }

    // Scenarios: BLRISK-FEE-I05.
    function test_givenZeroPrincipal_whenFeeQuoted(address caller_) public {
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 0, 1), 0, "independent flat fee");
    }

    // Scenarios: BLRISK-FEE-I06.
    function test_givenZeroTerms_whenFeeQuoted(address caller_) public {
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 0), 0, "independent flat fee");
    }

    // Scenarios: BLRISK-FEE-N01.
    function test_whenTermsAndPrincipalAreRepresentable(
        address caller_,
        uint256 principal_,
        uint16 terms_
    ) public {
        _curve(10000, 0, 0, 0);
        uint16 terms = uint16(bound(terms_, 1, type(uint16).max));
        uint256 principal = bound(principal_, 1, type(uint256).max / terms);
        // Identical debt/collateral unit values, full fee, so each term costs exactly principal.
        vm.prank(caller_);
        assertEq(
            _risk.fee(IBurnerLoansCore.PriceSnapshot(1e9, 1e6, 1e9), _MARKET, principal, terms),
            principal * terms,
            "per-term scaling"
        );
    }

    // Scenarios: BLRISK-FEE-N01, BLRISK-FEE-N16.
    function test_whenPrincipalAndTermEndpoints() public {
        _curve(10000, 0, 0, 0);
        IBurnerLoansCore.PriceSnapshot memory prices = IBurnerLoansCore.PriceSnapshot(
            1e9,
            1e6,
            1e9
        );
        assertEq(
            _risk.fee(prices, _MARKET, type(uint256).max, 1),
            type(uint256).max,
            "MAX principal is representable"
        );
        assertEq(_risk.fee(prices, _MARKET, 1, type(uint16).max), 65535, "MAX terms");
    }

    // Scenarios: BLRISK-FEE-P01.
    function test_whenUtilizationRoundsUp(address caller_, uint128 cap_, uint128 debt_) public {
        uint128 cap = uint128(bound(cap_, 2, type(uint128).max));
        uint128 debt = uint128(bound(debt_, 1, cap - 1));
        _market.principalCap = cap;
        _market.collateralDecimals = 18;
        _curve(0, 5000, 5000, 5000);
        _mockDebt(debt);
        // Linear 0..100% fee and exactly 1e18 required collateral make fee equal ceil(debt*1e18/cap).
        // uint128 debt * 1e18 fits uint256; use elementary division as independent oracle.
        uint256 expected = (uint256(debt) * 1e18 - 1) / cap + 1;
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), expected, "utilization is rounded up");
    }

    // Scenarios: BLRISK-FEE-P03.
    function test_givenBeforeKink_whenFeeQuoted(address caller_, uint128 debt_) public {
        uint128 debt = uint128(bound(debt_, 1, 7999));
        _market.principalCap = 10000;
        _market.collateralDecimals = 18;
        _curve(25, 8000, 100, 900);
        _mockDebt(debt);
        // At cap=10000 each raw debt unit is 1bps utilization; slope is 100/8000 before kink, 900/2000 after.
        vm.prank(caller_);
        assertEq(
            _risk.fee(_prices(), _MARKET, 1e9, 1),
            2500000000000000 + uint256(debt) * 1250000000000,
            "piecewise fee"
        );
    }

    // Scenarios: BLRISK-FEE-P04.
    function test_givenAtKink_whenFeeQuoted(address caller_, uint128 debt_) public {
        uint128 debt = uint128(bound(debt_, 8000, 8000));
        _market.principalCap = 10000;
        _market.collateralDecimals = 18;
        _curve(25, 8000, 100, 900);
        _mockDebt(debt);
        // At cap=10000 each raw debt unit is 1bps utilization; slope is 100/8000 before kink, 900/2000 after.
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 12500000000000000, "piecewise fee");
    }

    // Scenarios: BLRISK-FEE-P05.
    function test_givenAfterKink_whenFeeQuoted(address caller_, uint128 debt_) public {
        uint128 debt = uint128(bound(debt_, 8001, 10000));
        _market.principalCap = 10000;
        _market.collateralDecimals = 18;
        _curve(25, 8000, 100, 900);
        _mockDebt(debt);
        // At cap=10000 each raw debt unit is 1bps utilization; slope is 100/8000 before kink, 900/2000 after.
        vm.prank(caller_);
        assertEq(
            _risk.fee(_prices(), _MARKET, 1e9, 1),
            12500000000000000 + (uint256(debt) - 8000) * 45000000000000,
            "piecewise fee"
        );
    }

    // Scenarios: BLRISK-FEE-P02.
    function test_givenAtCap_whenFeeQuoted(address caller_, uint128 debt_) public {
        uint128 debt = uint128(bound(debt_, 10000, 10000));
        _market.principalCap = 10000;
        _market.collateralDecimals = 18;
        _curve(25, 8000, 100, 900);
        _mockDebt(debt);
        // At cap=10000 each raw debt unit is 1bps utilization; slope is 100/8000 before kink, 900/2000 after.
        vm.prank(caller_);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 102500000000000000, "piecewise fee");
    }

    // Scenarios: BLRISK-FEE-P13.
    function test_whenMarketRequirement() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 2000000 raw collateral.
        // ceil(2000000 * 100 / 10000) = 20000 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    2000000000000000000,
                    1000000000000000000,
                    1000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            20000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P14.
    function test_whenBackingRequirement() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 2000000 raw collateral.
        // ceil(2000000 * 100 / 10000) = 20000 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    1000000000000000000,
                    1000000000000000000,
                    2000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            20000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P15.
    function test_whenEqualRequirements() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 2000000 raw collateral.
        // ceil(2000000 * 100 / 10000) = 20000 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    2000000000000000000,
                    1000000000000000000,
                    2000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            20000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P16.
    function test_whenDiscountedLtv() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 5000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 4000000 raw collateral.
        // ceil(4000000 * 100 / 10000) = 40000 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    2000000000000000000,
                    1000000000000000000,
                    1000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            40000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-P17.
    function test_whenBackingMultiplier() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 12500;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 2500000 raw collateral.
        // ceil(2500000 * 100 / 10000) = 25000 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    1000000000000000000,
                    1000000000000000000,
                    2000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            25000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N17.
    function test_whenCollateralConversionRoundsUp() public {
        _price.setPriceDecimals(18);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 333334 raw collateral.
        // ceil(333334 * 100 / 10000) = 3334 raw collateral fee.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    1000000000000000000,
                    3000000000000000000,
                    1000000000000000000
                ),
                _MARKET,
                1e9,
                1
            ),
            3334,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N18.
    function test_whenSixPriceDecimals() public {
        _price.setPriceDecimals(6);
        _market.collateralDecimals = 6;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 1000000 raw collateral.
        // ceil(1000000 * 100 / 10000) = 10000 raw collateral fee.
        assertEq(
            _risk.fee(IBurnerLoansCore.PriceSnapshot(1000000, 1000000, 1000000), _MARKET, 1e9, 1),
            10000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N20.
    function test_whenSixPriceEighteenCollateralDecimals() public {
        _price.setPriceDecimals(6);
        _market.collateralDecimals = 18;
        _market.maxLtvBps = 10000;
        _data.backingMultiplierBps = 10000;
        _mockMarket();
        // max(market/LTV, backing*multiplier) converted up gives 1000000000000000000 raw collateral.
        // ceil(1000000000000000000 * 100 / 10000) = 10000000000000000 raw collateral fee.
        assertEq(
            _risk.fee(IBurnerLoansCore.PriceSnapshot(1000000, 1000000, 1000000), _MARKET, 1e9, 1),
            10000000000000000,
            "independent collateral fee"
        );
    }

    // Scenarios: BLRISK-FEE-N19.
    function test_whenEighteenOhmDecimals() public {
        MockERC20 ohm18 = new MockERC20("OHM18", "OHM18", 18);
        BurnerLoansRisk evaluator = new BurnerLoansRisk(
            _kernel,
            IERC20(address(ohm18)),
            address(_oracle),
            address(0),
            0,
            address(this)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(evaluator));
        evaluator.enable("");
        _market.debtToken = address(ohm18);
        _market.debtDecimals = 18;
        _market.collateralDecimals = 18;
        _mockMarket();
        // One whole OHM needs 1e18 collateral; a 100bps fee is 1e16.
        assertEq(evaluator.fee(_prices(), _MARKET, 1e18, 1), 1e16, "OHM and collateral units");
    }

    // Scenarios: BLRISK-FEE-P11.
    function test_whenFlatBase() public {
        _market.collateralDecimals = 18;
        _curve(25, 0, 0, 0);
        assertEq(
            _risk.fee(_prices(), _MARKET, 1e9, 1),
            2500000000000000,
            "flat curve expected fee"
        );
    }

    // Scenarios: BLRISK-FEE-P12.
    function test_whenZeroCurve() public {
        _market.collateralDecimals = 18;
        _curve(0, 0, 0, 0);
        assertEq(_risk.fee(_prices(), _MARKET, 1e9, 1), 0, "flat curve expected fee");
    }

    // Scenarios: BLRISK-FEE-D01.
    function test_whenDebtTokenDiffers_reverts(address caller_) public {
        _market.debtToken = address(_asset);
        _mockMarket();
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoansRisk_InvalidMarket.selector, _MARKET)
        );
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-D02.
    function test_whenMarketSchemaDiffers_reverts(address caller_) public {
        _market.configId = bytes16("Other product");
        _mockMarket();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_IncompatibleMarketConfig.selector,
                _MARKET,
                _market.configId
            )
        );
        vm.prank(caller_);
        _risk.fee(_prices(), _MARKET, 1e9, 1);
    }

    // Scenarios: BLRISK-FEE-P20.
    function test_whenMarketExitsAsShares() public {
        _market.collateralDecimals = 18;
        _market.principalCap = 1e18;
        _data.withdrawAsShares = true;
        _curve(25, 8000, 100, 900);
        _mockDebt(4e17);
        assertEq(
            _risk.fee(_prices(), _MARKET, 1e9, 1),
            7500000000000000,
            "fees stay in underlying units"
        );
    }

    // Scenarios: BLRISK-FEE-N01.
    function test_whenSnapshotFieldsAreMaximum() public {
        // Identical maximum USD fields: MAX debt USD / MAX collateral price yields 1e6 raw collateral.
        assertEq(
            _risk.fee(
                IBurnerLoansCore.PriceSnapshot(
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max
                ),
                _MARKET,
                1e9,
                1
            ),
            10000,
            "maximum snapshot prices remain full precision"
        );
    }
}
