// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Permissions} from "src/Kernel.sol";

contract BurnerLoansInventoryConfigTimelockRequestPermissionsTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-PERMS-P01.
    function test_whenPermissionsRead_thenEmpty(
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
        Permissions[] memory permissions = _timelock.requestPermissions();
        assertEq(permissions.length, 0, "No module writes or token approvals");
        assertEq(
            _queueDigest(_pendingId),
            beforeState,
            "Permissions query preserves queue and funds"
        );
    }

    // Scenarios: BLINCT-PERMS-P01.
    function test_givenEachLifecyclePair_whenRead_thenIndependent() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenPermissionsRead_thenEmpty(
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
