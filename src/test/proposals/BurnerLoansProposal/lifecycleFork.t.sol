// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansForkTest} from "./fixtures/BurnerLoansForkTest.sol";
import {Actions, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusHeart as Heart} from "src/policies/Heart.sol";

/// @notice End-to-end lending operations after the actual OCG launch on mainnet.
contract BurnerLoansLifecycleForkTest is BurnerLoansForkTest {
    // Scenarios: BLPF-P02.
    function test_givenLaunchedUsds_whenBorrowerServicesLoan() public {
        _serviceLoan(_graph.usds, _graph.susds, _graph.usds);
    }

    // Scenarios: BLPF-P03.
    function test_givenLaunchedUsde_whenBorrowerServicesLoan() public {
        _serviceLoan(_graph.usde, _graph.susde, _graph.susde);
    }

    // Scenarios: BLPF-P04.
    function test_givenProviderSuppliedOhm_whenBorrowerUsesMintedShortfall() public {
        address provider = _dao;
        assertTrue(
            _roles.hasRole(provider, BURNER_LOANS_INVENTORY_PROVIDER_ROLE),
            "OCG grants DAO provider authority"
        );
        deal(_graph.ohm, provider, 30e9);
        vm.startPrank(provider);
        assertTrue(
            IERC20(_graph.ohm).approve(_graph.inventory, 30e9),
            "Provider approves actual OHM supply"
        );
        _inventory.supply(30e9);
        vm.stopPrank();
        address borrower = makeAddr("fundedBorrower");
        _fundAndApprove(_graph.usds, borrower);
        _depositAndAssert(_graph.usds, _graph.susds, borrower);
        uint256 supplyBefore = IERC20(_graph.ohm).totalSupply();
        vm.prank(borrower);
        // This funding case asserts token supply and provider ledgers; quotes are covered by servicing tests.
        // forge-lint: disable-next-item(unused-return)
        _debt.borrow(_graph.usds, 100e9, borrower, borrower, 0, address(0));
        assertEq(
            IERC20(_graph.ohm).totalSupply() - supplyBefore,
            70e9,
            "100 OHM draw consumes 30 idle and mints only 70"
        );
        assertEq(_inventory.suppliedIdleOhm(), 0, "Provider idle liquidity is consumed first");
        assertEq(
            _inventory.providerClaimOhm(provider),
            30e9,
            "Provider retains its complete claim"
        );
        vm.roll(block.number + 1);
        vm.prank(borrower);
        // Repayment effects are asserted against actual supply, idle liquidity and principal below.
        // forge-lint: disable-next-item(unused-return)
        _debt.repay(_graph.usds, 100e9, borrower);
        assertEq(
            IERC20(_graph.ohm).totalSupply(),
            supplyBefore,
            "Repayment burns only the minted 70 OHM"
        );
        assertEq(_inventory.suppliedIdleOhm(), 30e9, "Repayment restores provider's 30 idle OHM");
        _assertPrincipal(_graph.usds, borrower, 0);
        vm.prank(provider);
        _inventory.withdraw(30e9, provider);
        assertEq(
            IERC20(_graph.ohm).balanceOf(provider),
            30e9,
            "Provider withdraws its restored claim"
        );
        assertEq(_inventory.providerClaimOhm(provider), 0, "Provider claim is consumed once");
        assertEq(_inventory.suppliedOhm(), 0, "Aggregate provider claims reconcile");
    }

    // Scenarios: BLPF-P05.
    function test_givenExpiredLoans_whenKeeperSeizesBothMarkets() public {
        address borrower = makeAddr("expiredBorrower");
        _openLoan(_graph.usds, _graph.susds, borrower);
        _openLoan(_graph.usde, _graph.susde, borrower);
        vm.warp(block.timestamp + 30 days + 1);
        _seizeAndAssert(_graph.usds, _graph.usds, borrower);
        _seizeAndAssert(_graph.usde, _graph.susde, borrower);
        assertEq(_core.totalActiveDebtOhm(), 0, "Both defaults clear Core active debt");
        assertEq(_inventory.activePrincipalOhm(), 0, "Both defaults clear Inventory active debt");
    }

    // Scenarios: BLPF-P06.
    function test_givenVaultYield_whenHeartTasksRun() public {
        (address output, uint256 amount) = IBurnerLoansYieldClaim(_graph.yieldClaimerTask)
            .claimYield(_graph.usds);
        assertEq(output, _graph.usds, "Empty USDS custody reports underlying output");
        assertEq(amount, 0, "Empty USDS custody has no yield");
        (output, amount) = IBurnerLoansYieldClaim(_graph.yieldClaimerTask).claimYield(_graph.usde);
        assertEq(output, _graph.susde, "Empty USDe custody reports share output");
        assertEq(amount, 0, "Empty USDe custody has no yield");
        address depositor = makeAddr("yieldDepositor");
        _fundAndApprove(_graph.usds, depositor);
        uint128 usdsCredit = _depositAndAssert(_graph.usds, _graph.susds, depositor);
        _fundAndApprove(_graph.usde, depositor);
        uint128 usdeCredit = _depositAndAssert(_graph.usde, _graph.susde, depositor);
        // Real sUSDS accrues through chi over time. A controlled USDe donation to the actual
        // sUSDe vault guarantees positive test yield; no vault conversion function is mocked.
        vm.warp(block.timestamp + 7 days);
        deal(_graph.usde, _graph.susde, IERC20(_graph.usde).balanceOf(_graph.susde) + 1_000e18);
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 usdsBefore = IERC20(_graph.usds).balanceOf(treasury);
        uint256 sharesBefore = IERC20(_graph.susde).balanceOf(treasury);
        vm.prank(_graph.heart);
        IPeriodicTask(_graph.yieldClaimerTask).execute();
        assertGt(
            IERC20(_graph.usds).balanceOf(_graph.revenueDistributor),
            0,
            "USDS yield reaches distributor"
        );
        assertGt(
            IERC20(_graph.susde).balanceOf(_graph.revenueDistributor),
            0,
            "sUSDe yield reaches distributor"
        );
        vm.prank(_graph.heart);
        IPeriodicTask(_graph.revenueDistributorTask).execute();
        assertEq(
            IERC20(_graph.usds).balanceOf(_graph.revenueDistributor),
            0,
            "USDS yield distributed completely"
        );
        assertEq(
            IERC20(_graph.susde).balanceOf(_graph.revenueDistributor),
            0,
            "sUSDe yield distributed completely"
        );
        assertGt(
            IERC20(_graph.usds).balanceOf(treasury),
            usdsBefore,
            "Yield task transfers real sUSDS underlying yield to Treasury"
        );
        assertGt(
            IERC20(_graph.susde).balanceOf(treasury),
            sharesBefore,
            "Yield task transfers real sUSDe yield shares to Treasury"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getOperatorLiabilities(
                IERC20(_graph.usds),
                _graph.core
            ),
            usdsCredit,
            "Yield preserves USDS borrower liabilities"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getOperatorLiabilities(
                IERC20(_graph.usde),
                _graph.core
            ),
            usdeCredit,
            "Yield preserves USDe borrower liabilities"
        );
        assertTrue(
            _lens.getAssetCollateralStatus(_graph.usds).solvent,
            "USDS custody remains solvent after yield collection"
        );
        assertTrue(
            _lens.getAssetCollateralStatus(_graph.usde).solvent,
            "USDe custody remains solvent after yield collection"
        );
        uint48 lastBeat = Heart(_graph.heart).lastBeat();
        // Real Heart first stores a PRICE observation, then invokes all old and new tasks.
        Heart(_graph.heart).beat();
        assertGt(
            Heart(_graph.heart).lastBeat(),
            lastBeat,
            "Actual heartbeat traverses the configured task list"
        );
        assertEq(
            IBurnerLoansSeizerTask(_graph.seizerTask).nextAssetIndex(),
            1,
            "Actual Heart executes the new Seizer task"
        );
        _assertHeartOrder();
    }

    // Scenarios: BLPF-P08.
    function test_givenExpiredPosition_whenHeartSeizerTaskRuns() public {
        address borrower = makeAddr("automatedDefaultBorrower");
        _openLoan(_graph.usds, _graph.susds, borrower);
        vm.warp(block.timestamp + 30 days + 1);
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 treasuryBefore = IERC20(_graph.usds).balanceOf(treasury);
        vm.prank(_graph.heart);
        IPeriodicTask(_graph.seizerTask).execute();
        assertEq(
            _lens.getPosition(_graph.usds, borrower).debtOhm,
            0,
            "Authorized automation closes the expired loan"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "Automated seizure settles Inventory default accounting"
        );
        assertGt(
            IERC20(_graph.usds).balanceOf(treasury),
            treasuryBefore,
            "Automated seizure routes collateral to Treasury"
        );
        assertEq(
            IERC20(_graph.usds).balanceOf(_graph.seizerTask),
            0,
            "Protocol automation retains no keeper reward"
        );
    }

    function _openLoan(
        address asset_,
        address vault_,
        address borrower_
    ) private returns (uint128 credit) {
        _fundAndApprove(asset_, borrower_);
        credit = _depositAndAssert(asset_, vault_, borrower_);
        vm.prank(borrower_);
        // This helper prepares debt for seizure/restart scenarios; servicing tests check the quote.
        // forge-lint: disable-next-item(unused-return)
        _debt.borrow(asset_, 100e9, borrower_, borrower_, 0, address(0));
    }

    function _seizeAndAssert(address asset_, address output_, address borrower_) private {
        {
            address keeper = makeAddr("seizureKeeper");
            address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
            address[] memory borrowers = new address[](1);
            borrowers[0] = borrower_;
            IBurnerLoansCore.SeizePreview memory quote = IBurnerLoansSeize(_graph.seize)
                .previewSeizeFor(keeper, asset_, borrowers);
            uint256 keeperBefore = IERC20(output_).balanceOf(keeper);
            uint256 treasuryBefore = IERC20(output_).balanceOf(treasury);
            vm.prank(keeper);
            (address token, uint256 reward, uint256 treasuryAmount) = IBurnerLoansSeize(
                _graph.seize
            ).seize(asset_, borrowers);
            assertEq(token, output_, "Seizure uses approved underlying/share output mode");
            assertEq(reward, quote.keeperReward, "Actual keeper allocation matches preview");
            assertEq(
                treasuryAmount,
                quote.collateralToTreasury,
                "Actual Treasury allocation matches preview"
            );
            assertEq(
                IERC20(output_).balanceOf(keeper) - keeperBefore,
                reward,
                "Keeper receives actual output token allocation"
            );
            assertEq(
                IERC20(output_).balanceOf(treasury) - treasuryBefore,
                treasuryAmount,
                "Treasury receives actual output token allocation"
            );
        }
        assertEq(
            _lens.getPosition(asset_, borrower_).depositedCollateral,
            0,
            "Seizure clears borrower collateral"
        );
        assertEq(
            IFLOANv1(_graph.floan).getMarketPrincipalDue(_core.marketId(asset_)),
            0,
            "FLOAN principal closes on default"
        );
        assertEq(
            IFLOANv1(_graph.floan).getMarketPrincipalDefaulted(_core.marketId(asset_)),
            100e9,
            "FLOAN records the actual defaulted principal"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getOperatorLiabilities(
                IERC20(asset_),
                _graph.core
            ),
            0,
            "Seizure clears custody liabilities"
        );
    }

    function _serviceLoan(address asset_, address vault_, address output_) private {
        address borrower = makeAddr("servicingBorrower");
        _fundAndApprove(asset_, borrower);
        uint256 supplyBefore = IERC20(_graph.ohm).totalSupply();
        uint128 credit = _depositAndAssert(asset_, vault_, borrower);
        uint48 maturity = _borrowAndAssert(asset_, borrower, supplyBefore);
        _extendAndAssert(asset_, borrower, maturity);
        _repayAndAssert(asset_, borrower, supplyBefore);
        _withdrawAndAssert(asset_, output_, borrower, credit);
    }

    function _depositAndAssert(
        address asset_,
        address vault_,
        address borrower_
    ) private returns (uint128 credit) {
        uint256 custodySharesBefore = IERC20(vault_).balanceOf(_graph.depositManager);
        // This assertion checks vault credit and collateral; debt-free health is asserted separately.
        // forge-lint: disable-next-item(unused-return)
        (uint256 quotedCredit, uint256 quotedCollateral, ) = _collateral.previewDepositCollateral(
            asset_,
            4_000e18,
            borrower_
        );
        vm.prank(borrower_);
        uint128 collateral;
        uint256 health;
        (credit, collateral, health) = _collateral.depositCollateral(asset_, 4_000e18, borrower_);
        assertEq(credit, quotedCredit, "Actual vault-backed credit agrees with deposit preview");
        assertEq(collateral, quotedCollateral, "Deposit preview agrees with collateral position");
        assertEq(health, type(uint256).max, "Debt-free position has unlimited health");
        assertEq(
            IERC20(asset_).balanceOf(borrower_),
            6_000e18,
            "Deposit collects exactly 4000 underlying units at 18 decimals"
        );
        assertGt(
            IERC20(vault_).balanceOf(_graph.depositManager),
            custodySharesBefore,
            "Actual vault shares enter shared v1.1 custody"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getOperatorLiabilities(
                IERC20(asset_),
                _graph.core
            ),
            credit,
            "Custody liabilities equal credited collateral"
        );
        assertEq(
            IFLOANv1(_graph.floan).getMarketCollateral(_core.marketId(asset_)),
            credit,
            "FLOAN records actual custody credit"
        );
    }

    function _borrowAndAssert(
        address asset_,
        address borrower_,
        uint256 supplyBefore_
    ) private returns (uint48 maturity) {
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            asset_,
            100e9,
            borrower_,
            borrower_,
            0,
            address(0)
        );
        vm.prank(borrower_);
        IBurnerLoansDebt.BorrowPreview memory borrowed = _debt.borrow(
            asset_,
            100e9,
            borrower_,
            borrower_,
            0,
            address(0)
        );
        assertEq(
            abi.encode(borrowed),
            abi.encode(quote),
            "Borrow result matches permissionless preview"
        );
        assertEq(borrowed.fee, 0, "Approved launch borrow fee is zero");
        IPriceCache.CachedPrice memory pair = IPriceCache(_graph.priceCache).getCachedPrice(
            _graph.ohm,
            asset_
        );
        assertEq(pair.updatedAt, block.timestamp, "Borrow refreshes the configured cache");
        assertGt(pair.assetPriceUsd, 0, "Cached OHM quote is positive");
        assertGt(pair.quotePriceUsd, 0, "Cached collateral quote is positive");
        assertEq(borrowed.maturity, block.timestamp + 30 days, "Initial debt term is thirty days");
        maturity = borrowed.maturity;
        assertEq(
            IERC20(_graph.ohm).balanceOf(borrower_),
            100e9,
            "Borrower receives 100 OHM at 9 decimals"
        );
        assertEq(
            IERC20(_graph.ohm).totalSupply() - supplyBefore_,
            100e9,
            "Empty inventory mints the complete loan"
        );
        _assertPrincipal(asset_, borrower_, 100e9);
    }

    function _extendAndAssert(address asset_, address borrower_, uint48 maturity_) private {
        IBurnerLoansDebt.ExtendPreview memory extensionQuote = _debt.previewExtend(
            asset_,
            borrower_,
            1,
            0,
            address(0)
        );
        vm.prank(borrower_);
        IBurnerLoansDebt.ExtendPreview memory extended = _debt.extend(
            asset_,
            borrower_,
            1,
            0,
            address(0)
        );
        assertEq(
            abi.encode(extended),
            abi.encode(extensionQuote),
            "Extension result matches preview"
        );
        assertEq(extended.maturity, maturity_ + 30 days, "One extension adds one complete term");
        assertEq(extended.fee, 0, "Launch extension fee is zero");
        assertEq(
            _lens.getPosition(asset_, borrower_).maturity,
            extended.maturity,
            "FLOAN-backed getter records extended maturity"
        );
    }

    function _repayAndAssert(address asset_, address borrower_, uint256 supplyBefore_) private {
        vm.roll(block.number + 1);
        (uint128 previewDebt, uint256 previewHealth) = _debt.previewRepay(asset_, 40e9, borrower_);
        vm.prank(borrower_);
        (uint128 debt, uint256 resultingHealth) = _debt.repay(asset_, 40e9, borrower_);
        assertEq(debt, previewDebt, "Partial repayment principal matches preview");
        assertEq(resultingHealth, previewHealth, "Partial repayment health matches preview");
        assertEq(debt, 60e9, "100 OHM minus 40 OHM leaves 60 OHM");
        assertEq(
            IERC20(_graph.ohm).balanceOf(borrower_),
            60e9,
            "Partial repayment collects exactly 40 OHM"
        );
        _assertPrincipal(asset_, borrower_, 60e9);
        vm.prank(borrower_);
        (debt, resultingHealth) = _debt.repay(asset_, 60e9, borrower_);
        assertEq(debt, 0, "Full repayment clears principal");
        assertEq(resultingHealth, type(uint256).max, "Fully repaid health is unlimited");
        _assertPrincipal(asset_, borrower_, 0);
        assertEq(
            IERC20(_graph.ohm).totalSupply(),
            supplyBefore_,
            "Repaid minted principal is burned"
        );
    }

    function _withdrawAndAssert(
        address asset_,
        address output_,
        address borrower_,
        uint128 credit_
    ) private {
        IBurnerLoansCollateral.WithdrawPreview memory withdrawalQuote = _collateral
            .previewWithdrawCollateral(asset_, credit_, borrower_, borrower_);
        uint256 outputBefore = IERC20(output_).balanceOf(borrower_);
        vm.prank(borrower_);
        IBurnerLoansCollateral.WithdrawPreview memory withdrawn = _collateral.withdrawCollateral(
            asset_,
            credit_,
            borrower_,
            borrower_
        );
        assertEq(
            abi.encode(withdrawn),
            abi.encode(withdrawalQuote),
            "Withdrawal result matches real-vault preview"
        );
        assertEq(withdrawn.returnToken, output_, "Custody uses the approved output mode");
        assertEq(
            IERC20(output_).balanceOf(borrower_) - outputBefore,
            withdrawn.returnAmount,
            "Actual withdrawal token delta equals returned amount"
        );
        assertEq(
            _lens.getPosition(asset_, borrower_).depositedCollateral,
            0,
            "Borrower collateral is cleared"
        );
        assertEq(
            IFLOANv1(_graph.floan).getMarketCollateral(_core.marketId(asset_)),
            0,
            "FLOAN collateral is cleared"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getOperatorLiabilities(
                IERC20(asset_),
                _graph.core
            ),
            0,
            "Custody liabilities are cleared"
        );
    }

    function _fundAndApprove(address asset_, address borrower_) private {
        deal(asset_, borrower_, 10_000e18);
        vm.startPrank(borrower_);
        assertTrue(
            IERC20(asset_).approve(_graph.core, type(uint256).max),
            "Borrower approves collateral collection"
        );
        assertTrue(
            IERC20(_graph.ohm).approve(_graph.core, type(uint256).max),
            "Borrower approves OHM repayment"
        );
        vm.stopPrank();
    }

    function _assertPrincipal(address asset_, address borrower_, uint128 expected_) private view {
        assertEq(
            _lens.getPosition(asset_, borrower_).debtOhm,
            expected_,
            "Borrower principal is authoritative"
        );
        assertEq(
            IFLOANv1(_graph.floan).getMarketPrincipalDue(_core.marketId(asset_)),
            expected_,
            "FLOAN market principal reconciles"
        );
        assertEq(_core.totalActiveDebtOhm(), expected_, "Core aggregate principal reconciles");
        assertEq(
            _inventory.activePrincipalOhm(),
            expected_,
            "Inventory funding principal reconciles"
        );
    }
}
