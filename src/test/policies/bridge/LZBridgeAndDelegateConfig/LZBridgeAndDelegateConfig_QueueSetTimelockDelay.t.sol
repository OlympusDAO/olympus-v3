// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @dev Queue-time validation for the typed self helper `queueSetTimelockDelay`: admin-only
///      proposer gate and the `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]` bounds.
contract LZBridgeAndDelegateConfigTests_QueueSetTimelockDelay is LZBridgeAndDelegateConfigTestBase {
    function test_queueSetTimelockDelay_admin() external {
        vm.prank(admin);
        config.queueSetTimelockDelay(INITIAL_TIMELOCK_DELAY);
    }

    function testFuzz_queueSetTimelockDelay_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTimelockDelay(INITIAL_TIMELOCK_DELAY);
    }

    function test_queueSetTimelockDelay_revertsIfDelayBelowMin() external {
        uint48 belowMin = uint48(config.MIN_TIMELOCK_DELAY()) - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                belowMin,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        config.queueSetTimelockDelay(belowMin);
    }

    function test_queueSetTimelockDelay_revertsIfDelayAboveMax() external {
        uint48 aboveMax = uint48(config.MAX_TIMELOCK_DELAY()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                aboveMax,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        vm.prank(admin);
        config.queueSetTimelockDelay(aboveMax);
    }
}
