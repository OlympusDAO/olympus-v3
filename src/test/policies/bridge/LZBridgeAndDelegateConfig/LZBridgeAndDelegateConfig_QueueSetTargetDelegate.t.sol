// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";

/// @dev Queue-time validation for the typed self helper `queueSetTargetDelegate`: admin-only
///      proposer gate and the non-zero address invariant.
contract LZBridgeAndDelegateConfigTests_QueueSetTargetDelegate is
    LZBridgeAndDelegateConfigTestBase
{
    function test_queueSetTargetDelegate_admin() external {
        vm.prank(admin);
        config.queueSetTargetDelegate(makeAddr("newDelegate"));
    }

    function testFuzz_queueSetTargetDelegate_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetDelegate(makeAddr("newDelegate"));
    }

    function test_queueSetTargetDelegate_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "delegate"
            )
        );
        vm.prank(admin);
        config.queueSetTargetDelegate(address(0));
    }
}
