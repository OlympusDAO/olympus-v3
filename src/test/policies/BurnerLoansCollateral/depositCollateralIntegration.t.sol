// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansCollateralVaultTest} from "./fixtures/BurnerLoansCollateralVaultTest.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralIntegrationTest is BurnerLoansCollateralVaultTest {
    error HealthReportFailed();

    // Scenarios: BLCOL-DEPOSIT-P08.
    function test_givenRoundedVaultCredit_whenHealthyTopUp_thenRealHealthUsesActualCredit() public {
        // Actual collateral=2002 whole assets at $1; required backing=$125. H=2002/125=16.016 WAD.
        _assertVaultTopUpHealth(1e18, 16_016_000_000_000_000_000, 100e9);
    }

    // Scenarios: BLCOL-DEPOSIT-P08.
    function test_givenRoundedVaultCredit_whenPartialTopUp_thenRealHealthUsesActualCredit() public {
        // At $1/32 per asset, H=(2002/32)/125=0.5005 WAD; a helpful partial top-up succeeds.
        _assertVaultTopUpHealth(31_250_000_000_000_000, 500_500_000_000_000_000, 100e9);
    }

    // Scenarios: BLCOL-DEPOSIT-T05.
    function test_givenVaultMisreportsShares_whenDeposited_thenReceiptDeltaEnforced() public {
        MockERC20 token = new MockERC20("External Asset", "EA", 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _admitVault(token, address(vault), true);
        token.mint(_borrower, 1e18);
        vm.prank(_borrower);
        token.approve(address(_core), 1e18);
        vault.setDepositResults(1, 2);
        bytes32 rollbackState = _accountingDigest(address(token));
        _assertInitialDepositQuote(address(token), 1e18, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InexactSharesReceived.selector,
                address(token),
                vault.share(),
                uint256(2),
                uint256(1)
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token), 1e18, _borrower);
        assertEq(
            IERC20(vault.share()).balanceOf(address(_depositManager)),
            0,
            "Misreported share mint rolls back"
        );
        assertEq(token.balanceOf(_borrower), 1e18, "Underlying pull restored");
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            0,
            "No misreported collateral credit"
        );
        assertEq(
            _accountingDigest(address(token)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N06.
    function test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback(
        uint128 room_,
        uint128 amount_
    ) public {
        room_ = uint128(bound(room_, 0, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, uint256(room_) + 1, type(uint128).max));
        MockERC20 token = new MockERC20("Capped Vault Asset", "CVA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), false);
        _depositManager.setAssetDepositCap(IERC20(address(token)), room_);
        token.mint(_borrower, amount_);
        vm.prank(_borrower);
        token.approve(address(_core), amount_);
        bytes memory reason = abi.encodeWithSelector(
            IAssetManager.AssetManager_DepositCapExceeded.selector,
            address(token),
            uint256(0),
            uint256(room_)
        );
        bytes32 rollbackState = _accountingDigest(address(token));
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(token), amount_, _borrower);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token), amount_, _borrower);
        assertEq(token.balanceOf(_borrower), amount_, "Cap failure restores underlying");
        assertEq(
            vault.balanceOf(address(_depositManager)),
            0,
            "Cap failure restores minted vault shares"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            0,
            "Cap failure creates no credit"
        );
        assertEq(
            _accountingDigest(address(token)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P08.
    function test_givenRoundedVaultCredit_whenHealthExactlyOne_thenAccepted() public {
        // Final C=2002 whole assets at $0.05 = $100.10.
        // Debt=80.08 OHM at $1, backing=125% -> $100.10 required. H=1 WAD.
        _assertVaultTopUpHealth(5e16, 1e18, 80_080_000_000);
    }

    // Scenarios: BLCOL-DEPOSIT-N06.
    function test_givenVaultCap_whenOneOverRoom_thenBothPathsReject() public {
        test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback(
            type(uint128).max - 1,
            type(uint128).max
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N06.
    function test_givenVaultCapZero_whenMaximumCredit_thenBothPathsReject() public {
        test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback(
            0,
            type(uint128).max
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P09.
    function test_givenRealStaleCache_whenToppedUp_thenRefreshAndCanonicalHealthAgree()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        IPriceCache.CachedPrice memory old = cache.getCachedPrice(address(_ohm), address(_asset));
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setPrice(address(_asset), 2e18);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        vm.prank(_borrower);
        (uint256 quotedCredit, uint256 quotedCollateral, uint256 quotedHealth) = _collateral
            .previewDepositCollateral(address(_asset), 1e6, _borrower);
        assertEq(
            cache.getCachedPrice(address(_ohm), address(_asset)).updatedAt,
            old.updatedAt,
            "Preview does not refresh stale cache"
        );
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            1e6,
            _borrower
        );
        // Collateral is now 2001 assets at $2; backing requirement is $100*1.25=$125.
        // H=4002/125=32.016 WAD. These constants do not call the Risk implementation.
        assertEq(credit, 1e6, "Direct actual credit");
        assertEq(collateral, 2001e6, "Canonical post-deposit collateral");
        assertEq(health, 32016e15, "Independent refreshed health");
        assertEq(quotedCredit, credit, "Stable conversion credit agrees");
        assertEq(quotedCollateral, collateral, "Preview collateral agrees");
        assertEq(quotedHealth, health, "Fresh PRICE view and mutating cache refresh agree");
        IPriceCache.CachedPrice memory current = cache.getCachedPrice(
            address(_ohm),
            address(_asset)
        );
        assertEq(current.updatedAt, vm.getBlockTimestamp(), "Real cache records fresh observation");
        assertEq(current.assetPriceUsd, 1e18, "OHM leg unchanged");
        assertEq(current.quotePriceUsd, 2e18, "Collateral leg refreshed");
        assertEq(_asset.balanceOf(_borrower), beforeBalance - 1e6, "Actual payer debit");
        assertEq(_asset.balanceOf(address(_depositManager)), 2001e6, "Real custody credit");
    }

    // Scenarios: BLCOL-DEPOSIT-P10.
    function test_givenRealStalePrice_whenDepositQuotedOrExecuted_thenRejectsBeforeTransfers()
        public
        givenDebtBearingPosition
    {
        vm.warp(vm.getBlockTimestamp() + 8 hours + 1);
        uint256 balance = _asset.balanceOf(_borrower);
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1, _borrower);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(_asset.balanceOf(_borrower), balance, "No payer transfer on price failure");
        assertEq(_asset.balanceOf(_recipient), 0, "No output on price failure");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Canonical collateral unchanged"
        );
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Debt ledger unchanged");
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P05.
    function test_givenUnhealthyDebt_whenPartialTopUpIsDeposited_thenUnhealthyHealthIsReturned()
        public
        givenDebtBearingPosition
    {
        _price.setPrice(address(_asset), 1e15);
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            1e6,
            _borrower
        );
        assertEq(credit, 1e6, "Helpful top-up is credited");
        assertEq(collateral, 2001e6, "Actual top-up increases existing collateral");
        // $0.001 * 2001 assets / ($100 * 1.25) = 0.016008 WAD.
        assertEq(health, 16_008_000_000_000_000, "Independent real unhealthy health");
        assertEq(
            health,
            _lens.positionHealthFactor(address(_asset), collateral, 100e9),
            "Returned health agrees with canonical position"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-DEPOSIT-N04.
    function test_givenVaultRounding_whenRawInputExceedsCapAndCreditIsBelowCap_thenAccepted()
        public
    {
        _assertRoundedDepositFitsCap(4);
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-DEPOSIT-N05.
    function test_givenVaultRounding_whenRawInputExceedsCapAndCreditEqualsCap_thenAccepted()
        public
    {
        _assertRoundedDepositFitsCap(3);
    }

    function _assertRoundedDepositFitsCap(uint256 cap_) internal {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(6);
        _depositManager.setAssetDepositCap(IERC20(address(token)), cap_);
        // Two shares backed by six assets: input five mints one share; floor(11/3)=3 credit.
        assertEq(
            _assertRoundedVaultDeposit(token, vault, 5),
            3,
            "Rounded credit fits cap despite raw input five"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N03.
    function test_givenNonUnitVaultRate_whenDepositedAcrossFullRange_thenActualCreditAndCustodyAgree(
        uint128 backing_,
        uint128 amount_
    ) public {
        backing_ = uint128(bound(backing_, 3, type(uint128).max));
        // Seed supply is two. ceil(backing/2) is the least input that mints a nonzero share.
        amount_ = uint128(bound(amount_, (uint256(backing_) + 1) / 2, type(uint128).max));
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(backing_);
        _assertRoundedVaultDeposit(token, vault, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-N03.
    function test_givenExistingVaultCollateral_whenToppedUpAcrossFullRange_thenActualCreditAddsOnce(
        uint128 amount_
    ) public {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(6);
        _assertRoundedVaultDeposit(token, vault, 3);
        amount_ = uint128(bound(amount_, 3, type(uint128).max - 3));
        _assertRoundedVaultDeposit(token, vault, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-N03.
    function test_givenNonUnitVaultRate_whenCreditIsOne_thenAllReturnsAndCustodyAgree() public {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(3);
        // Input two mints floor(2*2/3)=1 share; floor(1*5/3)=1 credited asset.
        assertEq(_assertRoundedVaultDeposit(token, vault, 2), 1, "One-unit actual credit");
    }

    // Scenarios: BLCOL-DEPOSIT-N03.
    function test_givenNonUnitVaultRate_whenCreditIsMaximum_thenAllReturnsAndCustodyAgree() public {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(6);
        // MAX128 is divisible by three: conversion remains exactly three assets/share.
        assertEq(
            _assertRoundedVaultDeposit(token, vault, type(uint128).max),
            type(uint128).max,
            "Maximum actual credit"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P10.
    function test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setPrice(address(_asset), 0);
        _expectDepositRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(_asset)),
            _borrower,
            1
        );
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Failed real refresh preserves cached round, timestamp and prices"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P07.
    function test_givenRealCacheRefresh_whenFinalHealthReportFails_thenCacheAndSettlementRollBack()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_asset), 2e18);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        vm.expectCall(
            address(cache),
            abi.encodeCall(
                cache.cachePriceIfNecessary,
                (address(_ohm), address(_asset), uint48(60))
            ),
            uint64(1)
        );
        _expectDepositRevert(abi.encodeWithSelector(HealthReportFailed.selector), _borrower, 1);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Late health error restores the real refreshed cache round, prices and timestamp"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
