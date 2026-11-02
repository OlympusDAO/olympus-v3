// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";

contract BurnerLoansPayoutVERSIONTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CONSTRUCTOR-V01.
    function test_whenVersionRead_thenConstant(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _payout.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
        assertEq(_ledgerDigest(), state, "Version read does not mutate custody");
    }
}
