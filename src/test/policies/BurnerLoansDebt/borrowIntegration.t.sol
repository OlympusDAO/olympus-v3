// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansDebtIntegrationTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtIntegrationTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtBorrowIntegrationTest is BurnerLoansDebtIntegrationTest {
    // Scenarios: BLDEBT-BORROW-P13.
    function test_givenAnotherBorrowerDebt_whenBorrowed() public {
        _openRealDebt(2000e6, 100e9);
        bytes32 first = keccak256(abi.encode(_position()));
        _asset.mint(_recipient, 3000e6);
        vm.startPrank(_recipient);
        _asset.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(_asset), 2000e6, _recipient);
        uint256 balance = _asset.balanceOf(_recipient);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _recipient,
            _recipient,
            314063
        );
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _recipient,
            _recipient,
            314063
        );
        vm.stopPrank();
        // The first borrow leaves market utilization at 0.1%, so rate=25.125 bps.
        // ceil(125e6 * 25.125 / 10000) = 314063 raw collateral units.
        assertEq(quote.fee, 314063, "Other borrower contributes to market utilization");
        assertEq(result.fee, quote.fee, "Same fee at unchanged utilization");
        assertEq(
            _asset.balanceOf(_recipient),
            balance - 314063,
            "Second borrower pays its own fee"
        );
        assertEq(_ohm.balanceOf(_recipient), 100e9, "Second borrower receives its principal");
        assertEq(
            _lens.getPosition(address(_asset), _recipient).debtOhm,
            100e9,
            "Separate second debt"
        );
        assertEq(keccak256(abi.encode(_position())), first, "First borrower position is untouched");
        _assertMarketTotals(address(_asset), 200e9, 4000e6, 2);
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            4000e6,
            "Custody backs both borrowers"
        );
        assertEq(_inventory.activePrincipalOhm(), 200e9, "Inventory reconciles both borrowers");
    }

    // Scenarios: BLDEBT-BORROW-P14.
    function test_givenAnotherBorrowerDebt_whenSharedMarketCapExceeded_reverts() public {
        _openRealDebtFor(_asset, _recipient, 2000e6, 100e9);
        _depositCollateral(2000e6);
        _config.setAssetDebtCap(address(_asset), 150e9);
        bytes32 other = keccak256(abi.encode(_lens.getPosition(address(_asset), _recipient)));
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_AssetDebtCapExceeded.selector,
                address(_asset),
                uint256(51e9),
                uint256(50e9)
            ),
            51e9,
            _borrower,
            type(uint256).max,
            _borrower
        );
        assertEq(
            keccak256(abi.encode(_lens.getPosition(address(_asset), _recipient))),
            other,
            "Other borrower is untouched"
        );
    }

    // Scenarios: BLDEBT-BORROW-P15.
    function test_givenAnotherMarketDebt_whenSharedGlobalCapExceeded_reverts() public {
        MockERC20 other = _admitSecondAsset();
        _openRealDebtFor(other, _borrower, 2000e6, 100e9);
        _depositCollateral(2000e6);
        _inventory.setGlobalDebtCap(150e9);
        bytes32 otherState = _stateDigestFor(address(other), _borrower);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                uint256(51e9),
                uint256(50e9)
            ),
            51e9,
            _borrower,
            type(uint256).max,
            _borrower
        );
        assertEq(
            _stateDigestFor(address(other), _borrower),
            otherState,
            "Other market completely unchanged"
        );
    }

    // Scenarios: BLDEBT-BORROW-P16.
    function test_givenAnotherMarketDebt_whenBorrowed() public {
        MockERC20 other = _admitSecondAsset();
        _openRealDebtFor(other, _borrower, 2000e6, 100e9);
        bytes32 otherPosition = keccak256(abi.encode(_lens.getPosition(address(other), _borrower)));
        _depositCollateral(2000e6);
        // This market has zero utilization despite global principal of 100 OHM.
        // ceil(125e6 * 25 / 10000) = 312500 raw collateral units.
        _assertRealBorrow(100e9, 312500, 16e18);
        assertEq(
            keccak256(abi.encode(_lens.getPosition(address(other), _borrower))),
            otherPosition,
            "Other market position is untouched"
        );
        _assertMarketTotals(address(other), 100e9, 2000e6, 1);
        _assertMarketTotals(address(_asset), 100e9, 2000e6, 1);
        assertEq(_inventory.activePrincipalOhm(), 200e9, "Global principal includes both markets");
    }

    // Scenarios: BLDEBT-BORROW-P17.
    function test_givenExpiredCacheAndChangedPrice_whenBorrowed() public {
        PriceCache cache = _installPriceCache();
        _depositCollateral(2000e6);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory oldQuote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500
        );
        assertEq(oldQuote.fee, 312500, "Original one-dollar price quote");
        _expireCacheAndHalveCollateralPrice();
        // Backing requirement remains USD 125, now 250 collateral tokens.
        // ceil(250e6 * 25 / 10000) = 625000; health=2000/250=8 WAD.
        _assertRealBorrow(100e9, 625000, 8e18);
        assertEq(
            cache.getCachedPrice(address(_ohm), address(_asset)).roundId,
            2,
            "One real cache refresh"
        );
        assertEq(_position().principalDue, 100e9, "One debt settlement");
    }

    // Scenarios: BLDEBT-BORROW-P18.
    function test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts() public {
        PriceCache cache = _installPriceCache();
        _depositCollateral(2000e6);
        vm.prank(_borrower);
        uint256 originalFee = _debt
            .previewBorrow(address(_asset), 100e9, _borrower, _borrower, type(uint256).max)
            .fee;
        assertEq(originalFee, 312500, "Original fee limit derived before price change");
        _expireCacheAndHalveCollateralPrice();
        bytes32 cached = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                uint256(625000),
                originalFee
            ),
            100e9,
            _borrower,
            originalFee,
            _borrower
        );
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            cached,
            "Failed borrow restores cache round, timestamp and prices"
        );
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenRealRisk_whenBorrowed_thenIndependentFeesAndHealth(
        uint8 priceDecimals_
    ) public {
        priceDecimals_ = uint8(bound(priceDecimals_, 6, 18));
        _price.setPriceDecimals(priceDecimals_);
        _price.setPrice(address(_asset), 10 ** priceDecimals_);
        _price.setPrice(address(_ohm), 10 ** priceDecimals_);
        _depositCollateral(2000e6);
        // USD scales cancel. Required backing=100*1.25=125 assets (6 decimals).
        // ceil(125e6*25/10000)=312500 assets; health=2000/125=16 WAD.
        _assertRealBorrow(100e9, 312500, 16e18);
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenPreBorrowUtilizationAtKink_whenBorrowed_then125Bps() public {
        _openRealDebt(200_000e6, 80_000e9);
        // Pre-borrow utilization=80%; 25+100=125 bps. ceil(125e6*125/10000)=1562500.
        // Final required backing=(80000+100)*1.25=100125 assets.
        _assertRealBorrow(100e9, 1562500, 1997503121098626716);
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenPreBorrowUtilizationAboveKink_whenBorrowed_then575Bps() public {
        _openRealDebt(200_000e6, 90_000e9);
        // Utilization=90%; rate=25+100+900*(90-80)/(100-80)=575 bps.
        // ceil(125e6*575/10000)=7187500; floor(200000/112625*1e18)=1775804661487236403.
        _assertRealBorrow(100e9, 7187500, 1775804661487236403);
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenGlobalUtilizationAtKink_whenMarketBelowKink_thenMarketRate() public {
        _openRealDebt(200_000e6, 40_000e9);
        _inventory.setGlobalDebtCap(50_000e9);
        // Global utilization=80%, market=40%; rate=25+100*40/80=75 bps.
        // Fee=125e6*75/10000=937500; final backing=50125 assets.
        _assertRealBorrow(100e9, 937500, 3990024937655860349);
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenEightDecimalCollateralAndPrice_whenBorrowed_thenNativeFeeUnits() public {
        _asset = new MockERC20("Eight", "EIGHT", 8);
        _price.setPriceDecimals(8);
        _price.setPrice(address(_asset), 1e8);
        _price.setPrice(address(_ohm), 1e8);
        _admit(address(_asset));
        _asset.mint(_borrower, 3000e8);
        vm.prank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
        _depositCollateral(2000e8);
        // ceil(125e8*25/10000)=31250000 raw units of 8-decimal collateral.
        _assertRealBorrow(100e9, 31250000, 16e18);
    }

    // Scenarios: BLDEBT-BORROW-P07.
    function test_givenOneRawOhmUnit_whenBorrowed_thenFeeRoundsUpToOneCollateralUnit() public {
        _depositCollateral(1);
        // 1 raw OHM requires 1.25e-9 USD; one raw collateral is 1e-6 USD.
        // Required asset units ceil to 1; its positive fractional fee ceils to 1. Health=800 WAD.
        _assertRealBorrow(1, 1, 800e18);
    }

    function _assertRealBorrow(uint128 amount_, uint256 fee_, uint256 health_) internal {
        _retainFee();
        uint256 payer = _asset.balanceOf(_borrower);
        uint256 custody = _asset.balanceOf(address(_payout));
        uint256 wallet = _ohm.balanceOf(_borrower);
        uint256 prior = _position().principalDue;
        bytes32 beforeQuote = _stateDigest(_borrower);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            amount_,
            _borrower,
            _borrower,
            fee_
        );
        assertEq(_stateDigest(_borrower), beforeQuote, "Real quote makes no writes");
        assertEq(quote.fee, fee_, "Independent real fee quote");
        assertEq(quote.resultingHealthFactor, health_, "Independent real health quote");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            _borrower,
            address(_asset),
            _borrower,
            _borrower,
            amount_,
            fee_
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            amount_,
            _borrower,
            _borrower,
            fee_
        );
        assertEq(result.fee, fee_, "Real fee return");
        assertEq(result.resultingHealthFactor, health_, "Real health return");
        assertEq(result.resultingDebtOhm, prior + amount_, "Debt increases by actual principal");
        assertEq(
            _asset.balanceOf(_borrower),
            payer - fee_,
            "Actual payer debit matches independent fee"
        );
        assertEq(
            _asset.balanceOf(address(_payout)),
            custody + fee_,
            "Exact incoming custody transfer"
        );
        assertEq(_ohm.balanceOf(_borrower), wallet + amount_, "OHM funding once");
    }

    // Scenarios: BLDEBT-BORROW-P08, BLDEBT-BORROW-I03.
    function test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts() public {
        _openRealDebt(2000e6, 100e9);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 8 hours + 1);
        bytes32 state = _stateDigest(_borrower);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.previewBorrow(address(_asset), 1, _borrower, _borrower, type(uint256).max);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _borrower, type(uint256).max);
        assertEq(
            _stateDigest(_borrower),
            state,
            "Real pricing failure restores all ledgers, custody and allowances"
        );
    }

    // Scenarios: BLDEBT-BORROW-N06.
    function test_givenDebtBearingPosition_whenBorrowIsPreviewed_thenActionResultMatches()
        public
        givenDebtBearingPosition
    {
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            50e9,
            _borrower,
            _borrower,
            type(uint256).max
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            50e9,
            _borrower,
            _borrower,
            type(uint256).max
        );
        assertEq(
            result.resultingHealthFactor,
            quote.resultingHealthFactor,
            "Action-owned quote uses the same health rules"
        );
        assertEq(result.fee, quote.fee, "Action-owned quote uses the same fee rules");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
