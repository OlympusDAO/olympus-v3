// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";

/// @dev Queue-time validation for the typed self helper `queueSetTargetFacilitator`:
///      admin-only proposer gate and the non-zero address invariant.
contract LZBridgeAndDelegateConfigTests_QueueSetTargetFacilitator is
    LZBridgeAndDelegateConfigTestBase
{
    function test_queueSetTargetFacilitator_admin() external {
        vm.prank(admin);
        config.queueSetTargetFacilitator(makeAddr("newFacilitator"));
    }

    function testFuzz_queueSetTargetFacilitator_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        _expectAdminRole();
        vm.prank(caller_);
        config.queueSetTargetFacilitator(makeAddr("newFacilitator"));
    }

    function test_queueSetTargetFacilitator_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "facilitator"
            )
        );
        vm.prank(admin);
        config.queueSetTargetFacilitator(address(0));
    }
}
