// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";

contract BurnerLoansCoreRequireNotReentrantTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-REENTRANCY-L01, BLCORE-REENTRANCY-L02, BLCORE-REENTRANCY-L03, BLCORE-REENTRANCY-L04.
    function test_givenIdleCore_whenGuardQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.prank(caller_);
        _core.requireNotReentrant();
        assertEq(_state(), before, "Idle guard query has no lifecycle gate or effects");
    }

    // Scenarios: BLCORE-REENTRANCY-C01.
    function test_givenBusyCore_whenGuardQueried_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("requireNotReentrant()"),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "View guard observes entered settlement lock"
        );
    }
}
