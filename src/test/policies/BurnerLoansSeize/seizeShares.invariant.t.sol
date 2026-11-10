// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {Actions} from "src/Kernel.sol";
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";
import {BurnerLoansShareHandler} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansShareHandler.sol";

/// @notice Restores the legacy multi-borrower external-share conservation campaign on the modular stack.
/// @dev Scope: one asset18/share6 vault, three borrowers, variable prices/time/yield, both supported
///      custody modes, asynchronous-redemption drift, Inventory and periodic seizure.
/// forge-config: default.invariant.fail-on-revert = true
contract BurnerLoansSeizeSharesInvariantTest is BurnerLoansModularTest {
    BurnerLoansShareHandler internal _handler;
    MockERC20 internal _shareAsset;
    MockERC7540ExternalShareVault internal _vault;
    IERC20 internal _share;
    BurnerLoansSeizerTask internal _seizer;
    BurnerLoansYieldClaimerTask internal _claimer;

    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function setUp() public override {
        super.setUp();
        _shareAsset = new MockERC20("Share collateral", "SC", 18);
        _vault = new MockERC7540ExternalShareVault(
            OZERC20(address(_shareAsset)),
            false,
            true,
            true
        );
        _share = IERC20(_vault.share());
        _price.setPrice(address(_shareAsset), 1e18);
        _depositManager.addAsset(
            IERC20(address(_shareAsset)),
            IERC4626(address(_vault)),
            type(uint256).max,
            0
        );
        _depositManager.addAssetPeriod(IERC20(address(_shareAsset)), 1, address(_core));
        _config.addAsset(
            address(_shareAsset),
            100_000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e18),
            IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900),
            true
        );
        _seizer = new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 3, 3, 10_000_000);
        _claimer = new BurnerLoansYieldClaimerTask(_kernel, address(_core), 2_000_000);
        _kernel.executeAction(Actions.ActivatePolicy, address(_seizer));
        _kernel.executeAction(Actions.ActivatePolicy, address(_claimer));
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_seizer));
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        _seizer.addAsset(address(_shareAsset));
        _seizer.enable("");
        _claimer.enable("");
        _handler = new BurnerLoansShareHandler(
            BurnerLoansShareHandler.Services({
                collateral: _collateral,
                debt: _debt,
                seize: _liquidation,
                config: _config,
                lens: _lens,
                seizer: _seizer,
                claimer: _claimer
            }),
            _vault,
            _price,
            _payout.treasury()
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        _rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, address(_handler));
        _rolesAdmin.grantRole(HEART_ROLE, address(_handler));

        // Deterministic setup proves each restored path runs before randomized interleavings.
        _handler.supplyInventory(50e9);
        _handler.setOriginations(false);
        _handler.deposit(0, 2000e18);
        _handler.setOriginations(true);
        _handler.deposit(1, 2000e18);
        _handler.deposit(2, 2000e18);
        _handler.borrow(0, 100e9);
        _handler.borrow(1, 100e9);
        _handler.borrow(2, 100e9);
        for (uint256 i; i < 3; ++i) {
            assertEq(
                _handler.principal(_handler.actors(i)),
                100e9,
                "Each seeded borrower incurs debt"
            );
        }
        _handler.addYield(100e18);
        _handler.withdraw(0, 25e18);
        assertEq(
            _handler.collateral(_handler.actors(0)),
            1975e18,
            "Seeded share withdrawal executes"
        );
        _handler.repay(1, 10e9);
        _handler.withdraw(1, 25e18);
        assertEq(
            _handler.principal(_handler.actors(1)),
            90e9,
            "Seeded partial repayment preserves debt"
        );
        assertEq(
            _handler.collateral(_handler.actors(1)),
            1975e18,
            "Seeded withdrawal after partial repayment returns shares"
        );
        _handler.repay(1, 90e9);
        _handler.withdraw(1, 50e18);
        assertEq(_handler.principal(_handler.actors(1)), 0, "Seeded full repayment clears debt");
        assertEq(
            _handler.collateral(_handler.actors(1)),
            1925e18,
            "Seeded withdrawal after full repayment returns shares"
        );
        _handler.setAsyncRedeem(false);
        _handler.setWithdrawAsShares(false);
        _handler.withdraw(1, 25e18);
        assertEq(
            _handler.collateral(_handler.actors(1)),
            1900e18,
            "Seeded underlying withdrawal executes"
        );
        uint256 underlyingBefore = _shareAsset.balanceOf(_payout.treasury());
        _handler.claimYield();
        assertGt(
            _shareAsset.balanceOf(_payout.treasury()),
            underlyingBefore,
            "Seeded underlying yield is delivered"
        );
        _handler.setAsyncRedeem(true);
        _handler.claimYield();
        _handler.setWithdrawAsShares(true);
        _handler.addYield(10e18);
        _handler.claimYield();
        assertGt(_share.balanceOf(_payout.treasury()), 0, "Seeded share yield is delivered");
        _handler.repay(2, 10e9);
        _handler.withdrawInventory(1e9);
        _handler.moveTime(31 days);
        _handler.seize();
        assertEq(
            _handler.defaulted(),
            190e9,
            "Seeded permissionless seizure closes remaining debt"
        );
        _handler.deposit(0, 2000e18);
        _handler.borrow(0, 100e9);
        assertEq(
            _handler.principal(_handler.actors(0)),
            100e9,
            "Seeded position reopens after default"
        );
        _handler.moveTime(31 days);
        _handler.executePeriodicSeizer();
        assertEq(_handler.defaulted(), 290e9, "Seeded periodic seizure executes");

        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = _handler.deposit.selector;
        selectors[1] = _handler.borrow.selector;
        selectors[2] = _handler.repay.selector;
        selectors[3] = _handler.withdraw.selector;
        selectors[4] = _handler.seize.selector;
        selectors[5] = _handler.executePeriodicSeizer.selector;
        selectors[6] = _handler.claimYield.selector;
        selectors[7] = _handler.addYield.selector;
        selectors[8] = _handler.movePrices.selector;
        selectors[9] = _handler.moveTime.selector;
        selectors[10] = _handler.setAsyncRedeem.selector;
        selectors[11] = _handler.setWithdrawAsShares.selector;
        selectors[12] = _handler.supplyInventory.selector;
        selectors[13] = _handler.withdrawInventory.selector;
        selectors[14] = _handler.setOriginations.selector;
        targetContract(address(_handler));
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
    }

    // forge-lint: disable-end(calls-loop)

    // Scenarios: BLLIQ-SEIZE-S01.
    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function invariant_shareCustodyAndPositionAccountingConserve() public view {
        uint256 collateral;
        uint256 principal;
        for (uint256 i; i < 3; ++i) {
            address actor = _handler.actors(i);
            IBurnerLoansCore.Position memory position = _lens.getPosition(
                address(_shareAsset),
                actor
            );
            assertEq(
                position.depositedCollateral,
                _handler.collateral(actor),
                "Borrower collateral equals model"
            );
            assertEq(position.debtOhm, _handler.principal(actor), "Borrower debt equals model");
            collateral += _handler.collateral(actor);
            principal += _handler.principal(actor);
            if (position.debtOhm != 0 && !_lens.isSeizable(address(_shareAsset), actor)) {
                assertGe(
                    _lens.positionHealthFactor(
                        address(_shareAsset),
                        position.depositedCollateral,
                        position.debtOhm
                    ),
                    1e18,
                    "Live debt is healthy or seizable"
                );
            }
        }
        uint32 market = _core.marketId(address(_shareAsset));
        assertEq(
            _floan.getMarketCollateral(market),
            collateral,
            "FLOAN collateral aggregate equals model"
        );
        assertEq(
            _floan.getMarketPrincipalDue(market),
            principal,
            "FLOAN principal aggregate equals model"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(market),
            _handler.defaulted(),
            "Defaults recorded exactly once"
        );
        assertEq(_inventory.activePrincipalOhm(), principal, "Inventory principal equals model");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_shareAsset)), address(_core)),
            collateral,
            "DM liabilities equal summed borrower credits"
        );
        uint256 id = _depositManager.getReceiptTokenId(
            IERC20(address(_shareAsset)),
            1,
            address(_core)
        );
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), id),
            collateral,
            "Core receipts equal modeled liabilities"
        );
        assertEq(
            _depositManager.getAssetDepositCapStatus(IERC20(address(_shareAsset))).utilization,
            collateral,
            "Asset cap utilization equals liabilities"
        );
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(_shareAsset)),
            address(_core)
        );
        assertEq(
            _share.balanceOf(address(_depositManager)),
            shares,
            "External share custody equals operator accounting"
        );
        assertGe(assets, collateral, "External shares cover all borrower liabilities");
        assertEq(
            _ohm.totalSupply(),
            principal +
                _handler.defaulted() +
                _inventory.suppliedIdleOhm() +
                _ohm.balanceOf(address(_handler)),
            "OHM funding and default conservation"
        );
        address[7] memory periphery = [
            address(_core),
            address(_payout),
            address(_collateral),
            address(_debt),
            address(_liquidation),
            address(_seizer),
            address(_claimer)
        ];
        for (uint256 i; i < periphery.length; ++i) {
            assertEq(_share.balanceOf(periphery[i]), 0, "No external shares remain in periphery");
            assertEq(_shareAsset.balanceOf(periphery[i]), 0, "No underlying remains in periphery");
        }
        (uint256 fees, , uint256 seized, , uint256 pending) = _payout.pendingAmounts(
            address(_share)
        );
        assertEq(fees + seized + pending, 0, "Successful share payouts leave no obligations");
        (fees, , seized, , pending) = _payout.pendingAmounts(address(_shareAsset));
        assertEq(fees + seized + pending, 0, "Successful underlying payouts leave no obligations");
    }
    // forge-lint: disable-end(calls-loop)
}
// forge-lint: disable-end(unused-return)
