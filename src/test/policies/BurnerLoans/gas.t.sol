// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";

import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansEndToEndGasTest is BurnerLoansSeizureTestBase {
    uint128 internal constant _COLLATERAL = 2_000e18;
    uint128 internal constant _DEBT = 100e9;

    function setUp() public override {
        super.setUp();
        _setDefaultConfigurator();
        _enableConfigTimelock();
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

        assertEq(
            uint8(burnerLoans.getPosition(address(usds), alice).status),
            uint8(IBurnerLoans.PositionStatus.Seized),
            "position status"
        );
        _assertGasRecorded(gasUsed);
    }

    // harvestYield
    // given a vault-backed market has earned yield above borrower liabilities
    //  when a keeper harvests the surplus
    //   then it records the end-to-end custody withdrawal gas cost
    function test_gasSnapshot_harvestYield() public {
        (MockERC20 asset, MockERC4626 vault) = _configureVaultMarket();
        uint128 collateral = 100e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        vm.stopPrank();
        asset.mint(address(vault), 10e18);

        vm.startSnapshotGas("BurnerLoans.harvestYield");
        uint256 claimed = burnerLoans.harvestYield(address(asset));
        uint256 gasUsed = vm.stopSnapshotGas();

        assertGt(claimed, 0, "claimed yield");
        _assertGasRecorded(gasUsed);
    }

    // setGlobalDebtCap
    // given Burner Loans is enabled
    //  when governance updates the global active-debt cap
    //   then it records the cap and MINTR reconciliation gas cost
    function test_gasSnapshot_admin_setGlobalDebtCap() public {
        uint128 newCap = 2_000_000e9;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoans.admin.setGlobalDebtCap");
        burnerLoans.setGlobalDebtCap(newCap);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(burnerLoans.globalDebtCapOhm(), newCap, "global debt cap");
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
    // given the caller is the Burner Loans admin
    //  when it reconciles MINTR approval with active debt
    //   then it records the operational admin gas cost
    function test_gasSnapshot_admin_syncMintApproval() public {
        vm.startPrank(burnerLoansAdmin);
        vm.startSnapshotGas("BurnerLoans.admin.syncMintApproval");
        uint256 approval = burnerLoans.syncMintApproval();
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(approval, burnerLoans.globalDebtCapOhm(), "mint approval");
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
        config.collateralFactorBps = 9_500;

        vm.startPrank(admin);
        vm.startSnapshotGas("BurnerLoansConfig.admin.setAssetRiskConfig");
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "collateral factor"
        );
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

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "collateral factor"
        );
        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "base fee");
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

    function _configBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate;
        riskUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection;
        riskSelection.collateralFactorBps = true;
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

    function _assertGasRecorded(uint256 gasUsed_) internal pure {
        assertGt(gasUsed_, 0, "gas snapshot should record gas");
    }
}
