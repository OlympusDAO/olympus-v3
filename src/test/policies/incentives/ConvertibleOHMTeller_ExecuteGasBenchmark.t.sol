// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {ConvertibleOHMToken} from "src/policies/incentives/convertible/ConvertibleOHMToken.sol";
import {ConvertibleOHMTellerTestBase} from "src/test/policies/incentives/ConvertibleOHMTeller.t.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title Gas benchmarks for ConvertibleOHMTeller.execute()
/// @notice Measures the gas cost of execute() when sweeping HEART_SWEEP_LIMIT
///         expired tokens. The benchmark is informational.
contract ConvertibleOHMTellerExecuteGasBenchmark is ConvertibleOHMTellerTestBase {
    /// @dev One UTC day, used to space out token timestamps.
    uint48 internal constant _ONE_DAY = uint48(1 days);

    /// @dev Tight upper bound on gas consumed by execute(). Tune if HEART_SWEEP_LIMIT
    ///      changes or sweep-loop logic changes.
    uint256 internal constant _GAS_UPPER_BOUND = 500_000;

    function test_execute_gas_sweep_singleCreator() external {
        uint256 limit = teller.HEART_SWEEP_LIMIT();
        assertGt(limit, 0, "HEART_SWEEP_LIMIT must be > 0 for benchmark");

        for (uint256 i; i < limit; ++i) {
            uint48 eligible = eligibleTimestamp + uint48(i) * _ONE_DAY;
            uint48 expiry = expiryTimestamp + uint48(i) * _ONE_DAY;
            ConvertibleOHMToken tok = _deployConvertibleTokenAt(eligible, expiry);
            vm.prank(incentiveDistributor);
            teller.create(address(tok), user0, 1e9);
        }

        uint48 lastExpiry = expiryTimestamp + uint48(limit - 1) * _ONE_DAY;
        vm.warp(uint256(lastExpiry) + 1);

        vm.prank(heart);
        teller.execute();
        Vm.Gas memory g = vm.lastCallGas();

        emit log_named_uint("execute() gas total used (single creator)", g.gasTotalUsed);
        emit log_named_int("execute() gas refunded (single creator)", g.gasRefunded);
        assertEq(teller.activeTokensLength(), 0, "all tokens should be swept");
        assertLt(g.gasTotalUsed, _GAS_UPPER_BOUND, "execute() gas should remain within bound");
    }

    function test_execute_gas_sweep_distinctCreators() external {
        uint256 limit = teller.HEART_SWEEP_LIMIT();
        assertGt(limit, 0, "HEART_SWEEP_LIMIT must be > 0 for benchmark");

        for (uint256 i; i < limit; ++i) {
            address distrib = makeAddr(string.concat("benchmarkDistrib", vm.toString(i)));
            roles.saveRole(teller.ROLE_CONVERTIBLE_DISTRIBUTOR(), distrib);
            teller.setCreatorMintCap(distrib, _UNLIMITED_CREATOR_CAP);

            uint48 eligible = eligibleTimestamp + uint48(i) * _ONE_DAY;
            uint48 expiry = expiryTimestamp + uint48(i) * _ONE_DAY;
            ConvertibleOHMToken tok = _deployConvertibleTokenForDistributor(
                distrib,
                eligible,
                expiry,
                STRIKE_PRICE
            );
            vm.prank(distrib);
            teller.create(address(tok), user0, 1e9);
        }

        uint48 lastExpiry = expiryTimestamp + uint48(limit - 1) * _ONE_DAY;
        vm.warp(uint256(lastExpiry) + 1);

        vm.prank(heart);
        teller.execute();
        Vm.Gas memory g = vm.lastCallGas();

        emit log_named_uint("execute() gas total used (distinct creators)", g.gasTotalUsed);
        emit log_named_int("execute() gas refunded (distinct creators)", g.gasRefunded);
        assertEq(teller.activeTokensLength(), 0, "all tokens should be swept");
        assertLt(g.gasTotalUsed, _GAS_UPPER_BOUND, "execute() gas should remain within bound");
    }

    function test_execute_gas_skipNotExpired() external {
        uint256 limit = teller.HEART_SWEEP_LIMIT();

        for (uint256 i; i < limit; ++i) {
            uint48 eligible = eligibleTimestamp + uint48(i) * _ONE_DAY;
            uint48 expiry = expiryTimestamp + uint48(i) * _ONE_DAY;
            ConvertibleOHMToken tok = _deployConvertibleTokenAt(eligible, expiry);
            vm.prank(incentiveDistributor);
            teller.create(address(tok), user0, 1e9);
        }

        // Stay strictly before the earliest expiry so the backward scan visits every
        // tail entry and exits without sweeping or touching MINTR.
        vm.warp(uint256(expiryTimestamp) - 1);
        vm.prank(heart);
        teller.execute();
        Vm.Gas memory g = vm.lastCallGas();

        emit log_named_uint("execute() gas total used (no sweep, budget consumed)", g.gasTotalUsed);
        assertEq(teller.activeTokensLength(), limit, "no token should be swept");
        assertLt(g.gasTotalUsed, _GAS_UPPER_BOUND, "execute() gas should remain within bound");
    }
}
