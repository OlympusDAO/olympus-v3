// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario literals document PRICE, token, and WAD decimal scales. Matrix variants intentionally
// share this fixture and focused test file.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,multi-contract-file)

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";

// Contracts
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansPositionHealthFactorAtPriceBase is BurnerLoansBorrowTestBase {
    function _atPrice(
        address asset_,
        address borrower_,
        uint256 collateralUsdPrice_,
        uint256 ohmUsdPrice_
    ) internal view returns (uint256) {
        return
            burnerLoans.positionHealthFactorAtPrice(
                asset_,
                borrower_,
                collateralUsdPrice_,
                ohmUsdPrice_
            );
    }

    function _createPosition(uint128 collateral_, uint128 principal_) internal {
        _createPositionInMarket(burnerLoansConfig.marketId(address(usds)), collateral_, principal_);
    }

    function _createPositionInMarket(
        uint32 marketId_,
        uint128 collateral_,
        uint128 principal_
    ) internal {
        vm.startPrank(address(burnerLoans));
        uint64 positionId = floan.createPosition(marketId_, alice);
        if (collateral_ != 0) floan.addCollateral(positionId, collateral_);
        if (principal_ != 0)
            floan.increaseDebt(
                positionId,
                principal_,
                0,
                SafeCast.toUint48(block.timestamp + 30 days)
            );
        vm.stopPrank();
    }

    modifier givenPosition(uint128 collateral_, uint128 principal_) {
        _createPosition(collateral_, principal_);
        _;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceTest is BurnerLoansPositionHealthFactorAtPriceBase {
    function setUp() public override {
        super.setUp();
        price.setPriceDecimals(6);
        price.setPrice(address(usds), 1e6);
        price.setPrice(address(ohm), 10e6);
        backingOracle.setBacking(10e18);
    }

    // given collateral market is absent
    //   when both supplied prices are zero
    //     [X] market validation reverts before price validation
    function test_givenMissingMarket_whenPricesAreZero_reverts() public {
        address missingAsset = makeAddr("missingAsset");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                missingAsset
            )
        );
        _atPrice(missingAsset, alice, 0, 0);
    }

    // given zero address has no market
    //   when supplied prices are positive
    //     [X] market validation reverts
    function test_givenZeroAsset_whenPricesArePositive_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, address(0))
        );
        _atPrice(address(0), alice, 1e6, 10e6);
    }

    // given market exists but borrower has no position
    //   when both supplied prices are zero
    //     [X] position lookup reverts before price validation
    function test_givenMissingPosition_whenPricesAreZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PositionNotFound.selector,
                address(usds),
                alice
            )
        );
        _atPrice(address(usds), alice, 0, 0);
    }

    // given market exists but zero-address borrower has no position
    //   when supplied prices are positive
    //     [X] position lookup reverts with borrower address
    function test_givenMissingPosition_whenBorrowerIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PositionNotFound.selector,
                address(usds),
                address(0)
            )
        );
        _atPrice(address(usds), address(0), 1e6, 10e6);
    }

    // given existing position
    //   when supplied collateral price is zero
    //     [X] collateral price validation reverts
    function test_givenPosition_whenCollateralPriceIsZero_reverts()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        _atPrice(address(usds), alice, 0, 10e6);
    }

    // given existing position
    //   when supplied OHM price is zero
    //     [X] OHM price validation reverts
    function test_givenPosition_whenOhmPriceIsZero_reverts() public givenPosition(1_250e6, 100e9) {
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(ohm)));
        _atPrice(address(usds), alice, 1e6, 0);
    }

    // given existing position with zero principal
    //   when either supplied price is zero
    //     [X] price validation reverts before debt-free shortcut
    function test_givenZeroPrincipal_whenEitherPriceIsZero_reverts()
        public
        givenPosition(1_250e6, 0)
    {
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        _atPrice(address(usds), alice, 0, 10e6);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(ohm)));
        _atPrice(address(usds), alice, 1e6, 0);
    }

    // given existing position with zero principal and unavailable live prices
    //   when both supplied prices are positive
    //     [X] health is maximum without reading live pricing or backing
    function test_givenZeroPrincipal_whenPricesArePositive_returnsMaximum()
        public
        givenPosition(1_250e6, 0)
    {
        price.setPrice(address(usds), 0);
        price.setPrice(address(ohm), 0);
        backingOracle.setBacking(0);
        vm.mockCallRevert(
            address(price),
            abi.encodeWithSelector(IPRICEv2.decimals.selector),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector)
        );
        assertEq(
            _atPrice(address(usds), alice, 1, 1),
            type(uint256).max,
            "existing debt-free position has maximum health"
        );
    }

    // given existing position at health-one boundary
    //   when collateral price is below, at, or above boundary
    //     [X] health tracks each PRICE-scaled step in WAD units
    function test_givenPosition_whenPricesCrossBoundary_returnsWadHealth()
        public
        givenPosition(1_250e6, 100e9)
    {
        // 100e9 OHM * $10e6 / 1e9 = $1_000e6; backing requirement = $1_250e6.
        // 1_250e6 collateral * $1e6 / 1e6 = $1_250e6; WAD health = 1e18.
        assertEq(_atPrice(address(usds), alice, 1_000_000, 10_000_000), 1e18, "WAD boundary");
        assertEq(
            _atPrice(address(usds), alice, 999_999, 10_000_000),
            999_999e12,
            "WAD health below boundary"
        );
        assertEq(
            _atPrice(address(usds), alice, 1_000_001, 10_000_000),
            1_000_001e12,
            "WAD health above boundary"
        );
    }

    // given existing position
    //   when any caller queries borrower health
    //     [X] permissionless result is caller-independent
    function test_givenPosition_whenCallerVaries_returnsSameHealth(
        address caller_
    ) public givenPosition(1_250e6, 100e9) {
        vm.prank(caller_);
        uint256 health = _atPrice(address(usds), alice, 1e6, 10e6);
        assertEq(health, 1e18, "permissionless result independent of caller");
    }

    // given existing position and disabled policy
    //   when health is queried with supplied prices
    //     [X] read remains available
    function test_givenPosition_whenPolicyIsDisabled_returnsHealth()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.prank(emergency);
        burnerLoans.disable("");
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "disabled policy view");
    }

    // given existing position and re-enabled policy
    //   when health is queried with supplied prices
    //     [X] read remains available
    function test_givenPosition_whenPolicyIsReenabled_returnsHealth()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.prank(admin);
        burnerLoans.enable("");
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "re-enabled policy view");
    }

    // given existing position with originations toggled off and on
    //   when health is queried in either state
    //     [X] read remains available
    function test_givenPosition_whenOriginationsAreDisabled_returnsHealth()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "disabled origination view");
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "re-enabled origination view");
    }

    // given existing position past maturity
    //   when health is queried with supplied prices
    //     [X] maturity does not change numeric health
    function test_givenPosition_whenMatured_returnsSameNumericHealth()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.warp(block.timestamp + 31 days);
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "maturity is not price health");
    }

    // given existing position and different live and supplied prices
    //   when both health paths are queried
    //     [X] supplied-price health differs without changing current health
    function test_givenPosition_whenLivePricesAreDifferent_keepsCurrentHealthSeparate()
        public
        givenPosition(1_250e6, 100e9)
    {
        // Existing health uses $1e6 collateral and $10e6 OHM, yielding 1e18.
        assertEq(
            burnerLoans.positionHealthFactor(address(usds), 1_250e6, 100e9),
            1e18,
            "existing live-price health"
        );
        // The hypothetical collateral price is $2e6, so collateral value doubles.
        assertEq(_atPrice(address(usds), alice, 2e6, 10e6), 2e18, "caller-price health");
    }

    // given existing position and updated canonical backing
    //   when health is queried at same supplied prices
    //     [X] current backing changes projected health
    function test_givenPosition_whenBackingChanges_usesCurrentBacking()
        public
        givenPosition(1_250e6, 100e9)
    {
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "initial backing");
        backingOracle.setBacking(20e18);
        // 100 OHM * $20 backing * 1.25 = $2_500 required; $1_250 / $2_500 = 0.5e18.
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 0.5e18, "updated backing");
    }

    // given existing indebted position and zero canonical backing
    //   when health is queried with positive prices
    //     [X] backing validation reverts
    function test_givenPosition_whenBackingIsZero_reverts() public givenPosition(1_250e6, 100e9) {
        backingOracle.setBacking(0);
        vm.expectRevert(abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector));
        _atPrice(address(usds), alice, 1e6, 10e6);
    }

    // given existing position with incompatible market config ID
    //   when health is queried with supplied prices
    //     [X] config compatibility validation reverts
    function test_givenIncompatibleMarketConfig_whenPositionExists_reverts() public {
        bytes16 incompatibleConfigId = hex"446966666572656e7420636f6e666967";
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        _createPositionInMarket(marketId, 1_250e6, 100e9);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
                marketId,
                incompatibleConfigId
            )
        );
        _atPrice(address(usds), alice, 1e6, 10e6);
    }

    // given existing position with malformed market config data
    //   when health is queried with supplied prices
    //     [X] config decoding validation reverts
    function test_givenMalformedMarketConfig_whenPositionExists_reverts() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            hex"4275726e6572204c6f616e7320763100",
            hex"01"
        );
        _createPositionInMarket(marketId, 1_250e6, 100e9);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
                marketId,
                1
            )
        );
        _atPrice(address(usds), alice, 1e6, 10e6);
    }

    // given existing position and updated market risk config
    //   when health is queried at same supplied prices
    //     [X] current LTV requirement changes projected health
    function test_givenPosition_whenRiskConfigChanges_usesCurrentConfig()
        public
        givenPosition(1_250e6, 100e9)
    {
        IBurnerLoans.AssetRiskConfigInput memory risk = _defaultAssetRiskConfigInput();
        risk.maxLtvBps = 5_000;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), risk);
        // Market requirement = $1_000e6 / 50% = $2_000e6; $1_250 / $2_000 = 0.625e18.
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 0.625e18, "updated max LTV");
    }

    // given existing position and unavailable live PRICE observations
    //   when health is queried with positive prices
    //     [X] projection succeeds without reading live observations
    function test_givenPosition_whenLiveObservationsAreZero_usesSuppliedPrices()
        public
        givenPosition(1_250e6, 100e9)
    {
        price.setPrice(address(usds), 0);
        price.setPrice(address(ohm), 0);
        vm.mockCallRevert(
            address(price),
            abi.encodeWithSelector(IPRICEv2.observationFrequency.selector),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector)
        );
        vm.mockCallRevert(
            address(price),
            abi.encodeWithSignature("getPrice(address)"),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector)
        );
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "no live price read");
    }

    // given existing indebted position
    //   when collateral price is uint256 maximum
    //     [X] unrepresentable collateral valuation reverts
    function test_givenPosition_whenCollateralPriceIsMaximum_reverts()
        public
        givenPosition(1_250e6, 100e9)
    {
        // FullMath rejects an unrepresentable uint256 collateral value with empty revert data.
        vm.expectRevert(bytes(""));
        _atPrice(address(usds), alice, type(uint256).max, 10e6);
    }

    // given existing indebted position
    //   when OHM price is uint256 maximum
    //     [X] unrepresentable debt valuation reverts
    function test_givenPosition_whenOhmPriceIsMaximum_reverts()
        public
        givenPosition(1_250e6, 100e9)
    {
        // FullMath rejects an unrepresentable uint256 debt value with empty revert data.
        vm.expectRevert(bytes(""));
        _atPrice(address(usds), alice, 1e6, type(uint256).max);
    }

    // given existing position with zero principal
    //   when both prices are uint256 maximum
    //     [X] health is maximum without price arithmetic
    function test_givenZeroPrincipal_whenBothPricesAreMaximum_returnsMaximum()
        public
        givenPosition(1_250e6, 0)
    {
        assertEq(
            _atPrice(address(usds), alice, type(uint256).max, type(uint256).max),
            type(uint256).max,
            "zero-principal shortcut does not perform price arithmetic"
        );
    }

    // given existing position and reverting operational cache
    //   when health is queried with supplied prices
    //     [X] projection succeeds without querying cache
    function test_givenPosition_whenOperationalCacheReverts_usesSuppliedPrices()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.startPrank(admin);
        PriceCache cache = _deployPriceCache(true, true);
        burnerLoans.setPriceCache(address(cache));
        vm.stopPrank();
        vm.mockCallRevert(
            address(cache),
            abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector)
        );
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "no cache getter read");
    }

    // given existing position and fresh cache conflicting with supplied prices
    //   when current and projected health are queried
    //     [X] each path uses its own prices
    function test_givenPosition_whenFreshCacheConflicts_preservesSeparatePricePaths()
        public
        givenPosition(1_250e6, 100e9)
    {
        vm.startPrank(admin);
        PriceCache cache = _deployPriceCache(true, true);
        burnerLoans.setPriceCache(address(cache));
        vm.stopPrank();
        vm.mockCall(
            address(cache),
            abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
            abi.encode(
                IPriceCache.CachedPrice({
                    assetPriceUsd: 10e6,
                    quotePriceUsd: 2e6,
                    updatedAt: SafeCast.toUint48(block.timestamp),
                    roundId: 1
                })
            )
        );
        // Cache values collateral at $2e6, but the scenario supplies $1e6.
        assertEq(
            burnerLoans.positionHealthFactor(address(usds), 1_250e6, 100e9),
            2e18,
            "existing view consumes fresh cache"
        );
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "scenario bypasses cache");
    }

    // given existing position and duplicate collateral market
    //   when health is queried for collateral asset
    //     [X] first market position is evaluated
    function test_givenPosition_whenDuplicateMarketExists_usesFirstPosition()
        public
        givenPosition(1_250e6, 100e9)
    {
        _createDuplicateUsdsMarketForTest();
        assertEq(_atPrice(address(usds), alice, 1e6, 10e6), 1e18, "first market position");
    }

    // given existing position and six-decimal PRICE config
    //   when both supplied prices are one PRICE unit
    //     [X] health retains PRICE-to-WAD scaling
    function test_givenPosition_whenPricesAreOne_preservesPriceScale()
        public
        givenPosition(1_250e6, 100e9)
    {
        // 1_250e6 collateral * 1 / 1e6 = 1_250 PRICE units, versus $1_250e6 required.
        assertEq(_atPrice(address(usds), alice, 1, 1), 1e12, "one-unit prices stay PRICE-scaled");
    }

    // given existing position and six-decimal PRICE config
    //   when positive supplied prices vary across bounded range
    //     [X] health matches independent integer-scaled arithmetic
    function test_givenPosition_whenPositivePricesVary_matchesIndependentModel(
        uint64 collateralPrice_,
        uint64 ohmPrice_
    ) public givenPosition(1_250e6, 100e9) {
        uint256 collateralPrice = bound(uint256(collateralPrice_), 1, 20e6);
        uint256 ohmPrice = bound(uint256(ohmPrice_), 1, 20e6);
        // PRICE has 6 decimals; 1_250e6 / 1e6 = 1_250 collateral tokens.
        uint256 collateralValue = 1_250 * collateralPrice;
        // 100e9 OHM / 1e9 = 100 OHM; debt value is 100 * OHM/USD price.
        uint256 debtValue = 100 * ohmPrice;
        uint256 marketRequired = (debtValue * 10_000 + 8_499) / 8_500;
        uint256 required = marketRequired > 1_250e6 ? marketRequired : 1_250e6;
        uint256 expected = (collateralValue * 1e18) / required;
        assertEq(
            _atPrice(address(usds), alice, collateralPrice, ohmPrice),
            expected,
            "bounded price sweep matches independent PRICE-to-WAD model"
        );
    }
}

