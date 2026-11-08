// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Actions, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansEndToEndGasTest is BurnerLoansConfigTimelockTest {
    uint128 internal constant _COLLATERAL = 2_000e6;
    uint128 internal constant _DEBT = 100e9;
    uint16 internal constant _MAX_BORROWERS_TO_CHECK = 500;
    uint8 internal constant _MAX_BORROWERS_TO_SEIZE = 50;

    BurnerLoansSeizerTask internal _seizer;
    BurnerLoansYieldClaimerTask internal _claimer;
    OlympusMinter internal _mintr;
    address internal _treasury;
    address internal _provider = address(0xBEEF);
    address internal _keeper = address(0xCEEF);
    address internal _heart;

    function setUp() public override {
        super.setUp();
        _price.setPrice(address(_ohm), 10e18);
        _treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        _mintr = OlympusMinter(address(_kernel.getModuleForKeycode(toKeycode("MINTR"))));
        _rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, _provider);
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, address(this));
        _claimer = new BurnerLoansYieldClaimerTask(_kernel, address(_core), 2_000_000);
        _kernel.executeAction(Actions.ActivatePolicy, address(_claimer));
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        _claimer.enable("");

        _heart = makeAddr("gasHeart");
        vm.startPrank(address(this));
        _seizer = new BurnerLoansSeizerTask(
            _kernel,
            IBurnerLoansSeize(address(_liquidation)),
            IBurnerLoansLens(address(_lens)),
            _MAX_BORROWERS_TO_CHECK,
            _MAX_BORROWERS_TO_SEIZE,
            10_000_000
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_seizer));
        _rolesAdmin.grantRole(HEART_ROLE, _heart);
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_seizer));
        _seizer.addAsset(address(_asset));
        _seizer.enable("");
        vm.stopPrank();
    }

    // depositCollateral
    // given a configured direct-custody market and a new borrower
    //  when the borrower deposits collateral for the first time
    //   then it records the end-to-end gas cost
    function test_gasSnapshot_depositCollateral_first() public {
        _fundAndApproveCollateral(_borrower, _COLLATERAL);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansCollateral.depositCollateral.first");
        _collateral.depositCollateral(address(_asset), _COLLATERAL, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
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
        uint128 additionalCollateral = 500e6;
        _asset.mint(_borrower, additionalCollateral);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansCollateral.depositCollateral.additional");
        _collateral.depositCollateral(address(_asset), additionalCollateral, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
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
        uint128 withdrawal = 500e6;

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansCollateral.withdrawCollateral.partial");
        _collateral.withdrawCollateral(address(_asset), withdrawal, _borrower, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            _COLLATERAL - withdrawal,
            "remaining collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    // supply
    // given the protocol provider has approved OHM
    //  when it supplies funding _inventory
    //   then it records provider funding and approval-adjustment gas
    function test_gasSnapshot_inventory_supply() public {
        _ohm.mint(_provider, _DEBT);
        vm.prank(_provider);
        _ohm.approve(address(_inventory), _DEBT);

        vm.startPrank(_provider);
        vm.startSnapshotGas("BurnerLoansInventory.supply");
        _inventory.supply(_DEBT);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedOhm(), _DEBT, "provider claim");
        assertEq(_inventory.suppliedIdleOhm(), _DEBT, "supplied idle");
        _assertGasRecorded(gasUsed);
    }

    // withdraw
    // given the provider's full claim is idle
    //  when it withdraws part of that claim
    //   then it records provider exit and approval-restoration gas
    function test_gasSnapshot_inventory_withdraw() public {
        _supplyOhm(_DEBT);

        vm.startPrank(_provider);
        vm.startSnapshotGas("BurnerLoansInventory.withdraw");
        _inventory.withdraw(40e9, _provider);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedOhm(), 60e9, "remaining claim");
        assertEq(_inventory.suppliedIdleOhm(), 60e9, "remaining supplied idle");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given a borrower has sufficient collateral and no debt
    //  when the borrower originates debt
    //   then it records the first-borrow gas cost
    function test_gasSnapshot_borrow_first() public {
        _depositForAlice(_COLLATERAL);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            _DEBT,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.borrow.first");
        _debt.borrow(address(_asset), _DEBT, _borrower, _borrower, preview.fee, address(0));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, _DEBT, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given supplied idle OHM covers the full debt amount
    //  when the borrower originates debt
    //   then it records the _inventory-funded path without minting
    function test_gasSnapshot_borrow_inventoryFunded() public {
        _supplyOhm(_DEBT);
        _depositForAlice(_COLLATERAL);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            _DEBT,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.borrow.inventoryFunded");
        _debt.borrow(address(_asset), _DEBT, _borrower, _borrower, preview.fee, address(0));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedIdleOhm(), 0, "supplied idle consumed");
        assertEq(_inventory.activePrincipalOhm(), _DEBT, "active principal");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given supplied idle OHM covers part of the debt amount
    //  when the borrower originates debt
    //   then it records the mixed _inventory-and-mint path
    function test_gasSnapshot_borrow_mixedFunded() public {
        _supplyOhm(40e9);
        _depositForAlice(_COLLATERAL);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            _DEBT,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.borrow.mixedFunded");
        _debt.borrow(address(_asset), _DEBT, _borrower, _borrower, preview.fee, address(0));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedIdleOhm(), 0, "supplied idle consumed");
        assertEq(_inventory.activePrincipalOhm(), _DEBT, "active principal");
        _assertGasRecorded(gasUsed);
    }

    // borrow
    // given a borrower already has an active debt position
    //  when the borrower takes additional debt
    //   then it records the steady-state borrow gas cost
    function test_gasSnapshot_borrow_additional() public {
        _borrowForAlice(50e9);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            50e9,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.borrow.additional");
        _debt.borrow(address(_asset), 50e9, _borrower, _borrower, preview.fee, address(0));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, _DEBT, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given a borrower has active debt and approved OHM
    //  when the borrower partially repays
    //   then it records the steady-state repayment gas cost
    function test_gasSnapshot_repay_partial() public {
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(_borrower);
        _ohm.approve(address(_core), 40e9);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.repay.partial");
        _debt.repay(address(_asset), 40e9, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, 60e9, "remaining debt");
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
        vm.prank(_borrower);
        _ohm.approve(address(_core), 40e9);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.repay.retained");
        _debt.repay(address(_asset), 40e9, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedIdleOhm(), 40e9, "replenished supplied idle");
        assertEq(_inventory.activePrincipalOhm(), 60e9, "remaining principal");
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
        vm.prank(_borrower);
        _ohm.approve(address(_core), 60e9);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.repay.split");
        _debt.repay(address(_asset), 60e9, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.suppliedIdleOhm(), 40e9, "claim replenished");
        assertEq(_inventory.activePrincipalOhm(), 40e9, "remaining principal");
        _assertGasRecorded(gasUsed);
    }

    // repay
    // given a borrower has active debt and approved OHM
    //  when the borrower repays the full balance
    //   then it records the position-closing repayment gas cost
    function test_gasSnapshot_repay_full() public {
        _borrowForAlice(_DEBT);
        vm.roll(block.number + 1);
        vm.prank(_borrower);
        _ohm.approve(address(_core), _DEBT);

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.repay.full");
        _debt.repay(address(_asset), _DEBT, _borrower);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, 0, "remaining debt");
        _assertGasRecorded(gasUsed);
    }

    // extend
    // given a borrower has a healthy active position
    //  when the borrower extends it by one term
    //   then it records the end-to-end extension gas cost
    function test_gasSnapshot_extend_oneTerm() public {
        _borrowForAlice(_DEBT);
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory preview = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            type(uint256).max,
            address(0)
        );

        vm.startPrank(_borrower);
        vm.startSnapshotGas("BurnerLoansDebt.extend.oneTerm");
        _debt.extend(address(_asset), _borrower, 1, preview.fee, address(0));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _lens.getPosition(address(_asset), _borrower).maturity,
            preview.maturity,
            "extended maturity"
        );
        _assertGasRecorded(gasUsed);
    }

    // seize
    // given one borrower has an unhealthy active position
    //  when a _keeper seizes the position
    //   then it records the end-to-end default and collateral-routing gas cost
    function test_gasSnapshot_seize_single() public {
        _makeUnhealthy(_borrower);
        address[] memory borrowers = _single(_borrower);

        vm.startPrank(_keeper);
        vm.startSnapshotGas("BurnerLoansSeize.seize.single");
        _liquidation.seize(address(_asset), borrowers);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, 0, "position debt");
        _assertGasRecorded(gasUsed);
    }

    // claimYield
    // given a vault-backed market has earned yield above borrower liabilities
    //  when a _keeper claims the surplus
    //   then it records the end-to-end custody withdrawal gas cost
    function test_gasSnapshot_claimYield_treasuryOnly() public {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        uint128 collateral = 100e18;
        asset.mint(_borrower, collateral);
        vm.startPrank(_borrower);
        asset.approve(address(_core), collateral);
        _collateral.depositCollateral(address(asset), collateral, _borrower);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);
        uint256 treasuryBefore = asset.balanceOf(_treasury);

        vm.startSnapshotGas("BurnerLoansYieldClaimerTask.claimYield.treasuryOnly");
        _claimer.claimYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();
        uint256 claimed = asset.balanceOf(_treasury) - treasuryBefore;

        assertGt(claimed, 0, "claimed yield");
        _assertGasRecorded(gasUsed);
    }

    // setGlobalDebtCap
    // given Burner Loans is enabled
    //  when governance updates the global active-debt cap
    //   then it records the cap and MINTR reconciliation gas cost
    function test_gasSnapshot_admin_setGlobalDebtCap() public {
        uint128 newCap = 2_000_000e9;

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansInventory.setGlobalDebtCap");
        _inventory.setGlobalDebtCap(newCap);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_inventory.globalDebtCapOhm(), newCap, "global debt cap");
        _assertGasRecorded(gasUsed);
    }

    // setBackingOracle
    // given Burner Loans is enabled
    //  when governance changes the backing oracle
    //   then it records the direct address(this) gas cost
    function test_gasSnapshot_admin_setBackingOracle() public {
        MockOlympusBackingOracle newOracle = new MockOlympusBackingOracle(12e18);

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansRisk.setBackingOracle");
        _risk.setBackingOracle(address(newOracle));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_risk.backingOracle(), address(newOracle), "backing oracle");
        _assertGasRecorded(gasUsed);
    }

    // syncMintApproval
    // given MINTR approval already equals unused global capacity
    //  when it reconciles MINTR approval with active debt
    //   then it records the no-op reconciliation gas cost
    function test_gasSnapshot_syncMintApproval_noop() public {
        vm.recordLogs();
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansInventory.syncMintApproval.noop");
        uint256 approval = _inventory.syncMintApproval();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(approval, _inventory.globalDebtCapOhm(), "mint approval");
        _assertEventEmitted(
            vm.getRecordedLogs(),
            address(_inventory),
            keccak256("MintApprovalSynchronized(uint256)")
        );
        _assertGasRecorded(gasUsed);
    }

    // syncMintApproval
    // given a full-cap position has defaulted and its restored approval is subsequently reduced
    //  when the address(this) reconciles approval
    //   then it records the capacity-restoration gas cost
    function test_gasSnapshot_syncMintApproval_restoreAfterDefault() public {
        vm.prank(address(this));
        _inventory.setGlobalDebtCap(_DEBT);
        _makeUnhealthy(_borrower);
        vm.prank(_keeper);
        _liquidation.seize(address(_asset), _single(_borrower));
        vm.prank(address(_inventory));
        _mintr.decreaseMintApproval(address(_inventory), _DEBT);

        vm.recordLogs();
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansInventory.syncMintApproval.restoreAfterDefault");
        uint256 approval = _inventory.syncMintApproval();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(approval, _DEBT, "returned approval");
        assertEq(_mintr.mintApproval(address(_inventory)), _DEBT, "stored approval");
        assertEq(_core.totalActiveDebtOhm(), 0, "active principal");
        assertEq(_lens.getActiveBorrowers(address(_asset)).length, 0, "active borrowers");
        _assertEventEmitted(
            vm.getRecordedLogs(),
            address(_inventory),
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
        vm.startSnapshotGas("BurnerLoansSeizerTask.execute.noSeizures");
        _seizer.execute();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_core.totalActiveDebtOhm(), 0, "active principal");
        assertEq(_lens.getActiveBorrowers(address(_asset)).length, 0, "active borrowers");
        assertEq(
            _mintr.mintApproval(address(_inventory)),
            _inventory.globalDebtCapOhm(),
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
        uint256 treasuryBefore = _asset.balanceOf(_treasury);

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizerTask.execute.oneSeizure");
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
        uint256 treasuryBefore = _asset.balanceOf(_treasury);

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizerTask.execute.batch10");
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
        uint256 borrowerCount = _seizer.maxBorrowersToSeize();
        _makeUnhealthyBatch(borrowerCount);
        uint256 treasuryBefore = _asset.balanceOf(_treasury);

        vm.recordLogs();
        vm.startPrank(_heart);
        vm.startSnapshotGas("BurnerLoansSeizerTask.execute.maximumBatch");
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

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.addAsset");
        _config.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertTrue(_config.isAssetConfigured(address(asset)), "asset configured");
        _assertGasRecorded(gasUsed);
    }

    // setConfigOperator
    // given no registered assets and a compatible replacement Config
    //  when governance replaces an existing Config
    //   then it records the fixed migration gas cost without market writes
    function test_gasSnapshot_setConfigOperator_zeroAssets() public {
        BurnerLoansCore freshFacility = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        BurnerLoansConfig outgoing = new BurnerLoansConfig(
            _kernel,
            IBurnerLoansCore(address(freshFacility))
        );
        BurnerLoansConfig replacement = new BurnerLoansConfig(
            _kernel,
            IBurnerLoansCore(address(freshFacility))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(freshFacility));
        freshFacility.setConfigOperator(address(outgoing));
        vm.startPrank(address(this));

        vm.startSnapshotGas("BurnerLoansCore.setConfigOperator.zeroAssets");
        freshFacility.setConfigOperator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(freshFacility.configOperator(), address(replacement), "replacement configurator");
        _assertGasRecorded(gasUsed);
    }

    // setConfigOperator
    // given one registered asset and a compatible replacement Config
    //  when governance migrates Config
    //   then it records the fixed plus one-market migration gas cost
    function test_gasSnapshot_setConfigOperator_oneAsset() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _core.disable("");
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansCore.setConfigOperator.oneAsset");
        _core.setConfigOperator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _floan.getMarket(_config.marketId(address(_asset))).manager,
            address(replacement),
            "market manager"
        );
        _assertGasRecorded(gasUsed);
    }

    // setConfigOperator
    // given one registered asset with two matching markets and a compatible replacement Config
    //  when governance migrates Config
    //   then it measures registered-market handoff without touching the unregistered market
    function test_gasSnapshot_setConfigOperator_oneAssetUnregisteredMarket() public {
        uint32 firstMarketId = _config.marketId(address(_asset));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _core.disable("");
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansCore.setConfigOperator.oneAssetUnregisteredMarket");
        _core.setConfigOperator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_floan.getMarket(firstMarketId).manager, address(replacement), "first manager");
        assertEq(
            _floan.getMarket(secondMarketId).manager,
            address(_config),
            "Unregistered market manager stays independent"
        );
        _assertGasRecorded(gasUsed);
    }

    // setConfigOperator
    // given three registered assets and a compatible replacement Config
    //  when governance migrates Config
    //   then it records representative multi-market migration gas scaling
    function test_gasSnapshot_setConfigOperator_threeAssets() public {
        address secondAsset = address(_addDirectAssetForTest());
        address thirdAsset = address(_addDirectAssetForTest());
        BurnerLoansConfig replacement = _activateReplacementConfigurator();

        _core.disable("");
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansCore.setConfigOperator.threeAssets");
        _core.setConfigOperator(address(replacement));
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            _floan.getMarket(_config.marketId(address(_asset))).manager,
            address(replacement),
            "first market manager"
        );
        assertEq(
            _floan.getMarket(_config.marketId(secondAsset)).manager,
            address(replacement),
            "second market manager"
        );
        assertEq(
            _floan.getMarket(_config.marketId(thirdAsset)).manager,
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

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetDebtCap");
        _config.setAssetDebtCap(address(_asset), newCap);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_config.getAssetConfig(address(_asset)).debtCap, newCap, "asset debt cap");
        _assertGasRecorded(gasUsed);
    }

    // setAssetRiskConfig
    // given an existing Burner Loans market
    //  when governance replaces its risk configuration
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_setAssetRiskConfig() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.maxLtvBps = 9_500;

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetRiskConfig");
        _config.setAssetRiskConfig(address(_asset), config);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_config.getAssetConfig(address(_asset)).maxLtvBps, 9_500, "maximum LTV");
        _assertGasRecorded(gasUsed);
    }

    // setAssetFeeConfig
    // given an existing Burner Loans market
    //  when governance replaces its utilization fee curve
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_setAssetFeeConfig() public {
        IBurnerLoansRisk.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = 30;

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetFeeConfig");
        _config.setAssetFeeConfig(address(_asset), config);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_config.getAssetFeeConfig(address(_asset)).baseFeeBps, 30, "base fee");
        _assertGasRecorded(gasUsed);
    }

    // setAssetOriginationsEnabled
    // given an existing enabled Burner Loans market
    //  when governance disables originations
    //   then it records the end-to-end config and FLOAN update gas cost
    function test_gasSnapshot_config_disableOriginations() public {
        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.disableOriginations");
        _config.setAssetOriginationsEnabled(address(_asset), false);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertFalse(
            _config.getAssetConfig(address(_asset)).originationsEnabled,
            "originations disabled"
        );
        _assertGasRecorded(gasUsed);
    }

    // setAssetOriginationsEnabled
    // given an existing disabled Burner Loans market
    //  when governance re-enables originations
    //   then it records dependency validation and the FLOAN update gas cost
    function test_gasSnapshot_config_enableOriginations() public {
        vm.prank(address(this));
        _config.setAssetOriginationsEnabled(address(_asset), false);

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfig.admin.enableOriginations");
        _config.setAssetOriginationsEnabled(address(_asset), true);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertTrue(
            _config.getAssetConfig(address(_asset)).originationsEnabled,
            "originations enabled"
        );
        _assertGasRecorded(gasUsed);
    }

    // queueBatch
    // given the config timelock is authorized and enabled
    //  when the Burner Loans address(this) queues two related configuration actions
    //   then it records validation and storage of the complete batch
    function test_gasSnapshot_timelock_queueBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _configBatch();

        vm.startPrank(address(this));
        vm.startSnapshotGas("BurnerLoansConfigTimelock.queueBatch.twoActions");
        uint64 actionId = _timelock.queueBatch(actions);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(_timelock.getQueuedActionLength(actionId), 2, "queued actions");
        _assertGasRecorded(gasUsed);
    }

    // executeQueuedAction
    // given two configuration actions have passed the timelock delay
    //  when a _keeper executes the batch
    //   then it records the complete validation, FLOAN updates, and queue cleanup gas cost
    function test_gasSnapshot_timelock_executeBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _configBatch();
        vm.prank(address(this));
        uint64 actionId = _timelock.queueBatch(actions);
        vm.warp(block.timestamp + _timelock.timelockDelay());

        vm.startSnapshotGas("BurnerLoansConfigTimelock.executeBatch.twoActions");
        _timelock.executeQueuedAction(actionId);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertEq(_config.getAssetConfig(address(_asset)).maxLtvBps, 9_500, "maximum LTV");
        assertEq(_config.getAssetFeeConfig(address(_asset)).baseFeeBps, 30, "base fee");
        _assertGasRecorded(gasUsed);
    }

    function _fundAndApproveCollateral(address account_, uint128 amount_) internal {
        _asset.mint(account_, amount_ + 100e6);
        vm.prank(account_);
        _asset.approve(address(_core), type(uint256).max);
    }

    function _depositForAlice(uint128 amount_) internal {
        _fundAndApproveCollateral(_borrower, amount_);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), amount_, _borrower);
    }

    function _borrowForAlice(uint128 amount_) internal {
        _depositForAlice(_COLLATERAL);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory preview = _debt.previewBorrow(
            address(_asset),
            amount_,
            _borrower,
            _borrower,
            type(uint256).max,
            address(0)
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), amount_, _borrower, _borrower, preview.fee, address(0));
    }

    function _configureVaultMarket() internal returns (MockERC20 asset, MockERC4626 vault) {
        asset = new MockERC20("Gas Vault Collateral", "gvCOLL", 18);
        vault = new MockERC4626(ERC20(address(asset)), "Gas Vault", "gVAULT");
        _configurePrice(address(asset), 1e18);

        vm.startPrank(address(this));
        _depositManager.addAsset(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        _depositManager.addAssetPeriod(
            IERC20(address(asset)),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
        vm.stopPrank();
    }

    function _supplyOhm(uint128 amount_) internal {
        _ohm.mint(_provider, amount_);
        vm.startPrank(_provider);
        _ohm.approve(address(_inventory), amount_);
        _inventory.supply(amount_);
        vm.stopPrank();
    }

    function _configBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);

        IBurnerLoansRisk.AssetRiskConfigInput memory riskUpdate = _defaultAssetRiskConfigInput();
        riskUpdate.maxLtvBps = 9500;
        actions[0] = ITimelockBatchQueue.BatchAction(
            address(_config),
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(_asset), riskUpdate)
        );
        IBurnerLoansRisk.AssetFeeConfig memory feeUpdate = _defaultAssetFeeConfig();
        feeUpdate.baseFeeBps = 30;
        actions[1] = ITimelockBatchQueue.BatchAction(
            address(_config),
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(_asset), feeUpdate)
        );
    }

    function _assertGasRecorded(uint256 gasUsed_) internal pure {
        assertGt(gasUsed_, 0, "gas snapshot should record gas");
    }

    function _makeUnhealthyBatch(uint256 borrowerCount_) internal {
        for (uint256 i; i < borrowerCount_; ++i) {
            _borrow(_gasBorrower(i), _COLLATERAL, _DEBT);
        }
        _configurePrice(address(_ohm), 20e18);
    }

    function _assertSeizerBatchResult(
        uint256 borrowerCount_,
        uint256 treasuryBefore_
    ) internal view {
        for (uint256 i; i < borrowerCount_; ++i) {
            IBurnerLoansCore.Position memory position = _lens.getPosition(
                address(_asset),
                _gasBorrower(i)
            );
            assertEq(position.debtOhm, 0, "position debt");
            assertEq(position.depositedCollateral, 0, "position collateral");
        }
        assertEq(_core.totalActiveDebtOhm(), 0, "facility principal");
        assertEq(_lens.assetActiveDebtOhm(address(_asset)), 0, "market principal");
        assertEq(
            _floan.getMarketPrincipalDefaulted(_config.marketId(address(_asset))),
            borrowerCount_ * _DEBT,
            "market defaulted principal"
        );
        assertEq(_lens.getActiveBorrowers(address(_asset)).length, 0, "active borrowers");
        assertEq(
            _mintr.mintApproval(address(_inventory)),
            _inventory.globalDebtCapOhm(),
            "mint approval"
        );
        assertEq(
            _asset.balanceOf(_treasury),
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
                address(_core),
                keccak256(
                    "SeizureBatchSettled(address,address,uint256,uint256,uint256,address,uint256,uint256)"
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

    function _configurePrice(address token_, uint256 price_) internal {
        _price.setPrice(token_, price_);
    }

    function _configureDepositManagerAsset(address token_) internal {
        _depositManager.addAsset(IERC20(token_), IERC4626(address(0)), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(token_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
    }

    function _defaultAssetDebtCap() internal pure returns (uint128) {
        return 100_000e9;
    }

    function _defaultAssetRiskConfigInput()
        internal
        pure
        returns (IBurnerLoansRisk.AssetRiskConfigInput memory)
    {
        return IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6);
    }

    function _defaultAssetFeeConfig()
        internal
        pure
        returns (IBurnerLoansRisk.AssetFeeConfig memory)
    {
        return IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900);
    }

    function _activateReplacementConfigurator() internal returns (BurnerLoansConfig replacement) {
        replacement = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
    }

    function _addDirectAssetForTest() internal returns (MockERC20 token) {
        token = new MockERC20("Additional collateral", "ADD", 6);
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
    }

    function _single(address account_) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = account_;
    }

    function _borrow(address account_, uint128 collateral_, uint128 debt_) internal {
        _fundAndApproveCollateral(account_, collateral_);
        vm.startPrank(account_);
        _collateral.depositCollateral(address(_asset), collateral_, account_);
        _debt.borrow(address(_asset), debt_, account_, account_, type(uint256).max, address(0));
        vm.stopPrank();
    }

    function _makeUnhealthy(address account_) internal {
        _borrow(account_, _COLLATERAL, _DEBT);
        _price.setPrice(address(_ohm), 20e18);
    }

    function _createDuplicateUsdsMarketForTest() internal returns (uint32 marketId) {
        uint32 selected = _core.marketId(address(_asset));
        IFLOANv1.Market memory m = _floan.getMarket(selected);
        bytes memory configData = _floan.getMarketConfigData(selected);
        vm.prank(address(_config));
        marketId = _floan.createMarket(
            IFLOANv1.MarketInput(
                m.collateralToken,
                m.debtToken,
                m.manager,
                m.facility,
                m.configId,
                m.principalCap,
                m.termLength,
                m.maxMaturityHorizon,
                m.maxLtvBps,
                m.baseFeeBps
            ),
            configData
        );
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
