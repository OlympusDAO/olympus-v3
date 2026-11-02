// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";

contract BurnerLoansInventoryConfigTimelockVERSIONTest is BurnerLoansInventoryConfigTimelockTest {
    // Scenarios: BLINCT-VERSION-P01.
    function test_whenVersionRead_thenConstant(
        address caller_,
        bool ownActive_,
        bool ownEnabled_,
        bool targetActive_,
        bool targetEnabled_
    ) public givenPendingRecovery {
        _setState(_timelock, ownActive_, ownEnabled_);
        _setState(_inventory, targetActive_, targetEnabled_);
        bytes32 beforeState = _queueDigest(_pendingId);
        vm.mockCallRevert(address(_inventory), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );

        vm.prank(caller_);
        (uint8 major, uint8 minor) = _timelock.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
        assertEq(
            _queueDigest(_pendingId),
            beforeState,
            "Pure version has no queue or funds effects"
        );
    }

    // Scenarios: BLINCT-VERSION-P01.
    function test_givenEachLifecyclePair_whenRead_thenIndependent() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenVersionRead_thenConstant(
                    address(0),
                    active != 0,
                    enabled != 0,
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
            }
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
