// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MinterAdminPolicy} from "src/test/policies/BurnerLoans/fixtures/MinterAdminPolicy.sol";
import {BurnerLoansERC7540CapabilityHandler} from "src/test/policies/BurnerLoans/handlers/BurnerLoansERC7540CapabilityHandler.sol";
import {BurnerLoansHandler} from "src/test/policies/BurnerLoans/handlers/BurnerLoansHandler.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract BurnerLoansShareInvariantTest is StdInvariant, BurnerLoansTest {
    uint256 internal constant _WAD = 1e18;

    BurnerLoansHandler internal _handler;
    BurnerLoansERC7540CapabilityHandler internal _capabilityHandler;
    BurnerLoansComposites internal _composites;
    BurnerLoansSeizer internal _seizer;
    MockERC7540ExternalShareVault internal _vault;
    MockERC7540ExternalShareToken internal _shareToken;
    MockYieldRepurchaseRecipient internal _yieldRecipient;
    PriceCache internal _primaryPriceCache;
    PriceCache internal _secondaryPriceCache;
    address[] internal _invariantActors;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        (_vault, _shareToken) = _configureAsyncExternalShareAssetForTest(usds);
        _setDefaultGlobalDebtCap();

        vm.startPrank(admin);
        MinterAdminPolicy minterAdminPolicy = new MinterAdminPolicy(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(minterAdminPolicy));

        _yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(_yieldRecipient));
        _yieldRecipient.setVaultConfig(address(_vault), address(usds), true);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(_yieldRecipient));

        _primaryPriceCache = _deployPriceCache(true, true);
        _secondaryPriceCache = _deployPriceCache(true, true);

        _seizer = new BurnerLoansSeizer(kernel, address(burnerLoans), 8, 4, 10_000_000);
        kernel.executeAction(Actions.ActivatePolicy, address(_seizer));
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_seizer));
        _seizer.addAsset(address(usds));
        vm.stopPrank();

        _invariantActors.push(alice);
        _invariantActors.push(makeAddr("bob"));
        _invariantActors.push(makeAddr("carol"));
        _composites = new BurnerLoansComposites(address(burnerLoans), address(ohm));
        _handler = new BurnerLoansHandler(
            BurnerLoansHandler.Dependencies({
                burnerLoans: burnerLoans,
                burnerLoansConfig: burnerLoansConfig,
                composites: _composites,
                floan: floan,
                seizer: _seizer,
                price: price,
                ohm: ohm,
                collateral: usds,
                depositManager: depositManager,
                admin: admin,
                treasury: address(trsry),
                inventoryProvider: protocolProvider,
                yieldRecipient: _yieldRecipient,
                primaryPriceCache: _primaryPriceCache,
                secondaryPriceCache: _secondaryPriceCache,
                actors: _invariantActors
            })
        );
        vm.prank(admin);
        rolesAdmin.grantRole(HEART_ROLE, address(_handler));
        _capabilityHandler = new BurnerLoansERC7540CapabilityHandler(_vault);

        _handler.supplyInventory(50e9);
        _handler.deposit(0, 2_000e18);
        _handler.borrow(0, 100e9);
        vm.roll(block.number + 1);
        _handler.addYield(100e18);

        // Exercise both governance transitions before stateful fuzzing begins.
        _handler.toggleWithdrawAsShares(false);
        _handler.toggleWithdrawAsShares(true);

        bytes4[] memory selectors = new bytes4[](18);
        selectors[0] = _handler.deposit.selector;
        selectors[1] = _handler.borrow.selector;
        selectors[2] = _handler.repay.selector;
        selectors[3] = _handler.withdraw.selector;
        selectors[4] = _handler.moveOhmPrice.selector;
        selectors[5] = _handler.moveCollateralPrice.selector;
        selectors[6] = _handler.moveTime.selector;
        selectors[7] = _handler.seize.selector;
        selectors[8] = _handler.addYield.selector;
        selectors[9] = _handler.claimAssetYield.selector;
        selectors[10] = _handler.toggleWithdrawAsShares.selector;
        selectors[11] = _handler.supplyInventory.selector;
        selectors[12] = _handler.withdrawInventory.selector;
        selectors[13] = _handler.compositeRepayAndWithdraw.selector;
        selectors[14] = _handler.executePeriodicSeizer.selector;
        selectors[15] = _handler.setYieldAssetRouting.selector;
        selectors[16] = _handler.setYieldRepurchaseRecipient.selector;
        selectors[17] = _handler.toggleYieldRecipient.selector;
        targetContract(address(_handler));
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));

        bytes4[] memory capabilitySelectors = new bytes4[](1);
        capabilitySelectors[0] = _capabilityHandler.setAsyncRedeem.selector;
        targetSelector(
            FuzzSelector({addr: address(_capabilityHandler), selectors: capabilitySelectors})
        );
    }

    function invariant_CollateralReconcilesAndRemainsSolvent() public view {
        uint256 creditedCollateral;
        for (uint256 i; i < _invariantActors.length; ++i) {
            // The invariant must reconcile each of the three fixed actors.
            // forge-lint: disable-start(calls-loop)
            creditedCollateral += burnerLoans
                .getPosition(address(usds), _invariantActors[i])
                .depositedCollateral;
            // forge-lint: disable-end(calls-loop)
        }
        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(usds)
        );
        assertEq(status.liabilities, creditedCollateral, "credited collateral mismatch");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            creditedCollateral,
            "DepositManager liabilities mismatch"
        );
        assertGe(status.assets + status.borrowed, status.liabilities, "custody is insolvent");
        assertTrue(status.solvent, "collateral status reports insolvency");
    }

    function invariant_WithdrawalShareOutputsConserve() public view {
        assertEq(
            _handler.withdrawalOutputConservationViolations(),
            0,
            "withdrawal share output did not reconcile"
        );
    }

    function invariant_CompositeWithdrawalShareOutputsConserve() public view {
        assertEq(
            _handler.compositeWithdrawalOutputConservationViolations(),
            0,
            "composite withdrawal share output did not reconcile"
        );
    }

    function invariant_SeizureShareOutputsConserve() public view {
        assertEq(
            _handler.seizureOutputConservationViolations(),
            0,
            "seizure share output did not reconcile"
        );
    }

    function invariant_YieldShareOutputsConserve() public view {
        assertEq(_handler.claimYieldConservationViolations(), 0, "yield shares did not reconcile");
        assertEq(_handler.claimYieldBoundViolations(), 0, "yield request exceeded share capacity");
        assertEq(_handler.claimYieldResidualViolations(), 0, "Burner Loans retained yield shares");
        assertEq(
            _handler.claimYieldFailureMutationViolations(),
            0,
            "failed yield claim mutated state"
        );
        assertEq(
            _handler.claimYieldPreviewConsistencyViolations(),
            0,
            "yield claim diverged from preview"
        );
        assertEq(
            _handler.cumulativeDistributedYield(),
            _handler.cumulativeClaimedYield(),
            "cumulative yield shares do not conserve"
        );
    }

    function invariant_ModeTransitionsAreAtomic() public view {
        assertEq(
            _handler.withdrawAsSharesTransitionViolations(),
            0,
            "withdraw-as-shares transition partially applied"
        );
    }

    function invariant_EligibleWithdrawalsAgreeWithPreview() public view {
        assertEq(_handler.unexpectedWithdrawFailures(), 0, "eligible withdrawal failed");
        assertEq(
            _handler.unexpectedUnexecutableWithdrawSuccesses(),
            0,
            "unexecutable withdrawal succeeded"
        );
    }

    function invariant_SeizureClosesDebtAndPositionState() public view {
        assertEq(_handler.seizureEligibilityViolations(), 0, "scan returned ineligible borrower");
        assertEq(_handler.seizureClosureViolations(), 0, "seizure did not clear position state");
    }

    function invariant_NoShareTokensRemainInPeriphery() public view {
        assertEq(
            _shareToken.balanceOf(address(burnerLoans)),
            0,
            "Burner Loans retained external shares"
        );
        assertEq(_shareToken.balanceOf(address(_seizer)), 0, "seizer retained external shares");
        assertEq(
            _shareToken.balanceOf(address(_composites)),
            0,
            "composite retained external shares"
        );
    }

    function invariant_ExternalShareCustodyCoversOperatorAccounting() public view {
        (uint256 operatorShares, ) = depositManager.getOperatorAssets(
            IERC20(address(usds)),
            address(burnerLoans)
        );
        assertGe(
            _shareToken.balanceOf(address(depositManager)),
            operatorShares,
            "external-share custody below operator accounting"
        );
    }

    function invariant_OhmSupplyAccounting() public view {
        uint256 accountedDebt = burnerLoans.totalActiveDebtOhm() +
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds)));
        uint256 accountedSupply = accountedDebt +
            inventory.suppliedIdleOhm() +
            ohm.balanceOf(protocolProvider);
        assertEq(ohm.totalSupply(), accountedSupply, "OHM supply accounting mismatch");
    }

    function invariant_ActivePositionsRemainHealthyOrSeizable() public view {
        for (uint256 i; i < _invariantActors.length; ++i) {
            // The invariant must inspect each of the three fixed actor positions.
            // forge-lint: disable-start(calls-loop)
            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(usds),
                _invariantActors[i]
            );
            // forge-lint: disable-end(calls-loop)
            if (
                // Each active actor must be tested against live seizure eligibility.
                // forge-lint: disable-next-line(calls-loop)
                position.debtOhm == 0 || burnerLoans.isSeizable(address(usds), _invariantActors[i])
            ) {
                continue;
            }
            assertGe(
                // Each remaining actor must be checked against its live health factor.
                // forge-lint: disable-start(calls-loop)
                burnerLoans.positionHealthFactor(
                    address(usds),
                    position.depositedCollateral,
                    position.debtOhm
                ),
                // forge-lint: disable-end(calls-loop)
                _WAD,
                "active position is unhealthy"
            );
        }
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