abstract contract BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase is
    BurnerLoansPositionHealthFactorAtPriceBase
{
    function _priceDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    // given equivalent economics across OHM, collateral, and PRICE decimal scales
    //   when health is queried with equivalent supplied prices
    //     [X] every scale combination returns one WAD
    function test_givenDecimalConfiguration_whenPricesAreEquivalent_returnsWadHealth() public {
        uint256 priceScale = 10 ** _priceDecimals();
        price.setPriceDecimals(_priceDecimals());
        backingOracle.setBacking(10e18);
        _createPosition(
            SafeCast.toUint128(1_250 * 10 ** _collateralDecimals()),
            SafeCast.toUint128(100 * 10 ** _ohmDecimals())
        );
        // 100 OHM * $10 = $1_000 debt; 125% backing requires $1_250.
        // 1_250 collateral * $1 = $1_250, so health is 1e18 regardless of token or PRICE scale.
        assertEq(
            _atPrice(address(usds), alice, priceScale, 10 * priceScale),
            1e18,
            "equivalent economics always return WAD health"
        );
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_9_6_18Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_9_18_6Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    // given 18-decimal backing has a remainder at six PRICE decimals
    //   when the supplied OHM price makes backing the binding requirement
    //     [X] upward backing rescaling gives exactly one WAD of health
    function test_givenFractionalBacking_whenPriceDecimalsAreSix_whenBackingRequirementBinds()
        public
    {
        price.setPriceDecimals(6);
        backingOracle.setBacking(10e18 + 1);
        _createPosition(1_250_000_125e12, 100e9);

        // Backing: ceil((10e18 + 1) * 1e6 / 1e18) = 10_000_001 (PRICE decimals).
        // Required: 100e9 / 1e9 * 10_000_001 * 12_500 / 10_000 = 1_250_000_125.
        // Collateral: 1_250_000_125e12 * 1e6 / 1e18 = 1_250_000_125 (PRICE decimals).
        // Health: floor(1_250_000_125 * 1e18 / 1_250_000_125) = 1e18 (WAD).
        assertEq(
            _atPrice(address(usds), alice, 1e6, 5e6),
            1e18,
            "fractional backing rounds up at six PRICE decimals"
        );
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_9_18_18Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_18_6_6Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_18_6_18Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_18_18_6Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

contract BurnerLoansPositionHealthFactorAtPriceDecimals_18_18_18Test is
    BurnerLoansPositionHealthFactorAtPriceDecimalsTestBase
{
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return,multi-contract-file)
