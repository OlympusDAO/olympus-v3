// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansSeizeIntegrationTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeIntegrationTestBase.sol";
import {SeizeRedemptionFeeVault} from "src/test/policies/BurnerLoansSeize/fixtures/SeizeRedemptionFeeVault.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// Nonzero role recipients are constrained with vm.assume.
// forge-lint: disable-start(literal-instead-of-constant, missing-zero-check, reentrancy-no-eth, unsafe-typecast, unused-return)

contract BurnerLoansSeizeIntegrationTest is BurnerLoansSeizeIntegrationTestBase {
    // Scenarios: BLLIQ-SEIZE-N01, BLLIQ-SEIZE-P18.
    function test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward() public {
        _configure(address(_asset), 100);
        _open(address(_asset), _borrower, 99, 1);
        // 99 raw assets * 100/10000 = 0.99, floored to 0. Backing ceil(1 OHM-wei / 1000)=1 asset-wei.
        _expire();
        _assertSeizure(address(_asset), address(_asset), 0, 99);
    }

    // Scenarios: BLLIQ-SEIZE-N03, BLLIQ-SEIZE-P18.
    function test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation() public {
        _configure(address(_asset), 9999);
        _open(address(_asset), _borrower, 2, 1);
        // floor(2 * 9999/10000)=1; Treasury=2-1=1. Never separately round the remainder fraction.
        _expire();
        _assertSeizure(address(_asset), address(_asset), 1, 1);
    }

    // Scenarios: BLLIQ-SEIZE-P13, BLLIQ-SEIZE-P14.
    function test_givenProtocolKeeper_whenSeized_thenNoReward(
        bool heart_,
        bool overlap_,
        address keeper_,
        address viewCaller_
    ) public {
        vm.assume(keeper_ != address(0));
        _keeper = keeper_;
        _configure(address(_asset), 9999);
        _open(address(_asset), _borrower, 2, 1);
        _rolesAdmin.grantRole(heart_ ? HEART_ROLE : BURNER_LOANS_SEIZER_ROLE, _keeper);
        if (overlap_)
            _rolesAdmin.grantRole(heart_ ? BURNER_LOANS_SEIZER_ROLE : HEART_ROLE, _keeper);
        _expire();
        vm.prank(viewCaller_);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_asset),
            _single(_borrower)
        );
        assertEq(
            quote.keeperReward,
            0,
            "Explicit actor roles determine quote independently of view caller"
        );
        _assertSeizure(address(_asset), address(_asset), 0, 2);
    }

    // Scenarios: BLLIQ-SEIZE-I04, BLLIQ-SEIZE-P19.
    function test_givenMaturedDebt_givenOrdinaryKeeper_givenRealPriceStale_whenSeized_reverts()
        public
    {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        vm.warp(vm.getBlockTimestamp() + 30 days);
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        bytes32 beforeState = _stateDigestFor(address(_asset), _keeper);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        _liquidation.previewSeizeFor(_keeper, address(_asset), borrowers);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_keeper);
        _liquidation.seize(address(_asset), borrowers);
        assertEq(
            _stateDigestFor(address(_asset), _keeper),
            beforeState,
            "Real price failure restores every ledger and custody component"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Price rejection leaves funding ledger unchanged"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "No redemption without snapshot"
        );
    }

    // Scenarios: BLLIQ-SEIZE-P13, BLLIQ-SEIZE-P14.
    function test_givenEachProtocolRole_whenSeized_thenNoReward() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenProtocolKeeper_whenSeized_thenNoReward(true, false, address(0x101), address(0));
        assertTrue(vm.revertToState(checkpoint), "Restore for seizer-only role");
        test_givenProtocolKeeper_whenSeized_thenNoReward(false, false, address(0x102), _borrower);
        assertTrue(vm.revertToState(checkpoint), "Restore for overlapping roles");
        test_givenProtocolKeeper_whenSeized_thenNoReward(
            false,
            true,
            address(0x103),
            address(this)
        );
    }

    // Scenarios: BLLIQ-SEIZE-R02, BLLIQ-SEIZE-P18.
    function test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking()
        public
    {
        MockERC20 token = new MockERC20("Fee collateral", "FC", 6);
        SeizeRedemptionFeeVault vault = new SeizeRedemptionFeeVault(OZERC20(address(token)));
        _admitVault(
            address(token),
            address(vault),
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            false
        );
        _open(address(token), _borrower, 2000e6, 100e9);
        // Vault yield keeps total operator custody solvent even after the redemption fee.
        // Two assets per share makes the 2000e6 withdrawal convert to exactly 1000e6 shares.
        token.mint(address(vault), 2000e6);
        vault.chargeRedemptionFee();
        MockBackingOracle(_risk.backingOracle()).setBacking(15e18);
        // 2000e6 collateral redeems to 1800e6 after 10% fee.
        // Required backing = 100e9 OHM * $15 * 12500/10000 / 1e9 = $1875 -> 1875e6 assets.
        // Actual output is below backing, so reward = 0 and Treasury receives all 1800e6.
        _expire();
        _assertSeizure(address(token), address(token), 0, 1800e6);
    }

    // Scenarios: BLLIQ-SEIZE-R01.
    function test_givenZeroCollateralDebt_whenSeized_thenDebtDefaultsWithoutRedemption() public {
        // Historical/injected debt state: use Core module authority to create zero-collateral debt.
        // Public borrowing does not originate unsecured loans; module/Inventory accounting stays real.
        vm.startPrank(address(_core));
        uint64 id = _floan.createPosition(_core.marketId(address(_asset)), _borrower);
        _floan.increaseDebt(id, 100e9, 0, uint48(vm.getBlockTimestamp() + 30 days));
        _inventory.draw(_borrower, 100e9);
        vm.stopPrank();
        _expire();
        _assertSeizure(address(_asset), address(_asset), 0, 0);
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            0,
            "No custody transfer for zero credit"
        );
    }

    // Scenarios: BLLIQ-SEIZE-R04.
    function test_givenDefaultedPosition_whenBorrowerReopens_thenPositionIdReused() public {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        (, uint64 beforeId, ) = LoanPositions.forCore(_core, address(_asset), _borrower);
        _expire();
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
        _open(address(_asset), _borrower, 2000e6, 100e9);
        (, uint64 afterId, IFLOANv1.Position memory reopened) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertEq(afterId, beforeId, "Reopening reuses canonical position ID");
        assertEq(reopened.principalDue, 100e9, "Reopened episode has new debt");
        assertEq(reopened.collateral, 2000e6, "Reopened episode has new collateral");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "New funding exposure recorded");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "Borrower reinserted once"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            100e9,
            "Historical default remains recorded once"
        );
    }

    // Scenarios: BLLIQ-SEIZE-R05.
    function test_givenOriginationsDisabled_whenSeized_thenDefaultStillSucceeds() public {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _expire();
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
    }

    // Scenarios: BLLIQ-SEIZE-P18.
    function test_givenRealUnhealthyUnexpiredDebt_whenSeized_thenHealthAndBalancesMatch() public {
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, 100, 30 days, 90 days, 1000e6)
        );
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _price.setPrice(address(_ohm), 25e18);
        // Collateral value = 2000e6 * $1e18 / 1e6 = 2000e18 USD.
        // Required collateral = 100e9 OHM * $25e18 / 1e9 at 100% LTV = 2500e18 USD.
        // Health = 2000e18 * 1e18 / 2500e18 = 0.8e18, below one WAD before expiry.
        assertEq(
            _risk.health(
                _risk.snapshot(address(_asset)),
                _core.marketId(address(_asset)),
                2000e6,
                100e9
            ),
            0.8e18,
            "Independent real health calculation"
        );
        assertLt(
            vm.getBlockTimestamp(),
            _lens.getPosition(address(_asset), _borrower).maturity,
            "Fixture has not matured"
        );
        // Reward = floor(2000e6 * 100/10000) = 20e6; Treasury receives 1980e6.
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
    }

    // Scenarios: BLLIQ-SEIZE-P03.
    function test_givenDebtFreeBorrower_givenOracleOutage_whenSeizedOrPreviewed_reverts(
        uint8 faultSeed_,
        uint8 keeperSeed_,
        bool existing_,
        bool emptyFirst_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        KeeperClass keeperClass_ = KeeperClass(bound(keeperSeed_, 0, uint8(KeeperClass.Both)));
        address[] memory borrowers = _prepareDebtFreeSelection(
            keeperClass_,
            existing_,
            emptyFirst_
        );
        _injectOracleFault(fault_);
        _expectNoSeizurePricing();
        _assertOracleFailure(
            borrowers,
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector)
        );
    }

    // Scenarios: BLLIQ-SEIZE-P03.
    function test_givenDebtFreeBorrower_givenReadyOracles_whenSeizedOrPreviewed_reverts(
        uint8 keeperSeed_,
        bool existing_,
        bool emptyFirst_
    ) public {
        KeeperClass keeperClass_ = KeeperClass(bound(keeperSeed_, 0, uint8(KeeperClass.Both)));
        address[] memory borrowers = _prepareDebtFreeSelection(
            keeperClass_,
            existing_,
            emptyFirst_
        );
        _expectNoSeizurePricing();
        _assertOracleFailure(
            borrowers,
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector)
        );
    }

    // Scenarios: BLLIQ-SEIZE-D13.
    function test_givenExpiredHealthyOrdinaryDebt_givenOracleOutage_reverts(
        uint8 faultSeed_,
        bool afterMaturity_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        address[] memory borrowers = _prepareHealthyExpired(KeeperClass.Ordinary, afterMaturity_);
        _assertOracleFailure(borrowers, _injectOracleFault(fault_));
    }

    // Scenarios: BLLIQ-SEIZE-D13.
    function test_givenExpiredOrdinaryDebt_givenZeroRewardConfig_givenOracleOutage_reverts(
        uint8 faultSeed_,
        uint8 configSeed_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        uint256 config = bound(configSeed_, 0, 2);
        address[] memory borrowers = _prepareHealthyExpired(KeeperClass.Ordinary, false);
        // Seed 0: zero BPS; seed 1: zero cap; seed 2: both zero. Admission remains priced.
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(
                8500,
                12500,
                config == 1 ? 100 : 0,
                30 days,
                90 days,
                config == 0 ? 1000e6 : 0
            )
        );
        _assertOracleFailure(borrowers, _injectOracleFault(fault_));
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenPriceReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.PriceReverts);
        _assertOracleFreeSeizure(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenCacheReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.CacheReverts);
        _assertOracleFreeSeizure(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenBackingReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.BackingReverts);
        _assertOracleFreeSeizure(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenBackingPaused_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.BackingPaused);
        _assertOracleFreeSeizure(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenPriceStale_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.PriceStale);
        _assertOracleFreeSeizure(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenPriceReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.PriceReverts);
        _assertOracleFreePreview(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenCacheReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.CacheReverts);
        _assertOracleFreePreview(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenBackingReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.BackingReverts);
        _assertOracleFreePreview(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenBackingPaused_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.BackingPaused);
        _assertOracleFreePreview(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D14.
    function test_givenExpiredHealthyProtocolDebt_givenPriceStale_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_
    ) public {
        address[] memory borrowers = _prepareHealthyExpired(
            _protocolClass(heart_, overlap_),
            afterMaturity_
        );
        _injectOracleFault(OracleFault.PriceStale);
        _assertOracleFreePreview(borrowers, 100e9, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D24.
    function test_givenUnexpiredUnhealthyDebt_givenOracleOutage_reverts(
        uint8 faultSeed_,
        uint8 keeperSeed_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        KeeperClass keeperClass_ = KeeperClass(bound(keeperSeed_, 0, uint8(KeeperClass.Both)));
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _setKeeperClass(keeperClass_);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_ohm), 25e18);
        _assertHealth(_borrower, false);
        assertLt(
            vm.getBlockTimestamp(),
            _lens.getPosition(address(_asset), _borrower).maturity,
            "Debt remains unexpired"
        );
        _assertOracleFailure(_single(_borrower), _injectOracleFault(fault_));
    }

    // Scenarios: BLLIQ-SEIZE-D25.
    function test_givenMixedMaturityDebt_givenOracleOutage_reverts(
        uint8 faultSeed_,
        uint8 keeperSeed_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        KeeperClass keeperClass_ = KeeperClass(bound(keeperSeed_, 0, uint8(KeeperClass.Both)));
        address[] memory borrowers = _prepareMixedHealth(
            keeperClass_,
            true,
            afterMaturity_,
            reverse_
        );
        _assertOracleFailure(borrowers, _injectOracleFault(fault_));
    }

    // Scenarios: BLLIQ-SEIZE-D27.
    function test_givenExpiredMixedHealthOrdinaryDebt_givenOracleOutage_reverts(
        uint8 faultSeed_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        address[] memory borrowers = _prepareMixedHealth(
            KeeperClass.Ordinary,
            false,
            afterMaturity_,
            reverse_
        );
        _assertOracleFailure(borrowers, _injectOracleFault(fault_));
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenPriceReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.PriceReverts);
        _assertOracleFreeSeizure(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenCacheReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.CacheReverts);
        _assertOracleFreeSeizure(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenBackingReverts_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.BackingReverts);
        _assertOracleFreeSeizure(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenBackingPaused_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.BackingPaused);
        _assertOracleFreeSeizure(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenPriceStale_whenSeized(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.PriceStale);
        _assertOracleFreeSeizure(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenPriceReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.PriceReverts);
        _assertOracleFreePreview(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenCacheReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.CacheReverts);
        _assertOracleFreePreview(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenBackingReverts_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.BackingReverts);
        _assertOracleFreePreview(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenBackingPaused_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.BackingPaused);
        _assertOracleFreePreview(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D26.
    function test_givenExpiredMixedHealthProtocolDebt_givenPriceStale_whenPreviewed(
        bool heart_,
        bool overlap_,
        bool afterMaturity_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            false,
            afterMaturity_,
            reverse_
        );
        _injectOracleFault(OracleFault.PriceStale);
        _assertOracleFreePreview(borrowers, 200e9, 7000e6);
    }

    // Scenarios: BLLIQ-SEIZE-D25.
    function test_givenMixedMaturityProtocolDebt_givenOracleOutage_whenOnlyExpiredSelected(
        uint8 faultSeed_,
        bool heart_,
        bool overlap_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        address[] memory allBorrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            true,
            false,
            false
        );
        bytes memory reason = _injectOracleFault(fault_);
        _assertOracleFailure(allBorrowers, reason);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint256 capacityBefore = _inventory.availableCapacity();
        IBurnerLoansCore.Position memory unexpiredBefore = _lens.getPosition(
            address(_asset),
            _recipient
        );
        _expectNoSeizurePricing();
        vm.prank(_keeper);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            _single(_borrower)
        );
        assertEq(token, address(_asset), "Expired subset redeems underlying");
        assertEq(reward, 0, "Protocol selection receives no reward");
        assertEq(treasury, 5000e6, "All selected collateral goes to Treasury");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 5000e6,
            "Selected collateral is paid"
        );
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            0,
            "Selected debt defaults"
        );
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "Selected collateral clears"
        );
        assertEq(
            keccak256(abi.encode(_lens.getPosition(address(_asset), _recipient))),
            keccak256(abi.encode(unexpiredBefore)),
            "Unselected debt and collateral remain unchanged"
        );
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Unselected principal remains active");
        assertEq(_core.totalActiveDebtOhm(), 100e9, "Core retains unselected debt");
        assertEq(
            _inventory.availableCapacity(),
            capacityBefore + 100e9,
            "Only selected debt releases cap room"
        );
        assertEq(
            _inventory.providerClaimOhm(address(this)),
            200e9,
            "Provider claim survives subset default"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            100e9,
            "Only selected debt is booked as defaulted"
        );
        address[] memory active = _floan.getActiveBorrowers(_core.marketId(address(_asset)));
        assertEq(active.length, 1, "Only unselected borrower remains indexed");
        assertEq(active[0], _recipient, "Remaining index identifies the unselected borrower");
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Unselected collateral remains in custody"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            2000e6,
            "Unselected custody liability remains"
        );
    }

    // Scenarios: BLLIQ-SEIZE-D25.
    function test_givenMixedMaturityProtocolDebt_givenOracleOutage_whenOnlyExpiredPreviewed(
        uint8 faultSeed_,
        bool heart_,
        bool overlap_
    ) public {
        OracleFault fault_ = OracleFault(bound(faultSeed_, 0, uint8(OracleFault.PriceStale)));
        address[] memory allBorrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            true,
            false,
            false
        );
        _injectOracleFault(fault_);
        bytes32 beforeState = _oracleBatchDigest(allBorrowers);
        _expectNoSeizurePricing();
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_asset),
            _single(_borrower)
        );
        assertEq(quote.tokenOut, address(_asset), "Subset quote returns underlying");
        assertEq(quote.seizedDebtOhm, 100e9, "Subset quote includes only expired debt");
        assertEq(quote.seizedCollateral, 5000e6, "Subset quote includes only expired collateral");
        assertEq(quote.keeperReward, 0, "Subset quote has no protocol reward");
        assertEq(
            quote.collateralToTreasury,
            5000e6,
            "Subset quote allocates all output to Treasury"
        );
        assertEq(
            _oracleBatchDigest(allBorrowers),
            beforeState,
            "Subset quote preserves both positions and all custody"
        );
    }

    // Scenarios: BLLIQ-SEIZE-P21.
    function test_givenMaturedDebt_givenOrdinaryKeeper_givenCollateralBelowBacking_whenSeized(
        bool cached_
    ) public {
        _prepareHealthyExpired(KeeperClass.Ordinary, false);
        _price.setPrice(address(_ohm), 25e18);
        MockBackingOracle(_risk.backingOracle()).setBacking(20e18);
        if (cached_) _installSeizurePriceCache();
        // 100e9 OHM (9 decimals) * $20e18 * 12500/10000 / 1e9 = $2500e18.
        // At $1e18 per asset, required backing is 2500e6, above 2000e6 collateral.
        // Surplus and reward are zero; Treasury receives all 2000e6 (6 decimals).
        _assertHealth(_borrower, false);
        _assertSeizure(address(_asset), address(_asset), 0, 2000e6);
    }

    // Scenarios: BLLIQ-SEIZE-P22.
    function test_givenMixedMaturityProtocolDebt_givenOperationalOracles(
        bool heart_,
        bool overlap_,
        bool cached_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            _protocolClass(heart_, overlap_),
            true,
            false,
            reverse_
        );
        if (cached_) _installSeizurePriceCache();
        _assertPricedBatch(borrowers, 0);
    }

    // Scenarios: BLLIQ-SEIZE-P23.
    function test_givenMixedMaturityOrdinaryDebt_givenOperationalOracles(
        bool cached_,
        bool reverse_
    ) public {
        address[] memory borrowers = _prepareMixedHealth(
            KeeperClass.Ordinary,
            true,
            false,
            reverse_
        );
        MockBackingOracle(_risk.backingOracle()).setBacking(27.8e18);
        if (cached_) _installSeizurePriceCache();
        _assertHealth(_borrower, true);
        _assertHealth(_recipient, false);
        // 200e9 OHM * $27.8e18 / 1e9 * 12500/10000 = $6950e18 -> 6950e6 assets.
        // floor(7000e6 * 100/10000)=70e6, but backing surplus=7000e6-6950e6=50e6.
        // Reward is capped to 50e6; Treasury keeps 6950e6. All divisions are exact here.
        _assertPricedBatch(borrowers, 50e6);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, missing-zero-check, reentrancy-no-eth, unsafe-typecast, unused-return)
