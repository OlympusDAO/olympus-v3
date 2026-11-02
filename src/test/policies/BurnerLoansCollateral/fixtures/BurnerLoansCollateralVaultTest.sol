// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansCollateralActionTest} from "./BurnerLoansCollateralActionTest.sol";
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

abstract contract BurnerLoansCollateralVaultTest is BurnerLoansCollateralActionTest {
    function _admitVault(MockERC20 token_, address vault_, bool shares_) internal {
        _price.setPrice(address(token_), 1e18);
        _depositManager.addAsset(IERC20(address(token_)), IERC4626(vault_), type(uint256).max, 0);
        _depositManager.addAssetPeriod(IERC20(address(token_)), 1, address(_core));
        _config.addAsset(
            address(token_),
            100000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            shares_
        );
    }

    function _deposit(MockERC20 token_, uint128 amount_) internal {
        token_.mint(_borrower, amount_);
        vm.startPrank(_borrower);
        token_.approve(address(_core), type(uint256).max);
        bytes32 beforeState = _accountingDigest(address(token_));
        (uint256 quote, uint256 quotedTotal, uint256 quotedHealth) = _collateral
            .previewDepositCollateral(address(token_), amount_, _borrower);
        assertEq(
            _accountingDigest(address(token_)),
            beforeState,
            "Vault preview preserves all accounting"
        );
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(token_),
            amount_,
            _borrower
        );
        // A rounded deposit may change the vault exchange rate itself. This initial
        // quote uses the pre-deposit rate; execution must book the actual post-deposit credit.
        assertEq(quotedTotal, quote, "New-position preview total equals estimated credit");
        assertEq(collateral, credit, "New-position total equals actual settled credit");
        assertEq(health, type(uint256).max, "Initial vault deposit remains debt-free");
        assertEq(quotedHealth, type(uint256).max, "Debt-free vault quote");
        assertEq(
            _lens.getPosition(address(token_), _borrower).depositedCollateral,
            credit,
            "Actual vault credit is canonical"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token_)), address(_core)),
            credit,
            "Liability uses actual vault credit"
        );
        vm.stopPrank();
    }

    function _assertVaultTopUpHealth(
        uint256 price_,
        uint256 expectedHealth_,
        uint128 debt_
    ) internal {
        MockERC20 token = new MockERC20("Whole Unit Asset", "WUA", 0);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        token.mint(address(this), 6);
        token.approve(address(vault), 2);
        vault.deposit(2, address(this));
        assertTrue(token.transfer(address(vault), 4), "Seed vault exchange rate");
        _admitVault(token, address(vault), false);
        _deposit(token, 2000);
        // floor(2000*2/6)=666 shares. Post-deposit credit=floor(666*2006/668)=1999 assets.
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            1999,
            "Independent initial vault credit"
        );
        vm.prank(_borrower);
        _debt.borrow(address(token), debt_, _borrower, _borrower, 0);
        _price.setPrice(address(token), price_);
        token.mint(_borrower, 5);
        vm.prank(_borrower);
        (uint256 quotedCredit, uint256 quotedCollateral, uint256 quotedHealth) = _collateral
            .previewDepositCollateral(address(token), 5, _borrower);
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(token),
            5,
            _borrower
        );
        // floor(5*668/2006)=1 share; actual credit=floor(1*2011/669)=3 assets.
        // Required backing=$100*1.25=$125. H=2002/125=16.016 WAD, or /32=0.5005 WAD.
        assertEq(credit, 3, "Actual credit differs from five input units");
        assertEq(collateral, 2002, "Position uses credited top-up, not nominal input");
        assertEq(health, expectedHealth_, "Independent real Risk health");
        assertEq(quotedCredit, credit, "Stable conversion credit matches quote");
        assertEq(quotedCollateral, collateral, "Stable canonical collateral matches quote");
        assertEq(quotedHealth, expectedHealth_, "Independent quoted health");
        assertEq(
            _lens.getPosition(address(token), _borrower).debtOhm,
            debt_,
            "Top-up preserves debt even below full health"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token)), address(_core)),
            2002,
            "Actual credit is authoritative for liabilities"
        );
        assertEq(
            vault.balanceOf(address(_depositManager)),
            667,
            "Exactly one new receipt-backed share"
        );
    }

    function _seedRoundedVault(
        uint128 backing_
    ) internal returns (MockERC20 token, MockERC4626 vault) {
        token = new MockERC20("Rounded", "RND", 6);
        vault = new MockERC4626(OZERC20(address(token)), "Vault", "VLT");
        token.mint(address(this), backing_);
        token.approve(address(vault), 2);
        vault.deposit(2, address(this));
        assertTrue(token.transfer(address(vault), backing_ - 2), "Seed non-1:1 exchange rate");
        _admitVault(token, address(vault), false);
    }

    function _assertRoundedVaultDeposit(
        MockERC20 token_,
        MockERC4626 vault_,
        uint128 amount_
    ) internal returns (uint128 credit) {
        uint256 prior = _lens.getPosition(address(token_), _borrower).depositedCollateral;
        uint256 priorShares = vault_.balanceOf(address(_depositManager));
        uint256 mintedShares;
        uint256 expectedCredit;
        token_.mint(_borrower, amount_);
        vm.prank(_borrower);
        token_.approve(address(_core), amount_);
        {
            uint256 backing = vault_.totalAssets();
            uint256 supply = vault_.totalSupply();
            // Raw asset/share units. Both conversions floor; the deposit can change assets/share.
            // Expected new shares = floor(A*S/B); actual Q = floor(newShares*(B+A)/(S+newShares)).
            mintedShares = (uint256(amount_) * supply) / backing;
            expectedCredit = (mintedShares * (backing + amount_)) / (supply + mintedShares);
        }
        {
            uint256 expectedQuote = (mintedShares * vault_.totalAssets()) / vault_.totalSupply();
            bytes32 beforeQuote = _accountingDigest(address(token_));
            vm.prank(_borrower);
            (uint256 q, uint256 c, uint256 h) = _collateral.previewDepositCollateral(
                address(token_),
                amount_,
                _borrower
            );
            assertEq(q, expectedQuote, "Independent pre-deposit conversion quote");
            assertEq(c, prior + expectedQuote, "Quoted total uses estimated credit");
            assertEq(h, type(uint256).max, "Debt-free quoted health");
            assertEq(
                _accountingDigest(address(token_)),
                beforeQuote,
                "Preview changes no accounting"
            );
            assertEq(
                vault_.totalAssets(),
                token_.totalSupply() - amount_,
                "Preview preserves vault backing"
            );
            assertEq(vault_.totalSupply(), priorShares + 2, "Preview mints no vault shares");
        }
        vm.expectEmit(address(_collateral));
        emit IBurnerLoansCollateral.CollateralDeposited(
            _borrower,
            address(token_),
            _borrower,
            amount_,
            uint128(expectedCredit)
        );
        vm.prank(_borrower);
        uint128 total;
        uint256 health;
        (credit, total, health) = _collateral.depositCollateral(
            address(token_),
            amount_,
            _borrower
        );
        assertEq(credit, expectedCredit, "Actual credit follows independently calculated shares");
        assertEq(total, prior + expectedCredit, "Returned collateral adds Q, never nominal input");
        assertEq(health, type(uint256).max, "Debt-free returned health");
        assertLe(credit, amount_, "Rounding cannot create collateral");
        assertEq(token_.balanceOf(_borrower), 0, "Payer funds the full nominal input");
        assertEq(token_.balanceOf(address(_core)), 0, "Core retains no transient assets");
        assertEq(token_.balanceOf(address(_depositManager)), 0, "All deposited assets enter vault");
        _assertVaultCollateral(token_, vault_, total, priorShares + mintedShares);
    }

    function _assertVaultCollateral(
        MockERC20 token_,
        MockERC4626 vault_,
        uint256 collateral_,
        uint256 shares_
    ) internal view {
        IERC20 asset = IERC20(address(token_));
        assertEq(
            _lens.getPosition(address(token_), _borrower).depositedCollateral,
            collateral_,
            "Stored collateral uses actual credit"
        );
        assertEq(
            _lens.getPosition(address(token_), _borrower).debtOhm,
            0,
            "Deposit creates no debt"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(token_))),
            collateral_,
            "Market collateral agrees with borrower"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(asset, address(_core)),
            collateral_,
            "Liabilities increase only by actual credit"
        );
        uint256 id = _depositManager.getReceiptTokenId(asset, 1, address(_core));
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), id),
            collateral_,
            "Core receipts increase only by actual credit"
        );
        assertEq(
            vault_.balanceOf(address(_depositManager)),
            shares_,
            "Vault delivers exact independently calculated shares"
        );
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(asset, address(_core));
        assertEq(shares, shares_, "Operator custody tracks actual vault shares");
        assertEq(
            assets,
            (shares_ * vault_.totalAssets()) / vault_.totalSupply(),
            "Custody assets match independent conversion"
        );
        assertGe(assets, collateral_, "Custody backs all credited liabilities");
        assertEq(
            vault_.totalAssets(),
            token_.totalSupply(),
            "Seed and deposited assets remain in vault"
        );
        assertEq(
            vault_.totalSupply(),
            shares_ + 2,
            "Vault supply increases only by minted deposit shares"
        );
    }

    function _configureCache() internal returns (PriceCache cache) {
        cache = new PriceCache(_kernel, 18, "USD");
        _kernel.executeAction(Actions.ActivatePolicy, address(cache));
        cache.enable("");
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(60);
        cache.cachePrice(address(_ohm), address(_asset));
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
