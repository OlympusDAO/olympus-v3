// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {BurnerLoansPayoutConfigTimelock} from "src/policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol";

contract BurnerLoansPayoutConfigTimelockVERSIONTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-VERSION-V01.
    function test_whenVersionRead_thenConstant(
        address caller_,
        bool ownActive_,
        bool ownEnabled_,
        bool targetActive_,
        bool targetEnabled_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, ownActive_, ownEnabled_);
        _setState(_payout, targetActive_, targetEnabled_);
        bytes32 beforeState = _queueDigest(_pendingId);
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");

        vm.prank(caller_);
        (uint8 major, uint8 minor) = _payoutTimelock.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
        assertEq(
            _queueDigest(_pendingId),
            beforeState,
            "Pure version has no queue or funds effects"
        );
    }

    // Scenarios: BLCUCT-VERSION-V01.
    function test_givenEachLifecyclePair_whenRead_thenIndependent() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 a; a < 2; ++a)
            for (uint256 e; e < 2; ++e)
                for (uint256 ta; ta < 2; ++ta)
                    for (uint256 te; te < 2; ++te) {
                        test_whenVersionRead_thenConstant(
                            address(0),
                            a != 0,
                            e != 0,
                            ta != 0,
                            te != 0
                        );
                        _restore(checkpoint);
                    }
    }

    // Scenarios: BLCUCT-VERSION-V01.
    function test_givenFreshPolicy_whenRead_thenIndependent(address caller_) public {
        BurnerLoansPayoutConfigTimelock fresh = new BurnerLoansPayoutConfigTimelock(
            _kernel,
            _payout
        );
        vm.prank(caller_);
        (uint8 major, uint8 minor) = fresh.VERSION();
        assertEq(major, 1, "Fresh major");
        assertEq(minor, 0, "Fresh minor");
        assertFalse(fresh.isEnabled(), "Query creates no lifecycle history");
        assertEq(fresh.lastTransitionAt(), 0, "No transition");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
