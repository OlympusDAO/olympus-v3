// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries

// Contracts
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {Actions, Policy} from "src/Kernel.sol";

import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Explicit boundary values and casts model the declared fixture domains.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)

contract BurnerLoansLensPositionHealthFactorIntegrationTest is BurnerLoansLensTest {
    // Scenarios: BLLENS-POSITION-HEALTH-P02.
    function test_givenDefaults_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        // C=$1250; debt market requirement=ceil($1000/0.85); backing=100 OHM * $10 * 1.25=$1250. H=$1250/$1250 * 1e18.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N06.
    function test_givenCollateralBelow_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        _price.setPrice(address(_healthAsset), 999_999);
        // Collateral USD=floor(1250e6 * 999999 / 1e6)=1249998750 (PRICE 6). H=floor(1249998750 * 1e18 / 1250000000)=999999000000000000.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            999_999_000_000_000_000,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N07.
    function test_givenCollateralAbove_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        _price.setPrice(address(_healthAsset), 1_000_001);
        // Collateral USD=1250001250 (PRICE 6); requirement=1250000000. H=1000001000000000000 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1_000_001_000_000_000_000,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N08.
    function test_givenZeroCollateral_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        // Zero collateral USD divided by the positive $1250 requirement gives zero health.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 0, 100e9),
            0,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N09.
    function test_givenOneRawCollateral_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        // One raw 6-decimal collateral unit is one PRICE unit. floor(1 * 1e18 / 1250000000)=800000000.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1, 100e9),
            800_000_000,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N10.
    function test_givenOneRawPrices_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        _price.setPrice(address(_healthAsset), 1);
        _price.setPrice(address(_ohm), 1);
        // Collateral USD=1250 PRICE units; backing still requires 1250000000. floor(1250 * 1e18 / 1250000000)=1000000000000.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1_000_000_000_000,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N11.
    function test_givenOhm9Asset6Price18_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 6, 18);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N12.
    function test_givenOhm9Asset18Price6_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 18, 6);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e18, 100e9),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N13.
    function test_givenOhm9Asset18Price18_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 18, 18);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e18, 100e9),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N14.
    function test_givenOhm18Asset6Price6_whenRealHealthQuoted(address caller_) public {
        _healthSetup(18, 6, 6);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e18),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N15.
    function test_givenOhm18Asset6Price18_whenRealHealthQuoted(address caller_) public {
        _healthSetup(18, 6, 18);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e18),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N16.
    function test_givenOhm18Asset18Price6_whenRealHealthQuoted(address caller_) public {
        _healthSetup(18, 18, 6);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e18, 100e18),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N17.
    function test_givenOhm18Asset18Price18_whenRealHealthQuoted(address caller_) public {
        _healthSetup(18, 18, 18);
        // Token/PRICE scales shown in the fixture arguments represent C=$1250 and D=100 OHM. Backing requires $1250, so 1250/1250 * 1e18=1e18 WAD.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e18, 100e18),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-N18.
    function test_givenBackingRoundsUp_whenRealHealthQuoted(address caller_) public {
        _healthSetup(9, 18, 6);
        _oracle.setBacking(10e18 + 1);
        _price.setPrice(address(_ohm), 5e6);
        // ceil((10e18+1)*1e6/1e18)=10000001 PRICE units per OHM. Required USD and credited collateral USD both equal 1250000125; H=1e18.
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250000125e12, 100e9),
            1e18,
            "Independent fixed health result"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Real quote emits no logs");
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P01.
    function test_givenCollateralPriceChanges_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Original fixed quote"
        );
        _price.setPrice(address(_healthAsset), 2e6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            2e18,
            "Current dependency/configuration quote"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P06.
    function test_givenOhmPriceChanges_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Original fixed quote"
        );
        _price.setPrice(address(_ohm), 20e6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            531_249_999_880_468_750,
            "Current dependency/configuration quote"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P07.
    function test_givenBackingChanges_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Original fixed quote"
        );
        _oracle.setBacking(20e18);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            5e17,
            "Current dependency/configuration quote"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P09.
    function test_givenLtvChanges_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Original fixed quote"
        );
        _config.setAssetRiskConfig(
            address(_healthAsset),
            IBurnerLoansRisk.AssetRiskConfigInput(5000, 12_500, 100, 30 days, 90 days, 1000e6)
        );
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            625_000_000_000_000_000,
            "Current dependency/configuration quote"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P10.
    function test_givenReplacementOracleChanges_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Original fixed quote"
        );
        MockOlympusBackingOracle replacement = new MockOlympusBackingOracle(20e18);
        _risk.setBackingOracle(address(replacement));
        vm.expectCall(address(_oracle), abi.encodeWithSignature("backing()"), uint64(0));
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            5e17,
            "Current dependency/configuration quote"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I04.
    function test_givenZeroCollateralPrice_whenQuoted_reverts(address caller_) public {
        _healthSetup(9, 6, 6); // Isolate Risk's value check: the PRICE mock itself rejects zero observations.
        vm.mockCall(
            address(_price),
            abi.encodeWithSignature("getPrice(address,uint8)", address(_healthAsset), uint8(0)),
            abi.encode(uint256(0), uint48(block.timestamp))
        );
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I05.
    function test_givenZeroOhmPrice_whenQuoted_reverts(address caller_) public {
        _healthSetup(9, 6, 6); // Isolate Risk's value check at the PRICE read boundary.
        vm.mockCall(
            address(_price),
            abi.encodeWithSignature("getPrice(address,uint8)", address(_ohm), uint8(0)),
            abi.encode(uint256(0), uint48(block.timestamp))
        );
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I06.
    function test_givenZeroBacking_whenQuoted_reverts(address caller_) public {
        _healthSetup(9, 6, 6);
        _oracle.setBacking(0);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-I07.
    function test_givenStalePrice_whenQuoted_reverts(address caller_) public {
        _healthSetup(9, 6, 6);
        vm.warp(block.timestamp + _price.observationFrequency() + 1);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9);
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P12.
    function test_givenReplacementPriceModule_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        MockPrice replacement = new MockPrice(_kernel, 18, 8 hours);
        replacement.setPrice(address(_ohm), 10e18);
        replacement.setPrice(address(_healthAsset), 1e18);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.expectCall(
            address(_price),
            abi.encodeWithSignature("getPrice(address,uint8)"),
            uint64(0)
        );
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            1e18,
            "Fresh PRICE pointer and decimal scale"
        );
    }

    // Scenarios: BLLENS-POSITION-HEALTH-P11.
    function test_givenReplacementActiveCache_whenQuoted(address caller_) public {
        _healthSetup(9, 6, 6);
        MockPriceCache cache = new MockPriceCache(address(_kernel));
        cache.setPriceDecimals(6);
        cache.setPriceModule(address(_price));
        cache.setUsdPrice(address(_ohm), 10e6);
        cache.setUsdPrice(address(_healthAsset), 2e6);
        cache.cachePrice(address(_ohm), address(_healthAsset));
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.isPolicyActive, (Policy(address(cache)))),
            abi.encode(true)
        );
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(1 hours);
        vm.expectCall(
            address(cache),
            abi.encodeWithSignature("cachePriceIfNecessary(address,address,uint48)"),
            uint64(0)
        );
        vm.prank(caller_);
        assertEq(
            _lens.positionHealthFactor(address(_healthAsset), 1250e6, 100e9),
            2e18,
            "Current fresh cache is used without refresh"
        );
    }

    MockERC20 internal _healthAsset;
    MockOlympusBackingOracle internal _oracle;

    function _healthSetup(uint8 ohmDecimals_, uint8 assetDecimals_, uint8 priceDecimals_) internal {
        vm.mockCall(address(_ohm), abi.encodeWithSignature("decimals()"), abi.encode(ohmDecimals_));
        MockPrice price = new MockPrice(_kernel, priceDecimals_, 8 hours);
        price.setPrice(address(_ohm), 10 * 10 ** uint256(priceDecimals_));
        price.setPrice(address(_asset), 10 ** uint256(priceDecimals_));
        _kernel.executeAction(Actions.UpgradeModule, address(price));
        _price = price;
        _oracle = new MockOlympusBackingOracle(10e18);
        BurnerLoansRisk evaluator = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(_oracle),
            address(0),
            0,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(evaluator));
        evaluator.setConfigOperator(address(_config));
        evaluator.enable("");
        _core.setRisk(address(evaluator));
        _risk = evaluator;
        _healthAsset = new MockERC20("Health asset", "H", assetDecimals_);
        _price.setPrice(address(_healthAsset), 10 ** uint256(priceDecimals_));
        _admit(address(_healthAsset));
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
