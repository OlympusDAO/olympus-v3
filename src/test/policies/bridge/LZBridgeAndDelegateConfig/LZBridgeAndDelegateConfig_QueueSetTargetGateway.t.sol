// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";

/// @dev Queue-time validation for the typed self helper `queueSetTargetGateway`: admin-only
///      proposer gate and the non-zero address invariant.
contract LZBridgeAndDelegateConfigTests_QueueSetTargetGateway is LZBridgeAndDelegateConfigTestBase {
    function test_queueSetTargetGateway_admin() external {
        vm.prank(admin);
        config.queueSetTargetGateway(makeAddr("newGateway"));
    }

    function testFuzz_queueSetTargetGateway_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetGateway(makeAddr("newGateway"));
    }

    function test_queueSetTargetGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "gateway"
            )
        );
        vm.prank(admin);
        config.queueSetTargetGateway(address(0));
    }
}
