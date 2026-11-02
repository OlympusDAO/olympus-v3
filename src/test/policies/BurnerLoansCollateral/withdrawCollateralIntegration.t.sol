// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {BurnerLoansCollateralVaultTest} from "./fixtures/BurnerLoansCollateralVaultTest.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/mocks/MockERC7575Vault.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralWithdrawCollateralIntegrationTest is BurnerLoansCollateralVaultTest {
    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N08, BLCOL-WITHDRAW-N09.
    function _withdrawSynchronousVault(
        bool shares_,
        uint128 collateral_,
        uint128 amount_
    ) internal {
        collateral_ = uint128(bound(collateral_, 1, type(uint128).max));
        amount_ = uint128(bound(amount_, 1, collateral_));
        MockERC20 token = new MockERC20("Vault Asset", "VA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), shares_);
        vm.prank(_borrower);
        (uint256 q, uint256 c, uint256 h) = _collateral.previewDepositCollateral(
            address(token),
            collateral_,
            _borrower
        );
        assertEq(q, collateral_, "Independent 1:1 vault deposit credit");
        assertEq(c, collateral_, "Independent projected vault collateral");
        assertEq(h, type(uint256).max, "Independent debt-free vault health");
        _deposit(token, collateral_);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            amount_,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(token),
            amount_,
            _borrower,
            _recipient
        );
        address output = shares_ ? address(vault) : address(token);
        assertEq(result.returnToken, output, "Selected underlying/share token");
        assertEq(result.returnAmount, amount_, "Independent 1:1 output");
        assertEq(quote.returnAmount, amount_, "Stable conversion quote");
        assertEq(IERC20(output).balanceOf(_recipient), amount_, "Actual recipient output");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            uint256(collateral_) - amount_,
            "Liability debit uses credited units"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            uint256(collateral_) - amount_,
            "Canonical remaining collateral"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N09.
    function test_givenExternalSharesWithSameDecimals_whenWithdrawn_thenExternalTokenDelivered()
        public
    {
        MockERC20 token = new MockERC20("External Asset", "EA", 18);
        MockERC7575Vault vault = new MockERC7575Vault(OZERC20(address(token)), true);
        _admitVault(token, address(vault), true);
        _deposit(token, 1000e18);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        assertEq(result.returnToken, vault.share(), "External share token, not vault address");
        assertEq(result.returnAmount, 400e18, "Same-decimal shares");
        assertEq(quote.returnAmount, result.returnAmount, "Share quote matches");
        assertEq(IERC20(vault.share()).balanceOf(_recipient), 400e18, "External shares delivered");
    }

    // Scenarios: BLCOL-WITHDRAW-N09.
    function test_givenExternalSharesWithDifferentDecimals_whenWithdrawn_thenUnitsPreserved()
        public
    {
        MockERC20 token = new MockERC20("External Asset", "EA", 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _admitVault(token, address(vault), true);
        _deposit(token, 1000e18);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        // 400e18 native assets / 1e12 assets per raw share = 400e6 raw external shares.
        assertEq(result.returnToken, vault.share(), "External share identity");
        assertEq(result.returnAmount, 400e6, "18-decimal assets become 6-decimal shares");
        assertEq(quote.returnAmount, 400e6, "Independent conversion quote");
        assertEq(IERC20(vault.share()).decimals(), 6, "Output decimals differ from underlying");
        assertEq(
            IERC20(vault.share()).balanceOf(_recipient),
            400e6,
            "Actual 6-decimal share receipt"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            600e18,
            "Collateral remains denominated in underlying units"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-T01.
    function test_givenWithdrawalRoundsToZero_whenQuotedOrExecuted_thenRejectAndRollback() public {
        MockERC20 token = new MockERC20("Tiny Asset", "TA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), true);
        _deposit(token, 2);
        token.mint(address(vault), 2);
        // Two shares backed by four assets: floor(1 asset * 2 shares / 4 assets)=0 shares.
        bytes32 rollbackState = _accountingDigest(address(token));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal.selector);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(token), 1, _borrower, _recipient);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(token), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            2,
            "Zero output restores collateral debit"
        );
        assertEq(vault.balanceOf(address(_depositManager)), 2, "Zero output restores shares");
        assertEq(
            _accountingDigest(address(token)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-T03.
    function test_givenVaultLoss_whenWithdrawn_thenDepositManagerEnforcesPostExitSolvency() public {
        MockERC20 token = new MockERC20("Loss Asset", "LA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), false);
        _deposit(token, 2);
        token.burn(address(vault), 1);
        // Two shares now back one asset. Withdrawing one asset burns both shares, leaving
        // one credited liability and zero assets: the exact post-exit shortfall is (1,0,0).
        bytes32 rollbackState = _accountingDigest(address(token));
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(token),
                uint256(1),
                uint256(0),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(token), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            2,
            "Solvency failure restores FLOAN collateral"
        );
        assertEq(token.balanceOf(_recipient), 0, "Solvency failure restores output transfer");
        assertEq(
            vault.balanceOf(address(_depositManager)),
            2,
            "Solvency failure restores receipt-backed shares"
        );
        assertEq(
            _accountingDigest(address(token)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N08, BLCOL-WITHDRAW-N09.
    function test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved() public {
        _withdrawSynchronousVault(true, type(uint128).max, type(uint128).max);
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N08, BLCOL-WITHDRAW-N09.
    function test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput() public {
        _withdrawSynchronousVault(false, 1, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-T04, BLCOL-WITHDRAW-P02.
    function test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers()
        public
        givenDebtBearingPosition
    {
        vm.warp(block.timestamp + 8 hours + 1);
        uint256 balance = _asset.balanceOf(_borrower);
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(_asset), 1, _borrower, _recipient);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
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

    // Scenarios: BLCOL-WITHDRAW-N05, BLCOL-WITHDRAW-P01.
    function test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral()
        public
        givenDebtBearingPosition
    {
        uint128 amount_ = 100e6;
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        assertEq(actual.remainingDepositedCollateral, 1900e6, "Settlement debits exact collateral");
        assertEq(
            actual.resultingHealthFactor,
            quote.resultingHealthFactor,
            "Stable-price view and settlement health agree"
        );
        // Both prices are $1: backing requirement is $100*1.25=$125=125e6 raw assets.
        // Withdraw 100 assets: remaining=$1,900; H=1900/125=15.2 WAD exactly.
        assertEq(
            actual.resultingHealthFactor,
            15_200_000_000_000_000_000,
            "Independent health of actual remaining collateral"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-P01, BLCOL-WITHDRAW-N04.
    function test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted()
        public
        givenDebtBearingPosition
    {
        // $100 debt * 125% = $125 required; 2000 - 1875 = 125 assets, so H=1 WAD.
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1875e6,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_asset),
            1875e6,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(_asset), 1875e6, 125e6, 1e18);
        _assertWithdrawal(actual, address(_asset), 1875e6, 125e6, 1e18);
        _assertDirectCollateral(125e6);
    }

    // Scenarios: BLCOL-WITHDRAW-P01, BLCOL-WITHDRAW-N03.
    function test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback()
        public
        givenDebtBearingPosition
    {
        // 124999999 / 125000000 * 1e18 = 999999992000000000, rounded down.
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                uint256(999_999_992_000_000_000)
            ),
            _borrower,
            1875e6 + 1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N08, BLCOL-WITHDRAW-N09.
    function test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed() public {
        MockERC20 token = new MockERC20("Yield asset", "YA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), true);
        _deposit(token, 10);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            2,
            _borrower,
            _recipient
        );
        token.mint(address(vault), 10);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(token),
            2,
            _borrower,
            _recipient
        );
        // Quote: ten shares / ten assets -> two shares. After yield: ten/twenty -> one share.
        _assertWithdrawal(quote, address(vault), 2, 8, type(uint256).max);
        _assertWithdrawal(actual, address(vault), 1, 8, type(uint256).max);
        assertEq(
            vault.balanceOf(_recipient),
            1,
            "Actual native share output, not the earlier quote"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            8,
            "Liability debited in asset units"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N08.
    function test_givenRepeatedPartialWithdrawals_whenLastCreditConsumed_thenExactlyExhausted()
        public
    {
        MockERC20 token = new MockERC20("Partial asset", "PA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), false);
        _deposit(token, 10);
        for (uint128 remaining = 10; remaining != 0; remaining -= 2) {
            vm.prank(_borrower);
            IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral
                .previewWithdrawCollateral(address(token), 2, _borrower, _recipient);
            vm.prank(_borrower);
            IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
                address(token),
                2,
                _borrower,
                _recipient
            );
            _assertWithdrawal(quote, address(token), 2, remaining - 2, type(uint256).max);
            _assertWithdrawal(actual, address(token), 2, remaining - 2, type(uint256).max);
        }
        assertEq(token.balanceOf(_recipient), 10, "Sum of independent partial outputs");
        assertEq(vault.balanceOf(address(_depositManager)), 0, "All credited shares exhausted");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            0,
            "No orphan liability"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-T01.
    function test_givenDebtAndSubShareOutput_whenWithdrawn_thenBothPathsReject() public {
        MockERC20 token = new MockERC20("Tiny debt asset", "TDA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _admitVault(token, address(vault), true);
        _deposit(token, 2);
        vm.prank(_borrower);
        _debt.borrow(address(token), 1, _borrower, _borrower, 0);
        token.mint(address(vault), 2);
        bytes32 beforeState = _accountingDigest(address(token));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal.selector);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(token), 1, _borrower, _recipient);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(token), 1, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(token)),
            beforeState,
            "Sub-share failure preserves live debt and collateral"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N09.
    function test_givenAsynchronousVaultDrift_whenUnderlyingRequested_thenBothPathsReject() public {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _synchronousExternalPosition();
        vault.setCapabilities(false, true, true, true);
        _expectUnderlyingModeRejected(token, address(vault));
    }

    // Scenarios: BLCOL-WITHDRAW-N09.
    function test_givenExplicitWarmupRequirement_whenUnderlyingRequested_thenBothPathsReject()
        public
    {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _synchronousExternalPosition();
        _depositManager.setAssetShareWithdrawalRequired(IERC20(address(token)), true);
        _expectUnderlyingModeRejected(token, address(vault));
    }

    // Scenarios: BLCOL-WITHDRAW-N09.
    function test_givenAsynchronousVaultDrift_whenSharesRequested_thenExitRemainsAvailable()
        public
    {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _synchronousExternalPosition();
        vault.setCapabilities(false, true, true, true);
        _config.setAssetWithdrawAsShares(address(token), true);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(token),
            400e18,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, vault.share(), 400e6, 600e18, type(uint256).max);
        _assertWithdrawal(actual, vault.share(), 400e6, 600e18, type(uint256).max);
        assertEq(
            IERC20(vault.share()).balanceOf(_recipient),
            400e6,
            "Async vault delivers external shares"
        );
    }

    function _synchronousExternalPosition()
        internal
        returns (MockERC20 token, MockERC7540ExternalShareVault vault)
    {
        token = new MockERC20("External asset", "EA", 18);
        vault = new MockERC7540ExternalShareVault(OZERC20(address(token)), false, false, true);
        _admitVault(token, address(vault), false);
        _deposit(token, 1000e18);
    }

    function _expectUnderlyingModeRejected(MockERC20 token_, address vault_) internal {
        bytes32 beforeState = _accountingDigest(address(token_));
        bytes memory reason = abi.encodeWithSelector(
            IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
            address(token_),
            vault_
        );
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(token_), 400e18, _borrower, _recipient);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(token_), 400e18, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(token_)),
            beforeState,
            "Incompatible output mode fully rolls back"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N08.
    function test_givenSynchronousVault_whenUnderlyingWithdrawn(
        uint128 collateral_,
        uint128 amount_
    ) public {
        _withdrawSynchronousVault(false, collateral_, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N09.
    function test_givenSynchronousVault_whenSharesWithdrawn(
        uint128 collateral_,
        uint128 amount_
    ) public {
        _withdrawSynchronousVault(true, collateral_, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N08.
    function test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn() public {
        _withdrawSynchronousVault(false, type(uint128).max, type(uint128).max);
    }

    // Scenarios: BLCOL-DEPOSIT-N03, BLCOL-WITHDRAW-N09.
    function test_givenOneVaultUnit_whenSharesWithdrawn() public {
        _withdrawSynchronousVault(true, 1, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-P02, BLCOL-WITHDRAW-T04.
    function test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack()
        public
        givenDebtBearingPosition
    {
        PriceCache cache = _configureCache();
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        vm.warp(block.timestamp + 61);
        _price.setPrice(address(_asset), 0);
        _expectWithdrawRevert(
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
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
