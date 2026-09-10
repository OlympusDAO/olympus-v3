// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {Vm} from "forge-std/Vm.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

contract BurnerLoansEndToEndGasTest is BurnerLoansSeizureTestBase {
    uint128 internal constant _COLLATERAL = 2_000e18;
    uint128 internal constant _DEBT = 100e9;
    uint16 internal constant _MAX_BORROWERS_TO_CHECK = 500;
    uint8 internal constant _MAX_BORROWERS_TO_SEIZE = 50;

    BurnerLoansSeizer internal _seizer;
    address internal _heart;

    function setUp() public override {
        super.setUp();
        _setDefaultConfigOperator();
        _enableConfigTimelock();

        _heart = makeAddr("gasHeart");
        vm.startPrank(admin);
        _seizer = new BurnerLoansSeizer(
            kernel,
            address(burnerLoans),
            _MAX_BORROWERS_TO_CHECK,
            _MAX_BORROWERS_TO_SEIZE,
            10_000_000
        );
        kernel.executeAction(Actions.ActivatePolicy, address(_seizer));
        rolesAdmin.grantRole(HEART_ROLE, _heart);
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_seizer));
        _seizer.addAsset(address(usds));
        _seizer.enable("");
        vm.stopPrank();
    }

    // depositCollateral
    // given a configured direct-custody market and a new borrower
    //  when the borrower deposits collateral for the first time
    //   then it records the end-to-end gas cost
    function test_gasSnapshot_depositCollateral_first() public {
        _fundAndApproveCollateral(alice, _COLLATERAL);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.depositCollateral.first");
        burnerLoans.depositCollateral(address(usds), _COLLATERAL, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            _COLLATERAL,
            "deposited collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    // depositCollateral
    // given a borrower already has credited collateral
    //  when the borrower deposits more collateral
    //   then it records the steady-state gas cost
    function test_gasSnapshot_depositCollateral_additional() public {
        _depositForAlice(_COLLATERAL);
        uint128 additionalCollateral = 500e18;
        usds.mint(alice, additionalCollateral);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.depositCollateral.additional");
        burnerLoans.depositCollateral(address(usds), additionalCollateral, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            _COLLATERAL + additionalCollateral,
            "deposited collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    // withdrawCollateral
    // given a debt-free borrower has credited collateral
    //  when the borrower withdraws part of it
    //   then it records the end-to-end gas cost
    function test_gasSnapshot_withdrawCollateral_partial() public {
        _depositForAlice(_COLLATERAL);
        uint128 withdrawal = 500e18;

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.withdrawCollateral.partial");
        burnerLoans.withdrawCollateral(address(usds), withdrawal, alice, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            _COLLATERAL - withdrawal,
            "remaining collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    // supply
    // given the protocol provider has approved OHM
    //  when it supplies funding inventory
    //   then it records provider funding and approval-adjustment gas
    function test_gasSnapshot_inventory_supply() public {
        ohm.mint(protocolProvider, _DEBT);
        vm.prank(protocolProvider);
        ohm.approve(address(inventory), _DEBT);

        vm.startPrank(protocolProvider);
        vm.startSnapshotGas("BurnerLoansInventory.supply");
        inventory.supply(_DEBT);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedOhm(), _DEBT, "provider claim");
        assertEq(inventory.suppliedIdleOhm(), _DEBT, "supplied idle");
        _assertGasRecorded(gasUsed);
    }

    // withdraw
    // given the provider's full claim is idle
    //  when it withdraws part of that claim
    //   then it records provider exit and approval-restoration gas
    function test_gasSnapshot_inventory_withdraw() public {
        _supplyOhm(_DEBT);

        vm.startPrank(protocolProvider);
        vm.startSnapshotGas("BurnerLoansInventory.withdraw");
        inventory.withdraw(40e9, protocolProvider);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedOhm(), 60e9, "remaining claim");
        assertEq(inventory.suppliedIdleOhm(), 60e9, "remaining supplied idle");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given a borrower has sufficient collateral and no debt
    //  when the borrower originates debt
    //   then it records the first-borrow gas cost
    function test_gasSnapshot_borrow_first() public {
        _depositForAlice(_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _DEBT,
            alice
        );

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.borrow.first");
        burnerLoans.borrow(address(usds), _DEBT, alice, alice, preview.fee);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, _DEBT, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given supplied idle OHM covers the full debt amount
    //  when the borrower originates debt
    //   then it records the inventory-funded path without minting
    function test_gasSnapshot_borrow_inventoryFunded() public {
        _supplyOhm(_DEBT);
        _depositForAlice(_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _DEBT,
            alice
        );

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.borrow.inventoryFunded");
        burnerLoans.borrow(address(usds), _DEBT, alice, alice, preview.fee);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedIdleOhm(), 0, "supplied idle consumed");
        assertEq(inventory.activePrincipalOhm(), _DEBT, "active principal");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given supplied idle OHM covers part of the debt amount
    //  when the borrower originates debt
    //   then it records the mixed inventory-and-mint path
    function test_gasSnapshot_borrow_mixedFunded() public {
        _supplyOhm(40e9);
        _depositForAlice(_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _DEBT,
            alice
        );

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.borrow.mixedFunded");
        burnerLoans.borrow(address(usds), _DEBT, alice, alice, preview.fee);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedIdleOhm(), 0, "supplied idle consumed");
        assertEq(inventory.activePrincipalOhm(), _DEBT, "active principal");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given a borrower already has an active debt position
    //  when the borrower takes additional debt
    //   then it records the steady-state borrow gas cost
    function test_gasSnapshot_borrow_additional() public {
        _borrowForAlice(50e9);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            50e9,
            alice
        );

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.borrow.additional");
        burnerLoans.borrow(address(usds), 50e9, alice, alice, preview.fee);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, _DEBT, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given a borrower has active debt and approved OHM
    //  when the borrower partially repays
    //   then it records the steady-state repayment gas cost
    function test_gasSnapshot_repay_partial() public {
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(alice);
        ohm.approve(address(burnerLoans), 40e9);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.repay.partial");
        burnerLoans.repay(address(usds), 40e9, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 60e9, "remaining debt");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given the repayment is fully needed to replenish the provider claim
    //  when the borrower partially repays
    //   then it records the retained-repayment path
    function test_gasSnapshot_repay_retained() public {
        _supplyOhm(_DEBT);
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(alice);
        ohm.approve(address(burnerLoans), 40e9);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.repay.retained");
        burnerLoans.repay(address(usds), 40e9, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedIdleOhm(), 40e9, "replenished supplied idle");
        assertEq(inventory.activePrincipalOhm(), 60e9, "remaining principal");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given repayment exceeds the provider claim deficit
    //  when the borrower partially repays
    //   then it records the retain-then-burn path
    function test_gasSnapshot_repay_split() public {
        _supplyOhm(40e9);
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(alice);
        ohm.approve(address(burnerLoans), 60e9);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.repay.split");
        burnerLoans.repay(address(usds), 60e9, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.suppliedIdleOhm(), 40e9, "claim replenished");
        assertEq(inventory.activePrincipalOhm(), 40e9, "remaining principal");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given a borrower has active debt and approved OHM
    //  when the borrower repays the full balance
    //   then it records the position-closing repayment gas cost
    function test_gasSnapshot_repay_full() public {
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(alice);
        ohm.approve(address(burnerLoans), _DEBT);

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.repay.full");
        burnerLoans.repay(address(usds), _DEBT, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "remaining debt");
        _assertGasRecorded(gasUsed);
    }

    // extend
    // given a borrower has a healthy active position
    //  when the borrower extends it by one term
    //   then it records the end-to-end extension gas cost
    function test_gasSnapshot_extend_oneTerm() public {
        _borrowForAlice(_DEBT);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.startPrank(alice);
        vm.startSnapshotGas("BurnerLoans.extend.oneTerm");
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "extended maturity"
        );
        _assertGasRecorded(gasUsed);
    }

    // seize
    // given one borrower has an unhealthy active position
    //  when a keeper seizes the position
    //   then it records the end-to-end default and collateral-routing gas cost
    function test_gasSnapshot_seize_single() public {
        _makeUnhealthy(alice);
        address[] memory borrowers = _single(alice);

        vm.startPrank(keeper);
        vm.startSnapshotGas("BurnerLoans.seize.single");
        burnerLoans.seize(address(usds), borrowers);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // claimYield
    // given a vault-backed market has earned yield above borrower liabilities
    //  when a keeper claims the surplus
    //   then it records the end-to-end custody withdrawal gas cost
    function test_gasSnapshot_claimYield_treasuryOnly() public {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        uint128 collateral = 100e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);
        uint256 treasuryBefore = asset.balanceOf(address(trsry));

        vm.startSnapshotGas("BurnerLoans.claimYield.treasuryOnly");
        burnerLoans.claimYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();
        uint256 claimed = asset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
        _assertGasRecorded(gasUsed);
    }

    // claimYield
    // given a vault-backed market routes all yield to a compatible repurchase recipient
    //  when a keeper claims the surplus
    //   then it records recipient validation and one non-Treasury transfer
    function test_gasSnapshot_claimYield_repurchaseOnly() public {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        MockYieldRepurchaseRecipient recipient = _configureYieldRecipient(asset, vault, 10_000);
        uint128 collateral = 100e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);
        uint256 treasuryBefore = asset.balanceOf(address(trsry));
        uint256 recipientBefore = asset.balanceOf(address(recipient));

        vm.startSnapshotGas("BurnerLoans.claimYield.repurchaseOnly");
        burnerLoans.claimYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();
        uint256 recipientAmount = asset.balanceOf(address(recipient)) - recipientBefore;
        uint256 claimed = recipientAmount + asset.balanceOf(address(trsry)) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
        assertEq(recipientAmount, claimed, "repurchase recipient");
        _assertGasRecorded(gasUsed);
    }

    // claimYield
    // given a vault-backed market routes yield to repurchase, two direct recipients, and Treasury
    //  when a keeper claims the surplus
    //   then it records validation and all mixed distribution legs
    function test_gasSnapshot_claimYield_mixed() public {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        MockYieldRepurchaseRecipient recipient = _configureYieldRecipient(asset, vault, 3_000);
        address directRecipientOne = makeAddr("gasDirectRecipientOne");
        address directRecipientTwo = makeAddr("gasDirectRecipientTwo");
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.repurchaseRecipientBps = 3_000;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](2);
        routing.directAllocations[0] = IBurnerLoans.DirectYieldAllocation({
            recipient: directRecipientOne,
            bps: 2_000
        });
        routing.directAllocations[1] = IBurnerLoans.DirectYieldAllocation({
            recipient: directRecipientTwo,
            bps: 1_000
        });
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(address(asset), routing);

        uint128 collateral = 100e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);

        vm.startSnapshotGas("BurnerLoans.claimYield.mixed");
        burnerLoans.claimYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();

        uint256 claimed = asset.balanceOf(address(recipient)) +
            asset.balanceOf(directRecipientOne) +
            asset.balanceOf(directRecipientTwo) +
            asset.balanceOf(address(trsry));
        assertGt(claimed, 0, "claimed yield");
        assertEq(asset.balanceOf(address(recipient)), (claimed * 3_000) / 10_000, "repurchase");
        assertEq(asset.balanceOf(directRecipientOne), (claimed * 2_000) / 10_000, "direct one");
        assertEq(asset.balanceOf(directRecipientTwo), (claimed * 1_000) / 10_000, "direct two");
        _assertGasRecorded(gasUsed);
    }

    // claimYield
    // given a vault-backed market routes yield to YRF and five direct recipients
    //  when a keeper claims the surplus
    //   then it records the six-recipient distribution gas cost
    function test_gasSnapshot_claimYield_yrfPlusFiveDirect() public {
        _snapshotClaimYieldWithYrfAndDirectRecipients(
            5,
            "BurnerLoans.claimYield.yrfPlusFiveDirect"
        );
    }

    // claimYield
    // given a vault-backed market routes yield to YRF and ten direct recipients
    //  when a keeper claims the surplus
    //   then it records the eleven-recipient distribution gas cost
    function test_gasSnapshot_claimYield_yrfPlusTenDirect() public {
        _snapshotClaimYieldWithYrfAndDirectRecipients(
            10,
            "BurnerLoans.claimYield.yrfPlusTenDirect"
        );
    }

    // claimYield
    // given a vault-backed market routes yield to YRF and twenty-five direct recipients
    //  when a keeper claims the surplus
    //   then it records the twenty-six-recipient distribution gas cost
    function test_gasSnapshot_claimYield_yrfPlusTwentyFiveDirect() public {
        _snapshotClaimYieldWithYrfAndDirectRecipients(
            25,
            "BurnerLoans.claimYield.yrfPlusTwentyFiveDirect"
        );
    }

    // setGlobalDebtCap
    // given Burner Loans is enabled
    //  when governance updates the global active-debt cap
    //   then it records the cap and MINTR reconciliation gas cost
    function test_gasSnapshot_admin_setGlobalDebtCap() public {
        uint128 newCap = 2_000_000e9;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setGlobalDebtCap");
        burnerLoansConfig.setGlobalDebtCap(newCap);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(inventory.globalDebtCapOhm(), newCap, "global debt cap");
        _assertGasRecorded(gasUsed);
    }

    // setBackingOracle
    // given Burner Loans is enabled
    //  when governance changes the backing oracle
    //   then it records the direct admin gas cost
    function test_gasSnapshot_admin_setBackingOracle() public {
        MockOlympusBackingOracle newOracle = new MockOlympusBackingOracle(12e18);

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoans.admin.setBackingOracle");
        burnerLoans.setBackingOracle(address(newOracle));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.backingOracle(), address(newOracle), "backing oracle");
        _assertGasRecorded(gasUsed);
    }

    // syncMintApproval
    // given MINTR approval already equals unused global capacity
    //  when it reconciles MINTR approval with active debt
    //   then it records the no-op reconciliation gas cost
    function test_gasSnapshot_syncMintApproval_noop() public {
        vm.recordLogs();
        vm.startPrank(burnerLoansAdmin);
        vm.startSnapshotGas("BurnerLoansInventory.syncMintApproval.noop");
        uint256 approval = inventory.syncMintApproval();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(approval, inventory.globalDebtCapOhm(), "mint approval");
        _assertEventEmitted(
            vm.getRecordedLogs(),
            address(inventory),
            keccak256("MintApprovalSynchronized(uint256)")
        );
        _assertGasRecorded(gasUsed);
    }

    // syncMintApproval
    // given a full-cap position has defaulted and its restored approval is subsequently reduced
    //  when the admin reconciles approval
    //   then it records the capacity-restoration gas cost
    function test_gasSnapshot_syncMintApproval_restoreAfterDefault() public {
        vm.prank(admin);
        burnerLoansConfig.setGlobalDebtCap(_DEBT);
        _makeUnhealthy(alice);
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), _DEBT);

        vm.recordLogs();
        vm.startPrank(burnerLoansAdmin);
        vm.startSnapshotGas("BurnerLoansInventory.syncMintApproval.restoreAfterDefault");
        uint256 approval = inventory.syncMintApproval();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(approval, _DEBT, "returned approval");
        assertEq(mintr.mintApproval(address(inventory)), _DEBT, "stored approval");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active principal");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        _assertEventEmitted(
            vm.getRecordedLogs(),
            address(inventory),
            keccak256("MintApprovalSynchronized(uint256)")
        );
        _assertGasRecorded(gasUsed);
    }

    // execute
    // given no borrowers are seizable
    //  when Heart executes the seizer task
    //   then it records scanning and no-op reconciliation gas
    function test_gasSnapshot_seizer_execute_noSeizures() public {
        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizer.execute.noSeizures");
        _seizer.execute();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active principal");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.globalDebtCapOhm(),
            "mint approval"
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSeizerExecutionEvents(logs, false);
        _assertGasRecorded(gasUsed);
    }

    // execute
    // given one equivalent position is seizable
    //  when Heart executes the seizer task
    //   then it records seizure and reconciliation gas
    function test_gasSnapshot_seizer_execute_oneSeizure() public {
        _makeUnhealthyBatch(1);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizer.execute.oneSeizure");
        _seizer.execute();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSeizerBatchResult(1, treasuryBefore);
        _assertSeizerExecutionEvents(logs, true);
        _assertGasRecorded(gasUsed);
    }

    // execute
    // given ten equivalent positions are seizable
    //  when Heart executes the seizer task
    //   then it records medium-batch seizure and reconciliation gas
    function test_gasSnapshot_seizer_execute_batch10() public {
        _makeUnhealthyBatch(10);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizer.execute.batch10");
        _seizer.execute();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSeizerBatchResult(10, treasuryBefore);
        _assertSeizerExecutionEvents(logs, true);
        _assertGasRecorded(gasUsed);
    }

    // execute
    // given the maximum batch of fifty equivalent positions is seizable
    //  when Heart executes the seizer task
    //   then it records maximum-batch seizure and reconciliation gas
    function test_gasSnapshot_seizer_execute_maximumBatch() public {
        uint256 borrowerCount = _seizer.MAX_BORROWERS_TO_SEIZE();
        _makeUnhealthyBatch(borrowerCount);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizer.execute.maximumBatch");
        _seizer.execute();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertSeizerBatchResult(borrowerCount, treasuryBefore);
        _assertSeizerExecutionEvents(logs, true);
        _assertGasRecorded(gasUsed);
    }

    // addAsset
    // given PRICE and DepositManager support a new collateral asset
    //  when governance creates its Burner Loans market
    //   then it records the complete configuration and FLOAN market-creation gas cost
    function test_gasSnapshot_config_addAsset() public {
        MockERC20 asset = new MockERC20("Gas Collateral", "gCOLL", 18);
        _configurePrice(address(asset), 1e18);
        _configureDepositManagerAsset(address(asset));

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.addAsset");
        burnerLoansConfig.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertTrue(burnerLoansConfig.isAssetConfigured(address(asset)), "asset configured");
        _assertGasRecorded(gasUsed);
    }

    // setConfigurator
    // given no registered assets and a compatible replacement Config
    //  when governance replaces an existing Config
    //   then it records the fixed migration gas cost without market writes
    function test_gasSnapshot_setConfigurator_zeroAssets() public {
        BurnerLoansHarness freshFacility = new BurnerLoansHarness(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            backingOracle
        );
        BurnerLoansConfig outgoing = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        BurnerLoansConfig replacement = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(freshFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(outgoing));
        kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        outgoing.setFacility(address(freshFacility));
        replacement.setFacility(address(freshFacility));
        freshFacility.setConfigurator(address(outgoing));

        vm.startSnapshotGas("BurnerLoans.setConfigurator.zeroAssets");
        freshFacility.setConfigurator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(freshFacility.configurator(), address(replacement), "replacement configurator");
        _assertGasRecorded(gasUsed);
    }

    // setConfigurator
    // given one registered asset and a compatible replacement Config
    //  when governance migrates Config
    //   then it records the fixed plus one-market migration gas cost
    function test_gasSnapshot_setConfigurator_oneAsset() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoans.setConfigurator.oneAsset");
        burnerLoans.setConfigurator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            floan.getMarket(burnerLoansConfig.marketId(address(usds))).manager,
            address(replacement),
            "market manager"
        );
        _assertGasRecorded(gasUsed);
    }

    // setConfigurator
    // given one registered asset with two matching markets and a compatible replacement Config
    //  when governance migrates Config
    //   then it records the incremental matching-market migration gas cost
    function test_gasSnapshot_setConfigurator_oneAssetTwoMarkets() public {
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoans.setConfigurator.oneAssetTwoMarkets");
        burnerLoans.setConfigurator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(floan.getMarket(firstMarketId).manager, address(replacement), "first manager");
        assertEq(floan.getMarket(secondMarketId).manager, address(replacement), "second manager");
        _assertGasRecorded(gasUsed);
    }

    // setConfigurator
    // given three registered assets and a compatible replacement Config
    //  when governance migrates Config
    //   then it records representative multi-market migration gas scaling
    function test_gasSnapshot_setConfigurator_threeAssets() public {
        address secondAsset = address(_addDirectAssetForTest());
        address thirdAsset = address(_addDirectAssetForTest());
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        vm.prank(admin);
        burnerLoans.disable("");
        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoans.setConfigurator.threeAssets");
        burnerLoans.setConfigurator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            floan.getMarket(burnerLoansConfig.marketId(address(usds))).manager,
            address(replacement),
            "first market manager"
        );
        assertEq(
            floan.getMarket(burnerLoansConfig.marketId(secondAsset)).manager,
            address(replacement),
            "second market manager"
        );
        assertEq(
            floan.getMarket(burnerLoansConfig.marketId(thirdAsset)).manager,
            address(replacement),
            "third market manager"
        );
        _assertGasRecorded(gasUsed);
    }

    // setAssetDebtCap
    // given an existing Burner Loans market
    //  when governance updates its debt cap
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_setAssetDebtCap() public {
        uint128 newCap = 200_000e9;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetDebtCap");
        burnerLoansConfig.setAssetDebtCap(address(usds), newCap);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).debtCap, newCap, "asset debt cap");
        _assertGasRecorded(gasUsed);
    }

    // setAssetRiskConfig
    // given an existing Burner Loans market
    //  when governance replaces its risk configuration
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_setAssetRiskConfig() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.maxLtvBps = 9_500;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetRiskConfig");
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).maxLtvBps, 9_500, "maximum LTV");
        _assertGasRecorded(gasUsed);
    }

    // setAssetFeeConfig
    // given an existing Burner Loans market
    //  when governance replaces its utilization fee curve
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_setAssetFeeConfig() public {
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = 30;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetFeeConfig");
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "base fee");
        _assertGasRecorded(gasUsed);
    }

    // setYieldAssetRouting
    // given an existing Burner Loans market has its default Treasury-only route
    //  when governance installs a route with twenty-five direct recipients
    //   then it records complete route validation, replacement, and event gas
    function test_gasSnapshot_config_setYieldAssetRouting_twentyFiveDirect() public {
        IBurnerLoans.AssetYieldRouting memory routing = _directOnlyRouting(25);

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setYieldAssetRouting.twentyFiveDirect");
        burnerLoansConfig.setYieldAssetRouting(address(usds), routing);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoans.getYieldAssetRouting(address(usds)).directAllocations.length,
            25,
            "direct allocation count"
        );
        _assertGasRecorded(gasUsed);
    }

    // setAssetOriginationsEnabled
    // given an existing enabled Burner Loans market
    //  when governance disables originations
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_disableOriginations() public {
        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.disableOriginations");
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations disabled"
        );
        _assertGasRecorded(gasUsed);
    }

    // setAssetOriginationsEnabled
    // given an existing disabled Burner Loans market
    //  when governance re-enables originations
    //   then it records dependency validation and the FLOAN update gas cost
    function test_gasSnapshot_config_enableOriginations() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.enableOriginations");
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations enabled"
        );
        _assertGasRecorded(gasUsed);
    }

    // queueBatch
    // given the config timelock is authorized and enabled
    //  when the Burner Loans admin queues two related configuration actions
    //   then it records validation and storage of the complete batch
    function test_gasSnapshot_timelock_queueBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _configBatch();

        vm.startPrank(burnerLoansAdmin);
        vm.startSnapshotGas("BurnerLoansConfigTimelock.queueBatch.twoActions");
        uint64 actionId = configTimelock.queueBatch(actions);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(configTimelock.getQueuedActionLength(actionId), 2, "queued actions");
        _assertGasRecorded(gasUsed);
    }

    // executeQueuedAction
    // given two configuration actions have passed the timelock delay
    //  when a keeper executes the batch
    //   then it records the complete validation, FLOAN updates, and queue cleanup gas cost
    function test_gasSnapshot_timelock_executeBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _configBatch();
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.startSnapshotGas("BurnerLoansConfigTimelock.executeBatch.twoActions");
        configTimelock.executeQueuedAction(actionId);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).maxLtvBps, 9_500, "maximum LTV");
        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "base fee");
        _assertGasRecorded(gasUsed);
    }

    // executeQueuedAction
    // given a twenty-five-recipient direct route has passed the timelock delay
    //  when a keeper executes the dynamic route payload
    //   then it records canonical decoding, route validation, storage, and queue cleanup gas
    function test_gasSnapshot_timelock_executeYieldAssetRouting() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _yieldAssetRoutingBatch();
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.startSnapshotGas("BurnerLoansConfigTimelock.executeYieldAssetRouting.twentyFiveDirect");
        configTimelock.executeQueuedAction(actionId);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertEq(
            burnerLoans.getYieldAssetRouting(address(usds)).directAllocations.length,
            25,
            "direct allocation count"
        );
        _assertGasRecorded(gasUsed);
    }

    function _fundAndApproveCollateral(address account_, uint128 amount_) internal {
        usds.mint(account_, amount_ + 100e18);
        vm.prank(account_);
        usds.approve(address(burnerLoans), type(uint256).max);
    }

    function _depositForAlice(uint128 amount_) internal {
        _fundAndApproveCollateral(alice, amount_);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(usds), amount_, alice);
    }

    function _borrowForAlice(uint128 amount_) internal {
        _depositForAlice(_COLLATERAL);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            amount_,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), amount_, alice, alice, preview.fee);
    }

    function _configureVaultMarket() internal returns (MockERC20 asset, MockERC4626 vault) {
        asset = new MockERC20("Gas Vault Collateral", "gvCOLL", 18);
        vault = new MockERC4626(ERC20(address(asset)), "Gas Vault", "gVAULT");
        _configurePrice(address(asset), 1e18);

        vm.startPrank(admin);
        depositManager.addAsset(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(
            IERC20(address(asset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        burnerLoansConfig.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        vm.stopPrank();
    }

    function _configureYieldRecipient(
        MockERC20 asset_,
        MockERC4626 vault_,
        uint16 bps_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        vm.startPrank(admin);
        recipient = new MockYieldRepurchaseRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(vault_), address(asset_), true);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(recipient));
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.repurchaseRecipientBps = bps_;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](0);
        burnerLoansConfig.setYieldAssetRouting(address(asset_), routing);
        vm.stopPrank();
    }

    function _directOnlyRouting(
        uint16 directCount_
    ) internal returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](directCount_);
        for (uint256 i; i < routing.directAllocations.length; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: makeAddr(string.concat("gasDirectRecipient", vm.toString(i))),
                bps: 1
            });
        }
    }

    function _yieldRoutingWithDirectRecipients(
        uint16 directCount_
    ) internal returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing = _directOnlyRouting(directCount_);
        routing.repurchaseRecipientBps = 1_000;
    }

    function _snapshotClaimYieldWithYrfAndDirectRecipients(
        uint16 directCount_,
        string memory snapshotName_
    ) internal {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        MockYieldRepurchaseRecipient recipient = _configureYieldRecipient(asset, vault, 1_000);
        IBurnerLoans.AssetYieldRouting memory routing = _yieldRoutingWithDirectRecipients(
            directCount_
        );
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(address(asset), routing);

        uint128 collateral = 100e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);

        vm.startSnapshotGas(snapshotName_);
        burnerLoans.claimYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();

        assertGt(asset.balanceOf(address(recipient)), 0, "repurchase recipient amount");
        for (uint256 i; i < routing.directAllocations.length; ++i) {
            assertGt(
                asset.balanceOf(routing.directAllocations[i].recipient),
                0,
                "direct recipient amount"
            );
        }
        _assertGasRecorded(gasUsed);
    }

    function _supplyOhm(uint128 amount_) internal {
        ohm.mint(protocolProvider, amount_);
        vm.startPrank(protocolProvider);
        ohm.approve(address(inventory), amount_);
        inventory.supply(amount_);
        vm.stopPrank();
    }

    function _configBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate;
        riskUpdate.maxLtvBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection;
        riskSelection.maxLtvBps = true;
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetRiskConfig.selector,
            payload: abi.encode(address(usds), riskUpdate, riskSelection)
        });

        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 30;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;
        actions[1] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetFeeConfig.selector,
            payload: abi.encode(address(usds), feeUpdate, feeSelection)
        });
    }

    function _yieldAssetRoutingBatch()
        internal
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setYieldAssetRouting.selector,
            payload: abi.encode(address(usds), _directOnlyRouting(25))
        });
    }

    function _assertGasRecorded(uint256 gasUsed_) internal pure {
        assertGt(gasUsed_, 0, "gas snapshot should record gas");
    }

    function _makeUnhealthyBatch(uint256 borrowerCount_) internal {
        for (uint256 i; i < borrowerCount_; ++i) {
            _borrow(_gasBorrower(i), _COLLATERAL, _DEBT);
        }
        _configurePrice(address(ohm), 20e18);
    }

    function _assertSeizerBatchResult(
        uint256 borrowerCount_,
        uint256 treasuryBefore_
    ) internal view {
        for (uint256 i; i < borrowerCount_; ++i) {
            IBurnerLoans.Position memory position = burnerLoans.getPosition(
                address(usds),
                _gasBorrower(i)
            );
            assertEq(position.debtOhm, 0, "position debt");
            assertEq(position.depositedCollateral, 0, "position collateral");
        }
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "facility principal");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "market principal");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            borrowerCount_ * _DEBT,
            "market defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.globalDebtCapOhm(),
            "mint approval"
        );
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore_ + borrowerCount_ * _COLLATERAL,
            "treasury collateral"
        );
    }

    function _gasBorrower(uint256 index_) internal pure returns (address) {
        return address(bytes20(keccak256(abi.encode("gasBorrower", index_))));
    }

    function _assertSeizerExecutionEvents(Vm.Log[] memory logs_, bool seizure_) internal view {
        if (seizure_) {
            _assertEventEmitted(
                logs_,
                address(burnerLoans),
                keccak256(
                    "SeizureBatchSettled(address,address,uint256,uint256,uint256,uint256,uint256)"
                )
            );
        }
        _assertEventEmitted(
            logs_,
            address(_seizer),
            keccak256("SeizureExecuted(address,uint256,uint256,uint256)")
        );
    }

    function _assertEventEmitted(
        Vm.Log[] memory logs_,
        address emitter_,
        bytes32 topic_
    ) internal pure {
        for (uint256 i; i < logs_.length; ++i) {
            if (
                logs_[i].emitter == emitter_ &&
                logs_[i].topics.length != 0 &&
                logs_[i].topics[0] == topic_
            ) return;
        }
        assertTrue(false, "expected event not emitted");
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
