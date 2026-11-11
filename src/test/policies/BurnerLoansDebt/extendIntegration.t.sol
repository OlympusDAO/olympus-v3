// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {BurnerLoansDebtIntegrationTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtIntegrationTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtExtendIntegrationTest is BurnerLoansDebtIntegrationTest {
    // Scenarios: BLEXT-EXTEND-P05.
    function test_givenRealRisk_whenExtended_thenPerTermRoundingIsIndependent() public {
        _openRealDebt(2000e6, 100e9);
        // Utilization=0.1%; rate=25.125 bps.
        // ceil(125e6*25.125/10000)*2=314063*2=628126, not 628125.
        _assertRealExtension(2, 628126, 60 days, 16e18);
    }

    // Scenarios: BLEXT-EXTEND-P05.
    function test_givenRealRisk_whenOneTermExtended_then314063Fee(uint8 priceDecimals_) public {
        priceDecimals_ = uint8(bound(priceDecimals_, 6, 18));
        _price.setPriceDecimals(priceDecimals_);
        _price.setPrice(address(_asset), 10 ** priceDecimals_);
        _price.setPrice(address(_ohm), 10 ** priceDecimals_);
        _openRealDebt(2000e6, 100e9);
        // ceil(125e6*25.125/10000)=314063 raw collateral units for one term.
        _assertRealExtension(1, 314063, 30 days, 16e18);
    }

    // Scenarios: BLEXT-EXTEND-P07.
    function test_givenRealTopUp_whenExtended() public {
        _openToppedUpDebt();
        // Utilization=150/100000=0.15%; rate=25+100*0.0015/0.8=25.1875 bps.
        // Required backing=150*1.25=187.5 collateral tokens (6 decimals).
        // ceil(187.5e6*25.1875/10000)*2=472266*2=944532.
        // floor(2000/187.5*1e18)=10666666666666666666 health.
        _assertRealExtension(2, 944532, 60 days, 10666666666666666666);
    }

    // Scenarios: BLEXT-EXTEND-P08.
    function test_givenRealTopUp_givenUpdatedTermLength_whenExtended() public {
        _openToppedUpDebt();
        uint48 oldMaturity = _position().maturity;
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 15 days, 90 days, 1000e6)
        );
        assertEq(_position().maturity, oldMaturity, "Governance term update preserves old expiry");
        // Same two per-term fees as P07; current term length gives 2*15 days.
        _assertRealExtension(2, 944532, 30 days, 10666666666666666666);
    }

    function _openToppedUpDebt() internal {
        _openRealDebt(2000e6, 100e9);
        uint48 maturity = _position().maturity;
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _price.setTimestamp(uint48(block.timestamp));
        uint256 balance = _asset.balanceOf(_borrower);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory topUp = _debt.borrow(
            address(_asset),
            50e9,
            _borrower,
            _borrower,
            157032,
            address(0)
        );
        // Top-up charges only added backing=50*1.25=62.5 assets.
        // ceil(62.5e6*25.125/10000)=157032 raw collateral units.
        assertEq(topUp.fee, 157032, "Top-up fee uses only added principal");
        assertEq(_asset.balanceOf(_borrower), balance - 157032, "Exact top-up fee debit");
        assertEq(topUp.maturity, maturity, "Top-up preserves original expiry");
        assertEq(_position().maturity, maturity, "Stored expiry remains unchanged");
        assertEq(_position().principalDue, 150e9, "Top-up increases aggregate position debt");
    }

    // Scenarios: BLEXT-EXTEND-P09.
    function test_givenExpiredCacheAndChangedPrice_whenExtended() public {
        PriceCache cache = _installPriceCache();
        _openRealDebt(2000e6, 100e9);
        vm.prank(_borrower);
        uint256 originalFee = _debt
            .previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(0))
            .fee;
        assertEq(originalFee, 314063, "Original fee uses one-dollar collateral");
        _expireCacheAndHalveCollateralPrice();
        // Required backing USD 125 / USD 0.5 = 250 collateral tokens.
        // ceil(250e6*25.125/10000)=628125; health=2000/250=8 WAD.
        _assertRealExtension(1, 628125, 30 days, 8e18);
        assertEq(
            cache.getCachedPrice(address(_ohm), address(_asset)).roundId,
            2,
            "One real cache refresh"
        );
    }

    // Scenarios: BLEXT-EXTEND-P10.
    function test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts() public {
        PriceCache cache = _installPriceCache();
        _openRealDebt(2000e6, 100e9);
        vm.prank(_borrower);
        uint256 originalFee = _debt
            .previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(0))
            .fee;
        assertEq(originalFee, 314063, "Original fee limit precedes the price change");
        _expireCacheAndHalveCollateralPrice();
        bytes32 cached = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                uint256(628125),
                originalFee
            ),
            1,
            originalFee,
            _borrower
        );
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            cached,
            "Failed extension restores cache round, timestamp and prices"
        );
    }

    function _assertRealExtension(
        uint16 terms_,
        uint256 fee_,
        uint48 increment_,
        uint256 health_
    ) internal {
        _retainFee();
        uint256 wallet = _asset.balanceOf(_borrower);
        uint256 payoutBalance = _asset.balanceOf(address(_payout));
        IFLOANv1.Position memory position = _position();
        {
            bytes32 beforeQuote = _stateDigest(_borrower);
            vm.prank(_borrower);
            IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
                address(_asset),
                _borrower,
                terms_,
                fee_,
                address(0)
            );
            assertEq(_stateDigest(_borrower), beforeQuote, "Real extension quote is read only");
            assertEq(quote.fee, fee_, "Independent real extension fee quote");
            assertEq(quote.maturity, position.maturity + increment_, "Independent maturity quote");
            assertEq(quote.healthFactor, health_, "Independent health quote");
        }
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Extended(
            _borrower,
            address(_asset),
            _borrower,
            position.maturity + increment_,
            fee_,
            address(0),
            0
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            terms_,
            fee_,
            address(0)
        );
        assertEq(result.fee, fee_, "Independent execution fee");
        assertEq(
            result.maturity,
            position.maturity + increment_,
            "Maturity uses old expiry and current term"
        );
        assertEq(result.healthFactor, health_, "Independent execution health");
        assertEq(_asset.balanceOf(_borrower), wallet - fee_, "Exact incoming fee debit");
        assertEq(
            _asset.balanceOf(address(_payout)),
            payoutBalance + fee_,
            "Exact incoming fee receipt"
        );
        assertEq(_position().maturity, result.maturity, "Stored maturity matches execution");
        assertEq(
            _position().principalDue,
            position.principalDue,
            "Extension preserves aggregate principal"
        );
        assertEq(_position().collateral, position.collateral, "Extension preserves collateral");
        assertEq(
            _inventory.activePrincipalOhm(),
            position.principalDue,
            "Extension preserves Inventory principal"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            position.principalDue,
            "Market principal reconciles"
        );
    }

    // Scenarios: BLEXT-EXTEND-P06, BLEXT-EXTEND-I02.
    function test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 8 hours + 1);
        bytes32 state = _stateDigest(_borrower);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(
            _stateDigest(_borrower),
            state,
            "Real pricing failure restores all ledgers, custody and allowances"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
