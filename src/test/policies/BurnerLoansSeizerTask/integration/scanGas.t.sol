// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";

// Deliberate workload sizes; borrower addresses and casts are bounded by 1000.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)
contract BurnerLoansSeizerTaskScanGasTest is BurnerLoansSeizerTaskProgressTest {
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
        _task.setScanLimits(500, 1);
        _task.setExecutionGasLimit(10_000_000);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(0));
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 0, "Oversized scan cannot commit progress");
        _task.setScanLimits(100, 1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 100, 0);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            100,
            "Smaller page progresses within the same gas budget"
        );
    }

    function _seedBorrowers(uint16 count_) private {
        _task.addAsset(address(_asset));
        _task.setExecutionGasLimit(100_000_000);
        for (uint256 i; i < count_; ++i) _seedDebt(address(uint160(0x10000 + i)), 10e6, 1e9);
    }

    function _measureHealthy(uint16 count_, string memory name_) private {
        _seedBorrowers(count_);
        _task.setScanLimits(count_, 1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 0, 0);
        _task.execute();
        uint256 gasUsed = vm.snapshotGasLastFrame("BurnerLoansSeizerTaskGas", name_);
        emit log_named_uint(name_, gasUsed);
        assertEq(
            _inventory.activePrincipalOhm(),
            uint256(count_) * 1e9,
            "Healthy scan preserves all principal"
        );
        assertEq(_task.assetCursor(address(_asset)), 0, "Healthy scan reaches end and wraps");
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        _task.execute();
    }

    function _measureEligible(uint8 count_, string memory name_) private {
        _seedBorrowers(count_);
        _task.setScanLimits(count_, count_);
        _mature();
        _task.execute();
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
