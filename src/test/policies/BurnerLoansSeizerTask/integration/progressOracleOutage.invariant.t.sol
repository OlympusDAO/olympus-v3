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
}
