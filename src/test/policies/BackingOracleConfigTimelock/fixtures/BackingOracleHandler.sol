// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";

/// @dev Exercises local pause, direct writes and one pending intent against an independent model.
contract BackingOracleHandler is Test {
    BackingOracle internal _oracle;
    uint256 public expectedBacking = 100e18;
    bool public expectedEnabled = true;
    uint64 public pendingId;
    uint256 public pendingValue;
    uint256 public queuedBacking;
    BackingOracleConfigTimelock internal _timelock;

    constructor(BackingOracle oracle_, BackingOracleConfigTimelock timelock_) {
        _oracle = oracle_;
        _timelock = timelock_;
    }

    function setBacking(uint256 value_) external {
        if (!expectedEnabled) return;
        // Bounded model keeps initialization-overflow characterization in its deterministic test.
        value_ = bound(value_, 90e18, 110e18);
        uint256 low = (expectedBacking * 9) / 10;
        uint256 high = (expectedBacking * 11) / 10;
        if (value_ < low || value_ > high) return;
        _oracle.setBacking(value_);
        expectedBacking = value_;
    }

    function queue(uint256 value_) external {
        if (!expectedEnabled || pendingId != 0) return;
        value_ = bound(value_, 90e18, 110e18);
        if (value_ < (expectedBacking * 9) / 10 || value_ > (expectedBacking * 11) / 10) return;
        pendingId = _timelock.queueSetBacking(value_);
        pendingValue = value_;
        queuedBacking = expectedBacking;
    }

    function execute() external {
        if (!expectedEnabled || pendingId == 0) return;
        if (queuedBacking != expectedBacking) return;
        vm.warp(_timelock.getQueuedAction(pendingId).executableAt);
        if (pendingValue < (expectedBacking * 9) / 10 || pendingValue > (expectedBacking * 11) / 10)
            return;
        _timelock.executeQueuedAction(pendingId);
        expectedBacking = pendingValue;
        pendingId = 0;
    }

    function cancel() external {
        if (pendingId == 0) return;
        _timelock.cancelQueuedAction(pendingId);
        pendingId = 0;
    }

    function toggleEnabled() external {
        if (expectedEnabled) {
            _oracle.disable("");
        } else {
            _oracle.reEnable();
        }
        expectedEnabled = !expectedEnabled;
    }
}
