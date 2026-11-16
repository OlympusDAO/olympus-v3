// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {BurnerLoansCollateralVaultTest} from "./fixtures/BurnerLoansCollateralVaultTest.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralIntegrationTest is BurnerLoansCollateralVaultTest {
    error HealthReportFailed();

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndPriceCachePaused_whenCollateralDeposited()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        cache.disable("");
        _assertExistingDebtQuoteWithoutPricing();
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral) = _collateral.depositCollateral(
            address(_asset),
            1,
            _borrower
        );
        assertEq(credit, 1, "Paused optional cache preserves real deposit credit");
        assertEq(collateral, 2000e6 + 1, "Paused optional cache preserves canonical collateral");
        // PriceCache's getter is enabled-only; restore access before inspecting the unchanged round.
        cache.enable("");
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Paused cache is not refreshed"
        );
        _assertDirectCollateral(collateral);
    }

    // Scenarios: BLCOL-DEPOSIT-T10.
    function test_givenVaultLoss_whenExistingBorrowerDeposits_thenFinalInsolvencyRollsBack()
        public
    {
        MockERC20 token = new MockERC20("Loss Asset", "LOSS", 0);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Loss Vault", "LV");
        _admitVault(token, address(vault), false);
        _depositAsset(token, 100, _borrower);
        token.burn(address(vault), 20);
        token.mint(_borrower, 8);
        bytes32 beforeAccounting = _accountingDigest(address(token));
        uint64 beforePositions = _floan.getPositionCount();
        // 100 shares now represent 80 assets. Input 8 mints 10 shares;
        // post-deposit custody=88, while liabilities=100+8=108 raw asset units.
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(token),
                uint256(108),
                uint256(88),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token), 8, _borrower);
        assertEq(
            _accountingDigest(address(token)),
            beforeAccounting,
            "Loss top-up fully rolls back"
        );
        assertEq(_floan.getPositionCount(), beforePositions, "No extra position survives");
        assertEq(token.balanceOf(_borrower), 8, "Caller keeps rejected top-up");
        assertEq(token.balanceOf(address(vault)), 80, "Vault backing restored");
        assertEq(vault.totalSupply(), 100, "Vault share mint restored");
        assertEq(vault.balanceOf(address(_depositManager)), 100, "Custody shares restored");
    }

    // Scenarios: BLCOL-DEPOSIT-P03, BLCOL-DEPOSIT-P08.
    function test_givenRoundedVaultCredit_whenHealthyTopUp_thenRealHealthUsesActualCredit() public {
        // Actual collateral=2002 whole assets at $1; required backing=$125. H=2002/125=16.016 WAD.
        _assertVaultTopUpHealth(1e18, 16_016_000_000_000_000_000, 100e9);
    }

    // Scenarios: BLCOL-DEPOSIT-P05, BLCOL-DEPOSIT-P08.
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

    // Scenarios: BLCOL-DEPOSIT-P04, BLCOL-DEPOSIT-P08.
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
    function test_givenPriceCacheState_whenDeposited(uint8 state_) public givenDebtBearingPosition {
        state_ = uint8(bound(state_, 0, 3));
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        if (state_ == 0) vm.warp(vm.getBlockTimestamp() + 60);
        if (state_ == 1) vm.warp(vm.getBlockTimestamp() + 61);
        if (state_ == 2) _risk.setPriceCache(address(0));
        if (state_ == 3) cache.disable("");
        vm.mockCallRevert(
            address(_risk),
            bytes(""),
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        vm.mockCallRevert(
            address(_price),
            bytes(""),
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        _assertDirectDeposit(_borrower, 1, 2000e6);
        vm.clearMockedCalls();
        if (state_ == 3) cache.enable("");
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Deposit preserves cache price and timestamp in every cache state"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P10.
    function test_givenStalePrice_whenDeposited(bool ohm_) public givenDebtBearingPosition {
        vm.warp(vm.getBlockTimestamp() + 8 hours + 1);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        address staleAsset = ohm_ ? address(_ohm) : address(_asset);
        bytes memory read = abi.encodeWithSignature(
            "getPrice(address,uint8)",
            staleAsset,
            IPRICEv2.Variant.CURRENT
        );
        vm.mockCall(address(_price), read, abi.encode(uint256(1e18), uint48(1)));
        vm.expectCall(address(_price), read, uint64(0));
        _assertDirectDeposit(_borrower, 1, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P05, BLCOL-DEPOSIT-P19.
    function test_givenUnhealthyDebt_whenPartialTopUpIsDeposited() public givenDebtBearingPosition {
        _price.setPrice(address(_asset), 1e15);
        (uint256 quotedCredit, uint256 quotedCollateral) = _collateral.previewDepositCollateral(
            address(_asset),
            1e6,
            _borrower
        );
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral) = _collateral.depositCollateral(
            address(_asset),
            1e6,
            _borrower
        );
        assertEq(credit, 1e6, "Helpful top-up is credited");
        assertEq(collateral, 2001e6, "Actual top-up increases existing collateral");
        assertEq(quotedCredit, credit, "Unhealthy loan quote matches actual credit");
        assertEq(quotedCollateral, collateral, "Unhealthy loan quote matches actual collateral");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            100e9,
            "Helpful top-up preserves principal"
        );
        _assertDirectCollateral(collateral);
        // $0.001 * 2001 assets / ($100 * 1.25) = 0.016008 WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), collateral, 100e9),
            16_008_000_000_000_000,
            "Independent real unhealthy health queried after deposit"
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

    // Scenarios: BLCOL-DEPOSIT-AUTH-N01.
    function test_givenDelegatedVaultDeposit_whenNominalExceedsGrantButActualCreditEqualsCap_thenAccepted()
        public
    {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(6);
        _grantRoundedDeposit(token, 1999);
        vm.prank(_recipient);
        (uint128 credit, uint128 total) = _collateral.depositCollateral(
            address(token),
            2000,
            _borrower
        );
        // floor(2000 * 2 / 6) = 666 minted shares. After deposit:
        // floor(666 * 2006 / 668) = 1999 actual assets (6 decimal raw units).
        assertEq(credit, 1999, "Delegated cap uses actual credit rather than nominal 2000");
        assertEq(total, 1999, "Canonical resulting collateral equals grant cap");
        assertEq(
            vault.balanceOf(address(_depositManager)),
            666,
            "Custody holds actual minted shares"
        );
        assertEq(token.balanceOf(_recipient), 0, "Operator funds nominal deposit once");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            1999,
            "Liability books actual credit"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-AUTH-N02.
    function test_givenDelegatedVaultDeposit_whenActualCreditExceedsGrant_thenFullRollback()
        public
    {
        (MockERC20 token, MockERC4626 vault) = _seedRoundedVault(6);
        _grantRoundedDeposit(token, 1998);
        bytes32 beforeAccounting = _accountingDigest(address(token));
        uint256 beforeBacking = token.balanceOf(address(vault));
        uint256 beforeSupply = vault.totalSupply();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(_recipient);
        _collateral.depositCollateral(address(token), 2000, _borrower);
        assertEq(
            _accountingDigest(address(token)),
            beforeAccounting,
            "Cap rejection restores full accounting"
        );
        assertEq(token.balanceOf(_recipient), 2000, "Nominal payer transfer restored");
        assertEq(token.balanceOf(address(vault)), beforeBacking, "Vault backing restored");
        assertEq(vault.totalSupply(), beforeSupply, "Vault mint restored");
        assertEq(vault.balanceOf(address(_depositManager)), 0, "No custody shares survive");
    }

    function _grantRoundedDeposit(MockERC20 token_, uint128 cap_) internal {
        token_.mint(_recipient, 2000);
        vm.prank(_recipient);
        token_.approve(address(_core), 2000);
        IOperatorAuth.Grant memory grant = _operatorGrantForAsset(
            _borrower,
            _recipient,
            type(uint48).max,
            address(token_)
        );
        grant.actions = 1;
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxCollateral = cap_;
        grant.permissions = abi.encode(permissions);
        vm.prank(_borrower);
        _auth.approveGrant(grant);
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
    function test_givenStaleRealCacheAndZeroPrice_whenDeposited(
        bool ohm_
    ) public givenDebtBearingPosition {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setPrice(ohm_ ? address(_ohm) : address(_asset), 0);
        _assertDirectDeposit(_borrower, 1, 2000e6);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Zero feed price does not trigger cache refresh"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P07.
    function test_givenStaleCacheAndHealthUnavailable_whenDeposited()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.warp(vm.getBlockTimestamp() + 61);
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
            uint64(0)
        );
        _assertDirectDeposit(_borrower, 1, 2000e6);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            beforeCache,
            "Successful deposit neither refreshes cache nor reports health"
        );
    }

    function _assertExistingDebtQuoteWithoutPricing() internal {
        (uint256 credit, uint256 collateral) = _collateral.previewDepositCollateral(
            address(_asset),
            1,
            _borrower
        );
        assertEq(credit, 1, "Price service failure does not affect credit quote");
        assertEq(collateral, 2000e6 + 1, "Price service failure does not affect collateral quote");
    }

    // Scenarios: BLCOL-DEPOSIT-P10.
    function test_givenPriceFeedReverts_whenDeposited(bool ohm_) public givenDebtBearingPosition {
        bytes memory read = abi.encodeWithSignature(
            "getPrice(address,uint8)",
            ohm_ ? address(_ohm) : address(_asset),
            IPRICEv2.Variant.CURRENT
        );
        vm.mockCallRevert(
            address(_price),
            read,
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        vm.expectCall(address(_price), read, uint64(0));
        _assertDirectDeposit(_borrower, 1, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P09.
    function test_givenPriceCacheStateBoundarySeeds_whenDeposited() public {
        for (uint8 state; state < 4; ++state) {
            uint256 checkpoint = vm.snapshotState();
            test_givenPriceCacheState_whenDeposited(state);
            vm.clearMockedCalls();
            assertTrue(vm.revertToState(checkpoint), "Restore state between cache seeds");
        }
    }

    // Scenarios: BLCOL-DEPOSIT-D10.
    function test_givenVaultDebtAndBothOraclesUnavailable_whenDeposited(
        bool delegated_,
        bool originationsDisabled_,
        bool backingReverts_
    ) public {
        MockERC20 token = new MockERC20("Whole Unit Asset", "WUA", 0);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        token.mint(address(this), 6);
        token.approve(address(vault), 2);
        vault.deposit(2, address(this));
        assertTrue(token.transfer(address(vault), 4), "Seed vault exchange rate");
        _admitVault(token, address(vault), false);
        _deposit(token, 2000);
        vm.prank(_borrower);
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 0, address(0));
        address caller = delegated_ ? _recipient : _borrower;
        if (delegated_)
            _approveOperatorForAsset(_borrower, caller, type(uint48).max, address(token));
        if (originationsDisabled_) _config.setAssetOriginationsEnabled(address(token), false);
        address oracle = _risk.backingOracle();
        if (backingReverts_)
            vm.mockCallRevert(
                oracle,
                abi.encodeWithSignature("backing()"),
                abi.encodeWithSelector(HealthReportFailed.selector)
            );
        else MockBackingOracle(oracle).setEnabled(false);
        vm.mockCallRevert(
            address(_risk),
            bytes(""),
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        vm.mockCallRevert(
            address(_price),
            bytes(""),
            abi.encodeWithSelector(HealthReportFailed.selector)
        );
        token.mint(caller, 5);
        vm.prank(caller);
        token.approve(address(_core), 5);
        uint48 maturity = _lens.getPosition(address(token), _borrower).maturity;
        (uint256 quotedCredit, uint256 quotedTotal) = _collateral.previewDepositCollateral(
            address(token),
            5,
            _borrower
        );
        vm.expectEmit(address(_collateral));
        emit IBurnerLoansCollateral.CollateralDeposited(caller, address(token), _borrower, 5, 3);
        vm.prank(caller);
        (uint128 credit, uint128 total) = _collateral.depositCollateral(
            address(token),
            5,
            _borrower
        );
        // Before top-up: 666 of 668 shares represent 1999 assets. Five assets mint
        // floor(5*668/2006)=1 share; Q=floor(2011/669)=3, so total=1999+3=2002.
        assertEq(credit, 3, "Actual rounded credit survives both oracle failures");
        assertEq(total, 2002, "Actual credit adds once to the borrower");
        assertEq(quotedCredit, credit, "Stable conversion quote agrees");
        assertEq(quotedTotal, total, "Collateral quote agrees");
        assertEq(token.balanceOf(caller), 0, "Actual caller funds nominal input");
        assertEq(token.balanceOf(address(_core)), 0, "Core retains no transient assets");
        assertEq(vault.balanceOf(address(_depositManager)), 667, "One new share enters custody");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            total,
            "Actual credit determines liabilities"
        );
        uint256 id = _depositManager.getReceiptTokenId(IERC20(address(token)), 1, address(_core));
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), id),
            total,
            "Receipts match actual liabilities"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(token))),
            total,
            "Aggregate collateral matches position"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).debtOhm,
            100e9,
            "Principal unchanged"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).maturity,
            maturity,
            "Maturity unchanged"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-D10.
    function test_givenVaultOracleOutageBoundarySeeds_whenDeposited() public {
        for (uint8 flags; flags < 8; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenVaultDebtAndBothOraclesUnavailable_whenDeposited(
                flags & 1 != 0,
                flags & 2 != 0,
                flags & 4 != 0
            );
            vm.clearMockedCalls();
            assertTrue(vm.revertToState(checkpoint), "Restore state between vault outage seeds");
        }
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
