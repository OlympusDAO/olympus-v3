// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Permissions} from "src/Kernel.sol";

contract BurnerLoansPayoutRequestPermissionsTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-PERMISSIONS-P01, BLCU-PERMISSIONS-P02.
    function test_whenPermissionsRead_thenEmpty(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("payout()"), hex"deadbeef");
        vm.prank(caller_);
        Permissions[] memory permissions = _payout.requestPermissions();
        assertEq(permissions.length, 0, "No module writes requested");
        assertEq(_ledgerDigest(), state, "Read preserves custody and routing");
    }
}
