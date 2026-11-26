// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDiscoveryWithdrawal} from "../fixtures/IDiscoveryDependencies.sol";

// Libraries
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";

// Deliberate workload sizes; borrower addresses and casts are bounded by 1000.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)
contract BurnerLoansSeizerTaskScanGasTest is BurnerLoansSeizerTaskProgressTest {
    error LateRedemptionFailed();

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsOne_thenMeasureGas() public {
        _measureHealthy(1, "healthy-1");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsTwentyFive_thenMeasureGas() public {
        _measureHealthy(25, "healthy-25");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsFifty_thenMeasureGas() public {
        _measureHealthy(50, "healthy-50");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsOneHundred_thenMeasureGas() public {
        _measureHealthy(100, "healthy-100");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsFiveHundred_thenMeasureGas() public {
        _measureHealthy(500, "healthy-500");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G01.
    function test_whenHealthyScanIsOneThousand_thenMeasureGas() public {
        _measureHealthy(1000, "healthy-1000");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsOne_thenMeasureGas() public {
        _measureEligible(1, "eligible-1");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsTwentyFive_thenMeasureGas() public {
        _measureEligible(25, "eligible-25");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsFifty_thenMeasureGas() public {
        _measureEligible(50, "eligible-50");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsFiftyOne_thenMeasureGas() public {
        _measureEligible(51, "eligible-51");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsOneHundred_thenMeasureGas() public {
        _measureEligible(100, "eligible-100");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G02.
    function test_whenEligibleBatchIsMaxUint8_thenMeasureGas() public {
        _measureEligible(type(uint8).max, "eligible-255");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G03.
    function test_givenTenMillionGas_whenScanReduced_thenProgressResumes() public {
        _seedBorrowers(500);
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(500, 1);
        vm.prank(_fixtureAdmin);
        _task.setExecutionGasLimit(10_000_000);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(0));
        _executeAsHeart(_task);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Oversized scan cannot commit progress"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Oversized scan cannot commit progress"
        );
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(100, 1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(
            address(_asset),
            IBurnerLoansLens.Selection.Unhealthy,
            0,
            100,
            0
        );
        _executeAsHeart(_task);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            100,
            "Smaller page progresses within the same gas budget"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            100,
            "Smaller page progresses within the same gas budget"
        );
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G04.
    function test_givenSeparateCursors_whenHealthyPagesDiffer_thenMeasureGas() public {
        _seedBorrowers(200);
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(100, 1);
        vm.prank(_fixtureAdmin);
        _task.setUnhealthyAssetCursor(address(_asset), 100);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(
            address(_asset),
            IBurnerLoansLens.Selection.Unhealthy,
            100,
            0,
            0
        );
        _executeAsHeart(_task);
        uint256 gasUsed = vm.snapshotGasLastFrame(
            "BurnerLoansSeizerTaskGas",
            "healthy-100-disjoint"
        );
        emit log_named_uint("healthy-100-disjoint", gasUsed);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            100,
            "Expiry advances through the first page"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Unhealthy advances through a different page and wraps"
        );
        assertEq(_inventory.activePrincipalOhm(), 200e9, "Both healthy pages preserve principal");
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G05.
    function test_givenExpiredBatch_givenLateRejection_whenExpiryFirst_thenMeasureGas() public {
        _seedBorrowers(100);
        _mature();
        _measureLateRejection("late-expired-expiry-first-heart", 26, 25);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G05.
    function test_givenExpiredBatch_givenLateRejection_whenUnhealthyFirst_thenMeasureGas() public {
        _seedBorrowers(100);
        _executeAsHeart(_task); // Healthy book consumes the first expiry-first visit without settlement.
        _mature();
        _measureLateRejection("late-expired-unhealthy-first-heart", 26, 0);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G05.
    function test_givenUnhealthyBatch_givenLateRejection_whenExpiryFirst_thenMeasureGas() public {
        _seedBorrowers(100);
        _price.setPrice(address(_asset), 1e16);
        _measureLateRejection("late-unhealthy-expiry-first-heart", 0, 26);
    }

    // Scenarios: BLSEIZ-SCAN-LIMITS-G05.
    function test_givenUnhealthyBatch_givenLateRejection_whenUnhealthyFirst_thenMeasureGas()
        public
    {
        _seedBorrowers(100);
        _executeAsHeart(_task);
        _price.setPrice(address(_asset), 1e16);
        _measureLateRejection("late-unhealthy-unhealthy-first-heart", 25, 26);
    }

    function _measureLateRejection(
        string memory name_,
        uint256 expectedExpired_,
        uint256 expectedUnhealthy_
    ) private {
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(100, 25);
        vm.prank(_fixtureAdmin);
        _task.setExecutionGasLimit(10_000_000);
        _setBothBorrowerCursors(address(_asset), 25);
        // Core defaults all 25 selected loans before attempting the aggregate withdrawal.
        // Reject the 25 * 10e6 withdrawal after real defaults; the full batch must roll back.
        bytes memory aggregateWithdrawal = abi.encodeCall(
            IDiscoveryWithdrawal.withdraw,
            (
                IDepositManager.WithdrawParams(
                    IERC20(address(_asset)),
                    1,
                    address(_core),
                    address(_payout),
                    250e6,
                    false
                ),
                false
            )
        );
        vm.mockCallRevert(
            address(_depositManager),
            aggregateWithdrawal,
            abi.encodeWithSelector(LateRedemptionFailed.selector)
        );
        uint32 market = _core.marketId(address(_asset));
        (, uint64 firstId) = _floan.getPositionIdForMarketAndBorrowerAt(
            market,
            address(0x10019),
            0
        );
        (, uint64 lastId) = _floan.getPositionIdForMarketAndBorrowerAt(market, address(0x10031), 0);
        vm.expectCall(
            address(_floan),
            abi.encodeCall(_floan.defaultPosition, (firstId)),
            uint64(1)
        );
        vm.expectCall(address(_floan), abi.encodeCall(_floan.defaultPosition, (lastId)), uint64(1));
        vm.expectCall(address(_depositManager), aggregateWithdrawal, uint64(1));

        MockPeriodicTaskManager manager = new MockPeriodicTaskManager(_kernel);
        _executeFixtureKernelAction(Actions.ActivatePolicy, address(manager));
        _grantFixtureRole(HEART_ROLE, address(manager));
        MockPeriodicTask later = new MockPeriodicTask();
        vm.prank(_fixtureAdmin);
        manager.addPeriodicTask(address(_task));
        vm.prank(_fixtureAdmin);
        manager.addPeriodicTask(address(later));
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), LateRedemptionFailed.selector);
        manager.executeAllTasks{gas: 12_000_000}();
        uint256 gasUsed = vm.snapshotGasLastFrame("BurnerLoansSeizerTaskGas", name_);
        emit log_named_uint(name_, gasUsed);
        assertEq(later.count(), 1, "Late batch failure leaves later Heart tasks runnable");
        assertEq(
            _lens.getPosition(address(_asset), address(0x10019)).debtOhm,
            1e9,
            "Rejected batch retains the first loan"
        );
        assertEq(
            _lens.getPosition(address(_asset), address(0x10031)).debtOhm,
            1e9,
            "Batch rollback retains tail"
        );
        assertEq(_floan.getActiveBorrowerCount(market), 100, "No hidden singleton attempt commits");
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            expectedExpired_,
            "Expiry cursor includes any successful empty-page scan before rejection"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            expectedUnhealthy_,
            "Unhealthy cursor includes any successful empty-page scan before rejection"
        );
        assertEq(_floan.getMarketPrincipalDue(market), 100e9, "Failed batch principal rolls back");
        assertEq(_floan.getMarketPrincipalDefaulted(market), 0, "All defaults roll back");
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Inventory agrees with canonical principal"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            1000e6,
            "Failed batch preserves all collateral"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            0,
            "Rejected batch transfers no proceeds"
        );
    }

    function _seedBorrowers(uint16 count_) private {
        vm.prank(_fixtureAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_fixtureAdmin);
        _task.setExecutionGasLimit(100_000_000);
        for (uint256 i; i < count_; ++i) _seedDebt(address(uint160(0x10000 + i)), 10e6, 1e9);
    }

    function _measureHealthy(uint16 count_, string memory name_) private {
        _seedBorrowers(count_);
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(count_, 1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(
            address(_asset),
            IBurnerLoansLens.Selection.Unhealthy,
            0,
            0,
            0
        );
        _executeAsHeart(_task);
        uint256 gasUsed = vm.snapshotGasLastFrame("BurnerLoansSeizerTaskGas", name_);
        emit log_named_uint(name_, gasUsed);
        assertEq(
            _inventory.activePrincipalOhm(),
            uint256(count_) * 1e9,
            "Healthy scan preserves all principal"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Healthy scan reaches end and wraps"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Healthy scan reaches end and wraps"
        );
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        _executeAsHeart(_task);
    }

    function _measureEligible(uint8 count_, string memory name_) private {
        _seedBorrowers(count_);
        vm.prank(_fixtureAdmin);
        _task.setScanLimits(count_, count_);
        _mature();
        _executeAsHeart(_task);
        uint256 gasUsed = vm.snapshotGasLastFrame("BurnerLoansSeizerTaskGas", name_);
        emit log_named_uint(name_, gasUsed);
        assertEq(_inventory.activePrincipalOhm(), 0, "Measured call settles the complete batch");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "No eligible borrower skipped"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(_asset))),
            0,
            "All collateral settled"
        );
        assertEq(_asset.balanceOf(address(_task)), 0, "No reward retained by Task");
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
