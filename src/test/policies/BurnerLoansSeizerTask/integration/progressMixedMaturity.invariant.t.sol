// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressInvariantTest} from "./progress.invariant.t.sol";

/// @dev Eight expired and four unexpired underwater loans, unequal starting offsets,
///      arbitrary gas/limits, independent cursor recovery and pause/re-enable calls.
/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: default.invariant.depth = 64
// Explicit fixture quantities and deterministic identities define the modeled population.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskProgressMixedMaturityInvariantTest is
    BurnerLoansSeizerTaskProgressInvariantTest
{
    address[4] internal _underwaterBorrowers;
    uint48[4] internal _futureMaturities;
    uint256 internal _treasuryBefore;

    function setUp() public override {
        super.setUp();
        for (uint256 i; i < 4; ++i) {
            address borrower = address(uint160(0x20000 + i));
            _underwaterBorrowers[i] = borrower;
            _seedDebt(borrower, 10e6, 1e9);
            _futureMaturities[i] = _lens.getPosition(address(_asset), borrower).maturity;
        }
        _price.setPrice(address(_asset), 1e16);
        // 10e6 collateral at$0.01 =1e17 USD;1e9 debt needs1.25e18 USD.
        // Health=1e17*1e18/1.25e18=8e16, strictly unhealthy before maturity.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 10e6, 1e9),
            8e16,
            "Fixture has genuinely underwater unexpired debt"
        );
        _task.setUnhealthyAssetCursor(address(_asset), 8);
        _treasuryBefore = _asset.balanceOf(_payout.treasury());
    }

    // Scenarios: BLSEIZ-EXECUTE-P31, BLSEIZ-SELF-EXECUTE-P19.
    function afterInvariant() public {
        _assertDrain();
    }

    // Scenarios: BLSEIZ-EXECUTE-P31, BLSEIZ-SELF-EXECUTE-P19.
    function invariant_mixedBacklogRemainsReachable() public {
        // Prove liveness from the generated state without changing the campaign's history.
        uint256 checkpoint = vm.snapshotState();
        _assertDrain();
        assertTrue(
            vm.revertToStateAndDelete(checkpoint),
            "Restore generated state after reachability proof"
        );
    }

    function _assertDrain() private {
        uint256 expired = _task.expiredAssetCursor(address(_asset));
        uint256 unhealthy = _task.unhealthyAssetCursor(address(_asset));
        uint256 now_ = vm.getBlockTimestamp();
        if (!_task.isEnabled()) _task.reEnable();
        _task.setScanLimits(1, 1);
        _task.setExecutionGasLimit(10_000_000);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            expired,
            "Drain preserves randomized expiry progress"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            unhealthy,
            "Drain preserves randomized unhealthy progress"
        );
        uint32 market = _core.marketId(address(_asset));
        uint256 remaining = _floan.getActiveBorrowerCount(market);
        // Between removals a lane traverses at most the finite population. Each removal reduces
        // that population; two-asset rotation and conservative rewinds fit this quadratic bound.
        uint256 budget = 4 * (remaining + 1) * (remaining + 1);
        for (uint256 i; i < budget && _floan.getActiveBorrowerCount(market) != 0; ++i)
            _task.execute();
        assertEq(vm.getBlockTimestamp(), now_, "Drain never matures unexpired positions");
        assertEq(
            _floan.getActiveBorrowerCount(market),
            0,
            "No eligible borrower is stranded after arbitrary history"
        );
        assertEq(_floan.getMarketPrincipalDue(market), 0, "All canonical active principal clears");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory active principal clears");
        // Twelve1e9 debts default; twelve10e6 collateral balances go to Treasury with protocol reward0.
        assertEq(
            _floan.getMarketPrincipalDefaulted(market),
            12e9,
            "Both discovery lanes default all twelve loans"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - _treasuryBefore,
            120e6,
            "All collateral reaches Treasury exactly once"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            0,
            "Custody liabilities fully clear"
        );
        for (uint256 i; i < 4; ++i) {
            assertLt(now_, _futureMaturities[i], "Unhealthy-lane proof cannot rely on expiry");
            assertEq(
                _lens.getPosition(address(_asset), _underwaterBorrowers[i]).debtOhm,
                0,
                "Each initially unexpired underwater borrower is reached"
            );
        }
        invariant_schedulerAndAccountingRemainConsistent();
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
