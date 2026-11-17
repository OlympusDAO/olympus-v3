// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unsafe-typecast, unused-return)

abstract contract BurnerLoansSeizeIntegrationTestBase is BurnerLoansDebtTest {
    enum OracleFault {
        PriceReverts,
        CacheReverts,
        BackingReverts,
        BackingPaused,
        PriceStale
    }
    enum KeeperClass {
        Ordinary,
        Heart,
        Seizer,
        Both
    }

    error PriceUnavailable();
    error CacheUnavailable();
    error BackingUnavailable();

    address internal _keeper = address(0xfee);

    function _open(
        address asset_,
        address borrower_,
        uint128 collateral_,
        uint128 principal_
    ) internal {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(0), uint256(0))
        );
        MockERC20(asset_).mint(borrower_, collateral_);
        vm.startPrank(borrower_);
        assertTrue(
            MockERC20(asset_).approve(address(_core), type(uint256).max),
            "Borrower approves Core"
        );
        _collateral.depositCollateral(asset_, collateral_, borrower_);
        _debt.borrow(asset_, principal_, borrower_, borrower_, 0, address(0));
        vm.stopPrank();
    }

    function _admitVault(
        address asset_,
        address vault_,
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        bool shares_
    ) internal {
        _price.setPrice(asset_, 1e18);
        _depositManager.addAsset(IERC20(asset_), IERC4626(vault_), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(asset_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            asset_,
            100_000e9,
            risk_,
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            shares_
        );
    }

    function _configure(address asset_, uint16 rewardBps_) internal {
        _config.setAssetRiskConfig(
            asset_,
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, rewardBps_, 30 days, 90 days, 1000)
        );
    }

    function _assertSeizure(
        address asset_,
        address token_,
        uint256 expectedReward_,
        uint256 expectedTreasury_
    ) internal {
        address[] memory borrowers = _single(_borrower);
        uint256 keeperBefore = IERC20(token_).balanceOf(_keeper);
        uint256 treasuryBefore = IERC20(token_).balanceOf(_payout.treasury());
        bytes32 beforeState = _stateDigestFor(asset_, _keeper);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            asset_,
            borrowers
        );
        assertEq(
            _stateDigestFor(asset_, _keeper),
            beforeState,
            "Preview preserves every ledger and custody component"
        );
        assertEq(quote.tokenOut, token_, "Quote uses actual output token");
        assertEq(
            quote.seizedDebtOhm,
            _lens.getPosition(asset_, _borrower).debtOhm,
            "Quote includes complete debt"
        );
        assertEq(
            quote.seizedCollateral,
            _lens.getPosition(asset_, _borrower).depositedCollateral,
            "Quote includes complete collateral"
        );
        assertEq(quote.keeperReward, expectedReward_, "Independent fixed reward");
        assertEq(quote.collateralToTreasury, expectedTreasury_, "Independent integer remainder");
        vm.prank(_keeper);
        (address output, uint256 reward, uint256 treasury) = _liquidation.seize(asset_, borrowers);
        assertEq(output, token_, "Underlying/share output identity");
        assertEq(reward, expectedReward_, "Settled fixed reward");
        assertEq(treasury, expectedTreasury_, "Settled fixed Treasury remainder");
        assertEq(
            IERC20(token_).balanceOf(_keeper),
            keeperBefore + reward + (_keeper == _payout.treasury() ? treasury : 0),
            "Exact keeper payment"
        );
        assertEq(
            IERC20(token_).balanceOf(_payout.treasury()),
            treasuryBefore + treasury + (_keeper == _payout.treasury() ? reward : 0),
            "Exact Treasury payment"
        );
        assertEq(
            _payout.pendingRecipientAmount(token_, _keeper),
            0,
            "No zero or paid keeper obligation"
        );
        _assertDefaulted(asset_, token_, quote.seizedDebtOhm);
    }

    function _single(address borrower_) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = borrower_;
    }

    function _expire() internal {
        vm.warp(vm.getBlockTimestamp() + 30 days);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_ohm), 1e18);
    }

    function _supplyOracleTestInventory(uint128 principal_) internal {
        _rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, address(this));
        _ohm.mint(address(this), principal_);
        assertTrue(_ohm.approve(address(_inventory), principal_), "Provider approves its supply");
        _inventory.supply(principal_);
    }

    function _setKeeperClass(KeeperClass keeperClass_) internal {
        if (keeperClass_ == KeeperClass.Heart || keeperClass_ == KeeperClass.Both)
            _rolesAdmin.grantRole(HEART_ROLE, _keeper);
        if (keeperClass_ == KeeperClass.Seizer || keeperClass_ == KeeperClass.Both)
            _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, _keeper);
    }

    function _prepareHealthyExpired(
        KeeperClass keeperClass_,
        bool afterMaturity_
    ) internal returns (address[] memory borrowers) {
        _supplyOracleTestInventory(100e9);
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _setKeeperClass(keeperClass_);
        vm.warp(_lens.getPosition(address(_asset), _borrower).maturity + (afterMaturity_ ? 1 : 0));
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _assertHealth(_borrower, true);
        return _single(_borrower);
    }

    function _prepareMixedHealth(
        KeeperClass keeperClass_,
        bool unexpiredSecond_,
        bool afterMaturity_,
        bool reverse_
    ) internal returns (address[] memory borrowers) {
        _supplyOracleTestInventory(200e9);
        _open(address(_asset), _borrower, 5000e6, 100e9);
        if (unexpiredSecond_) {
            vm.warp(vm.getBlockTimestamp() + 15 days);
            _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        }
        _open(address(_asset), _recipient, 2000e6, 100e9);
        _setKeeperClass(keeperClass_);
        vm.warp(_lens.getPosition(address(_asset), _borrower).maturity + (afterMaturity_ ? 1 : 0));
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_ohm), 25e18);
        // At 85% LTV, 100 OHM * $25 / 0.85 requires ceil($2941.176...).
        // $5000 is healthy; $2000 is unhealthy. These are real reads BEFORE any fault.
        _assertHealth(_borrower, true);
        _assertHealth(_recipient, false);
        assertEq(
            vm.getBlockTimestamp() < _lens.getPosition(address(_asset), _recipient).maturity,
            unexpiredSecond_,
            "Second maturity matches the scenario"
        );
        borrowers = new address[](2);
        borrowers[reverse_ ? 1 : 0] = _borrower;
        borrowers[reverse_ ? 0 : 1] = _recipient;
    }

    function _assertHealth(address borrower_, bool healthy_) internal view {
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), borrower_);
        uint256 health = _risk.health(
            _risk.snapshot(address(_asset)),
            _core.marketId(address(_asset)),
            position.depositedCollateral,
            position.debtOhm
        );
        assertEq(health >= 1e18, healthy_, "Economic fixture has the stated health");
    }

    function _injectOracleFault(OracleFault fault_) internal returns (bytes memory reason) {
        if (fault_ == OracleFault.PriceReverts) {
            reason = abi.encodeWithSelector(PriceUnavailable.selector);
            vm.mockCallRevert(
                address(_price),
                abi.encodeWithSignature("getPrice(address,uint8)"),
                reason
            );
        } else if (fault_ == OracleFault.CacheReverts) {
            PriceCache cache = _installSeizurePriceCache();
            reason = abi.encodeWithSelector(CacheUnavailable.selector);
            vm.mockCallRevert(
                address(cache),
                abi.encodeWithSelector(IPriceCache.cachePriceIfNecessary.selector),
                reason
            );
            vm.mockCallRevert(
                address(cache),
                abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
                reason
            );
        } else if (fault_ == OracleFault.BackingReverts) {
            reason = abi.encodeWithSelector(BackingUnavailable.selector);
            vm.mockCallRevert(_risk.backingOracle(), abi.encodeWithSignature("backing()"), reason);
        } else if (fault_ == OracleFault.BackingPaused) {
            MockBackingOracle(_risk.backingOracle()).setEnabled(false);
            reason = abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                _risk.backingOracle()
            );
        } else {
            // Exactly one second outside PRICE's inclusive freshness window.
            _price.setTimestamp(uint48(vm.getBlockTimestamp() - _price.observationFrequency() - 1));
            reason = abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        }
    }

    function _oracleBatchDigest(
        address[] memory borrowers_
    ) internal view returns (bytes32 digest) {
        digest = keccak256(
            abi.encode(
                _stateDigestFor(address(_asset), _keeper),
                _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
                _core.totalActiveDebtOhm(),
                _inventory.availableCapacity(),
                _inventory.suppliedOhm(),
                _inventory.suppliedIdleOhm(),
                _asset.balanceOf(_payout.treasury()),
                _payout.pendingRecipientAmount(address(_asset), _keeper)
            )
        );
        for (uint256 i; i < borrowers_.length; ++i)
            digest = keccak256(
                abi.encode(
                    digest,
                    _lens.getPosition(address(_asset), borrowers_[i]),
                    _inventory.providerClaimOhm(borrowers_[i])
                )
            );
    }

    function _assertBatchDefaulted(address[] memory borrowers_, uint256 debt_) internal view {
        _assertDefaulted(address(_asset), address(_asset), debt_);
        for (uint256 i; i < borrowers_.length; ++i) {
            assertEq(
                _lens.getPosition(address(_asset), borrowers_[i]).debtOhm,
                0,
                "Every selected debt is cleared"
            );
            assertEq(
                _lens.getPosition(address(_asset), borrowers_[i]).depositedCollateral,
                0,
                "Every selected collateral record is cleared"
            );
        }
    }

    function _prepareDebtFreeSelection(
        KeeperClass keeperClass_,
        bool existing_,
        bool emptyFirst_
    ) internal returns (address[] memory borrowers) {
        _prepareHealthyExpired(keeperClass_, false);
        if (existing_) {
            uint32 market = _core.marketId(address(_asset));
            vm.prank(address(_core));
            _floan.createPosition(market, _recipient);
        }
        borrowers = new address[](2);
        borrowers[emptyFirst_ ? 1 : 0] = _borrower;
        borrowers[emptyFirst_ ? 0 : 1] = _recipient;
    }

    function _installSeizurePriceCache() internal returns (PriceCache cache) {
        cache = new PriceCache(_kernel, 18, "USD");
        _kernel.executeAction(Actions.ActivatePolicy, address(cache));
        cache.enable("");
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(60);
        cache.cachePrice(address(_ohm), address(_asset));
    }

    function _expectNoSeizurePricing() internal {
        vm.expectCall(address(_price), bytes(""), uint64(0));
        vm.expectCall(_risk.backingOracle(), bytes(""), uint64(0));
        address cache = _risk.priceCache();
        if (cache != address(0)) vm.expectCall(cache, bytes(""), uint64(0));
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
    }

    function _assertOracleFreeSeizure(
        address[] memory borrowers_,
        uint256 debt_,
        uint256 collateral_
    ) internal {
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint256 keeperBefore = _asset.balanceOf(_keeper);
        uint256 capacityBefore = _inventory.availableCapacity();
        uint256 claimBefore = _inventory.providerClaimOhm(address(this));
        uint256 suppliedBefore = _inventory.suppliedOhm();
        uint256 idleBefore = _inventory.suppliedIdleOhm();
        for (uint256 i; i < borrowers_.length; ++i) {
            assertTrue(
                _lens.isSeizable(address(_asset), borrowers_[i]),
                "Maturity establishes eligibility"
            );
            vm.expectEmit(true, true, true, true, address(_core));
            emit IBurnerLoansCore.Seized(
                _keeper,
                address(_asset),
                borrowers_[i],
                100e9,
                borrowers_.length == 1 ? 2000e6 : (borrowers_[i] == _borrower ? 5000e6 : 2000e6)
            );
        }
        _expectNoSeizurePricing();
        vm.expectEmit(true, true, false, true, address(_core));
        emit IBurnerLoansCore.SeizureBatchSettled(
            _keeper,
            address(_asset),
            borrowers_.length,
            debt_,
            collateral_,
            address(_asset),
            0,
            collateral_
        );

        vm.prank(_keeper);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            borrowers_
        );

        // Underlying collateral redeems 1:1; zero reward allocates the full output to Treasury.
        assertEq(token, address(_asset), "Settlement returns underlying collateral");
        assertEq(reward, 0, "Protocol keeper receives no reward");
        assertEq(treasury, collateral_, "All collateral belongs to Treasury");
        assertEq(_asset.balanceOf(_keeper), keeperBefore, "No keeper payment");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + collateral_,
            "Treasury paid"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "Collateral leaves custody");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            0,
            "Market debt cleared"
        );
        assertEq(_inventory.availableCapacity(), capacityBefore + debt_, "Debt cap room released");
        assertEq(
            _inventory.providerClaimOhm(address(this)),
            claimBefore,
            "Default preserves the nonzero provider claim"
        );
        assertEq(
            _inventory.suppliedOhm(),
            suppliedBefore,
            "Default preserves total provider claims"
        );
        assertEq(_inventory.suppliedIdleOhm(), idleBefore, "Default does not invent idle OHM");
        _assertBatchDefaulted(borrowers_, debt_);
    }

    function _assertOracleFreePreview(
        address[] memory borrowers_,
        uint256 debt_,
        uint256 collateral_
    ) internal {
        bytes32 beforeState = _oracleBatchDigest(borrowers_);
        _expectNoSeizurePricing();
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_asset),
            borrowers_
        );

        assertEq(quote.tokenOut, address(_asset), "Quote returns underlying collateral");
        assertEq(quote.seizedDebtOhm, debt_, "Quote includes all expired principal");
        assertEq(quote.seizedCollateral, collateral_, "Quote includes all deposited collateral");
        assertEq(quote.keeperReward, 0, "Protocol keeper quote has no reward");
        assertEq(
            quote.collateralToTreasury,
            collateral_,
            "Quote allocates all collateral to Treasury"
        );
        assertEq(_oracleBatchDigest(borrowers_), beforeState, "Preview preserves state");
    }

    function _assertOracleFailure(address[] memory borrowers_, bytes memory reason_) internal {
        // Execution identifies the refresh stage; the view keeps its original dependency error.
        _assertSeizureRejection(
            borrowers_,
            reason_,
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector,
                reason_
            )
        );
    }

    function _assertAdmissionFailure(address[] memory borrowers_, bytes memory reason_) internal {
        _assertSeizureRejection(borrowers_, reason_, reason_);
    }

    function _assertSeizureRejection(
        address[] memory borrowers_,
        bytes memory previewReason_,
        bytes memory executionReason_
    ) private {
        bytes32 beforeState = _oracleBatchDigest(borrowers_);
        vm.expectRevert(previewReason_);
        _liquidation.previewSeizeFor(_keeper, address(_asset), borrowers_);
        assertEq(_oracleBatchDigest(borrowers_), beforeState, "Rejected quote preserves state");
        vm.expectRevert(executionReason_);
        vm.prank(_keeper);
        _liquidation.seize(address(_asset), borrowers_);
        assertEq(
            _oracleBatchDigest(borrowers_),
            beforeState,
            "Pricing failure rolls back the entire batch"
        );
    }

    function _protocolClass(bool heart_, bool overlap_) internal pure returns (KeeperClass) {
        return overlap_ ? KeeperClass.Both : (heart_ ? KeeperClass.Heart : KeeperClass.Seizer);
    }

    function _assertPricedBatch(address[] memory borrowers_, uint256 expectedReward_) internal {
        uint256 claimBefore = _inventory.providerClaimOhm(address(this));
        uint256 suppliedBefore = _inventory.suppliedOhm();
        uint256 idleBefore = _inventory.suppliedIdleOhm();
        bytes32 beforeState = _oracleBatchDigest(borrowers_);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint256 keeperBefore = _asset.balanceOf(_keeper);
        uint256 capacityBefore = _inventory.availableCapacity();
        vm.expectCall(address(_risk), abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector));
        vm.expectCall(address(_risk), abi.encodeWithSelector(IBurnerLoansRisk.health.selector));
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_asset),
            borrowers_
        );
        assertEq(
            _oracleBatchDigest(borrowers_),
            beforeState,
            "Priced preview preserves every selected position"
        );
        assertEq(quote.tokenOut, address(_asset), "Preview identifies underlying output");
        assertEq(quote.seizedDebtOhm, 200e9, "Preview includes both debts");
        assertEq(quote.seizedCollateral, 7000e6, "Preview includes both collateral balances");
        assertEq(quote.keeperReward, expectedReward_, "Independent backing-capped reward");
        assertEq(
            quote.collateralToTreasury,
            7000e6 - expectedReward_,
            "Independent Treasury remainder"
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector)
        );
        vm.expectCall(address(_risk), abi.encodeWithSelector(IBurnerLoansRisk.health.selector));
        vm.prank(_keeper);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            borrowers_
        );
        assertEq(token, quote.tokenOut, "Execution and preview output agree");
        assertEq(reward, quote.keeperReward, "Execution and preview reward agree");
        assertEq(treasury, quote.collateralToTreasury, "Execution and preview Treasury agree");
        assertEq(
            _asset.balanceOf(_keeper),
            keeperBefore + reward,
            "Keeper receives exactly its capped reward"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + treasury,
            "Treasury receives the remainder"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            0,
            "No selected collateral remains in custody"
        );
        assertEq(
            _inventory.availableCapacity(),
            capacityBefore + 200e9,
            "Both principals release debt-cap room"
        );
        assertEq(
            _inventory.providerClaimOhm(address(this)),
            claimBefore,
            "Default preserves the provider claim"
        );
        assertEq(_inventory.suppliedOhm(), suppliedBefore, "Default preserves supplied claims");
        assertEq(
            _inventory.suppliedIdleOhm(),
            idleBefore,
            "Default does not restore lent OHM as idle"
        );
        _assertBatchDefaulted(borrowers_, 200e9);
    }

    function _assertDefaulted(address asset_, address token_, uint256 debt_) internal view {
        assertEq(_inventory.activePrincipalOhm(), 0, "Default reconciles principal once");
        assertEq(_core.totalActiveDebtOhm(), 0, "Core aggregate debt cleared");
        assertEq(_lens.getPosition(asset_, _borrower).debtOhm, 0, "Position debt cleared");
        assertEq(
            _lens.getPosition(asset_, _borrower).depositedCollateral,
            0,
            "Position collateral cleared"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(asset_)),
            debt_,
            "Default booked exactly once"
        );
        assertEq(_floan.getActiveBorrowerCount(_core.marketId(asset_)), 0, "Active index cleared");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(asset_), address(_core)),
            0,
            "DM liabilities cleared"
        );
        uint256 receipt = _depositManager.getReceiptTokenId(IERC20(asset_), 1, address(_core));
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), receipt),
            0,
            "Selected receipt custody clears"
        );
        assertEq(
            _depositManager.getBorrowedAmount(IERC20(asset_), address(_core)),
            0,
            "No collateral remains borrowed from custody"
        );
        (uint256 fee, , uint256 seized, , uint256 total) = _payout.pendingAmounts(token_);
        assertEq(fee, 0, "No fee created by default");
        assertEq(seized, 0, "No paid Treasury reserve");
        assertEq(total, 0, "No paid reserve remains");
        assertEq(IERC20(token_).balanceOf(address(_payout)), 0, "No retained output");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unsafe-typecast, unused-return)
