// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansHandler} from "src/test/policies/BurnerLoans/handlers/BurnerLoansHandler.sol";
import {BurnerLoansSeizureTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansInvariantTest is StdInvariant, BurnerLoansSeizureTestBase {
    uint256 internal constant _WAD = 1e18;

    BurnerLoansHandler internal handler;
    BurnerLoansComposites internal composites;
    BurnerLoansSeizer internal seizer;
    address[] internal invariantActors;

    function setUp() public override {
        super.setUp();
        invariantActors.push(alice);
        invariantActors.push(bob);
        invariantActors.push(makeAddr("carol"));

        composites = new BurnerLoansComposites(address(burnerLoans), address(ohm));

        vm.startPrank(admin);
        seizer = new BurnerLoansSeizer(kernel, address(burnerLoans), 8, 4);
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        seizer.addAsset(address(usds));
        vm.stopPrank();

        handler = new BurnerLoansHandler(
            BurnerLoansHandler.Dependencies({
                burnerLoans: burnerLoans,
                burnerLoansConfig: burnerLoansConfig,
                composites: composites,
                floan: floan,
                seizer: seizer,
                price: price,
                ohm: ohm,
                collateral: usds,
                depositManager: depositManager,
                admin: admin,
                treasury: address(trsry),
                actors: invariantActors
            })
        );
        vm.prank(admin);
        rolesAdmin.grantRole(HEART_ROLE, address(handler));

        // Seed every campaign with a live position so debt, health, repayment, maturity,
        // seizure, and custody invariants are not dependent on a random setup sequence.
        handler.deposit(0, 2_000e18);
        handler.borrow(0, 100e9);
        vm.roll(block.number + 1);

        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.borrow.selector;
        selectors[2] = handler.repay.selector;
        selectors[3] = handler.withdraw.selector;
        selectors[4] = handler.extend.selector;
        selectors[5] = handler.moveOhmPrice.selector;
        selectors[6] = handler.moveCollateralPrice.selector;
        selectors[7] = handler.moveTime.selector;
        selectors[8] = handler.seize.selector;
        selectors[9] = handler.executePeriodicSeizer.selector;
        selectors[10] = handler.addYield.selector;
        selectors[11] = handler.harvestYield.selector;
        selectors[12] = handler.toggleAsset.selector;
        selectors[13] = handler.compositeDepositAndBorrow.selector;
        selectors[14] = handler.compositeRepayAndWithdraw.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when OHM supply accounting is checked
    //   then OHM supply equals active and defaulted facility principal
    function invariant_OhmSupplyAccounting() public view {
        uint256 accountedDebt = burnerLoans.totalActiveDebtOhm() +
            floan.getMarketPrincipalDefaulted(burnerLoans.marketId(address(usds)));
        assertEq(ohm.totalSupply(), accountedDebt, "OHM supply does not reconcile to loan debt");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when repayment burn accounting is checked
    //   then repayments burn exact OHM and leave no OHM in Burner Loans
    function invariant_RepaymentBurn() public view {
        assertEq(handler.repaymentBurnViolations(), 0, "repayment did not burn exact OHM");
        assertEq(ohm.balanceOf(address(burnerLoans)), 0, "BurnerLoans retained OHM");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when debt capacity is checked
    //   then global and market principal remain within their caps
    function invariant_Capacity() public view {
        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertLe(
            burnerLoans.totalActiveDebtOhm(),
            burnerLoans.globalDebtCapOhm(),
            "global debt cap exceeded"
        );
        assertLe(
            burnerLoans.assetActiveDebtOhm(address(usds)),
            config.debtCap,
            "asset debt cap exceeded"
        );
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when repayment debt reduction is checked
    //   then repayment reduces debt without changing credited collateral
    function invariant_RepaymentDebtReduction() public view {
        assertEq(handler.repaymentDebtViolations(), 0, "repayment debt delta mismatch");
        assertEq(
            handler.repaymentCollateralViolations(),
            0,
            "repayment changed credited collateral"
        );
        assertEq(handler.unexpectedRepayFailures(), 0, "eligible repayment failed");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when fully repaid positions are checked
    //   then no debt dust or active-borrower entry remains
    function invariant_FullRepaymentNoDebtDust() public view {
        address[] memory activeBorrowers = burnerLoans.getActiveBorrowers(address(usds));
        for (uint256 i; i < invariantActors.length; ++i) {
            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(usds),
                invariantActors[i]
            );
            bool listed = _contains(activeBorrowers, invariantActors[i]);
            if (position.debtOhm == 0) assertFalse(listed, "zero-debt borrower remains active");
            else assertTrue(listed, "active-debt borrower missing from index");
        }
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when withdrawal health is checked
    //   then active non-seizable positions remain healthy
    function invariant_WithdrawalAndActivePositionHealth() public view {
        for (uint256 i; i < invariantActors.length; ++i) {
            address actor = invariantActors[i];
            IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), actor);
            if (position.debtOhm == 0 || burnerLoans.isSeizable(address(usds), actor)) continue;
            assertGe(
                burnerLoans.positionHealthFactor(
                    address(usds),
                    position.depositedCollateral,
                    position.debtOhm
                ),
                _WAD,
                "active non-seizable position is unhealthy"
            );
        }
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when same-block repayment behavior is checked
    //   then same-block repayment remains blocked
    function invariant_SameBlockRepaymentDelay() public view {
        assertEq(handler.sameBlockRepayViolations(), 0, "same-block repayment succeeded");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when collateral custody is checked
    //   then credited collateral reconciles with solvent DepositManager custody
    function invariant_CollateralAndDepositManagerReconciliation() public view {
        uint256 creditedCollateral;
        for (uint256 i; i < invariantActors.length; ++i) {
            creditedCollateral += burnerLoans
                .getPosition(address(usds), invariantActors[i])
                .depositedCollateral;
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

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when harvest accounting is checked
    //   then harvested yield never exceeds the claimable amount
    function invariant_HarvestBound() public view {
        assertEq(handler.harvestBoundViolations(), 0, "harvest exceeded claimable yield");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when seized positions are checked
    //   then seizure closes debt and collateral and removes the active borrower
    function invariant_SeizureClosesEntirePosition() public view {
        assertEq(handler.seizureEligibilityViolations(), 0, "scan returned ineligible borrower");
        address[] memory activeBorrowers = burnerLoans.getActiveBorrowers(address(usds));
        for (uint256 i; i < invariantActors.length; ++i) {
            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(usds),
                invariantActors[i]
            );
            if (position.status != IBurnerLoans.PositionStatus.Seized) continue;
            assertEq(position.debtOhm, 0, "seized debt remains");
            assertEq(position.depositedCollateral, 0, "seized collateral remains");
            assertFalse(
                _contains(activeBorrowers, invariantActors[i]),
                "seized borrower remains active"
            );
        }
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when periphery custody balances are checked
    //   then Burner Loans periphery contracts retain no collateral or OHM
    function invariant_NoResidualCustodyBalances() public view {
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "BurnerLoans retained collateral");
        assertEq(ohm.balanceOf(address(burnerLoans)), 0, "BurnerLoans retained OHM");
        assertEq(usds.balanceOf(address(seizer)), 0, "protocol seizer retained collateral");
        assertEq(usds.balanceOf(address(composites)), 0, "composite retained collateral");
        assertEq(ohm.balanceOf(address(composites)), 0, "composite retained OHM");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when backing is checked
    //   then borrowing and seizure preserve the backing floor
    function invariant_BackingPreservation() public view {
        assertEq(handler.backingViolations(), 0, "borrow or seizure reduced backing below floor");
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when credited collateral is checked
    //   then credited collateral does not exceed withdrawable custody assets
    function invariant_CreditedCollateralWithdrawable() public view {
        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(usds)
        );
        assertLe(
            status.liabilities,
            status.assets + status.borrowed,
            "credit exceeds custody assets"
        );
    }

    // invariant
    // given any sequence of Burner Loans handler calls
    //  when position maturities are checked
    //   then active maturities remain within the configured horizon
    function invariant_TermHorizon() public view {
        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        for (uint256 i; i < invariantActors.length; ++i) {
            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(usds),
                invariantActors[i]
            );
            if (position.debtOhm == 0) continue;
            assertLe(
                position.maturity,
                block.timestamp + config.maxMaturityHorizon,
                "maturity exceeds configured horizon"
            );
        }
    }

    function _contains(address[] memory values_, address value_) private pure returns (bool) {
        for (uint256 i; i < values_.length; ++i) if (values_[i] == value_) return true;
        return false;
    }
}
