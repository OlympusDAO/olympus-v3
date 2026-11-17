// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IDiscoveryPrice} from "../fixtures/IDiscoveryDependencies.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressInvariantTest} from "./progress.invariant.t.sol";

/// @dev Reuses arbitrary gas/check/result settings, cursor recovery and pause/re-enable sequences.
///      Eight expired and two unexpired positions share a market during a persistent PRICE outage.
/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: default.invariant.depth = 64
contract BurnerLoansSeizerTaskProgressOracleOutageInvariantTest is
    BurnerLoansSeizerTaskProgressInvariantTest
{
    error OracleUnavailable();

    function setUp() public override {
        super.setUp();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        vm.mockCallRevert(
            address(_price),
            abi.encodeWithSelector(IDiscoveryPrice.getPrice.selector),
            abi.encodeWithSelector(OracleUnavailable.selector)
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P13, BLSEIZ-EXECUTE-D01.
    function invariant_unexpiredDebtRemainsUnclassified() public view {
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            1e9,
            "Unexpired Carol is never settled without prices"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            1e9,
            "Unexpired Dave is never settled without prices"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P13, BLSEIZ-EXECUTE-D01.
    function afterInvariant() public {
        uint256 expired = _task.expiredAssetCursor(address(_asset));
        uint256 unhealthy = _task.unhealthyAssetCursor(address(_asset));
        uint256 now_ = vm.getBlockTimestamp();
        if (!_task.isEnabled()) _task.reEnable();
        _task.setScanLimits(1, 1);
        _task.setExecutionGasLimit(10_000_000);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            expired,
            "Outage drain preserves generated expiry progress"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            unhealthy,
            "Outage drain preserves generated unhealthy progress"
        );

        uint32 market = _core.marketId(address(_asset));
        uint256 remaining = _floan.getActiveBorrowerCount(market);
        // Each lane gets a turn every other visit to A; B also consumes alternating visits.
        // A finite page traversal followed by each removal fits this quadratic bound.
        uint256 budget = 4 * (remaining + 1) * (remaining + 1);
        for (uint256 i; i < budget && _floan.getActiveBorrowerCount(market) > 2; ++i)
            _task.execute();

        assertEq(vm.getBlockTimestamp(), now_, "Outage drain cannot mature unexpired debt");
        assertEq(_floan.getActiveBorrowerCount(market), 2, "Only the two unexpired loans remain");
        address first = _floan.getActiveBorrowerAt(market, 0);
        address second = _floan.getActiveBorrowerAt(market, 1);
        assertTrue(
            (first == _CAROL && second == _DAVE) || (first == _DAVE && second == _CAROL),
            "Canonical active borrowers are precisely Carol and Dave"
        );
        // Ten loans of 1e9 OHM principal: eight expired defaults and two unexpired loans.
        assertEq(_floan.getMarketPrincipalDue(market), 2e9, "Unexpired principal remains due");
        assertEq(_floan.getMarketPrincipalDefaulted(market), 8e9, "Every expired loan defaults");
        assertEq(_inventory.activePrincipalOhm(), 2e9, "Inventory retains only unexpired debt");
        invariant_unexpiredDebtRemainsUnclassified();
        invariant_schedulerAndAccountingRemainConsistent();
        vm.expectRevert(OracleUnavailable.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(_task), address(_asset), 0, 1, 1);
    }
}
