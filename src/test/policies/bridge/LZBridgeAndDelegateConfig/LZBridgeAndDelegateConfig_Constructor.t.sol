// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";

contract LZBridgeAndDelegateConfigTests_Constructor is LZBridgeAndDelegateConfigTestBase {
    function test_constructor_storesTargets() external view {
        assertEq(config.gateway(), address(gateway), "gateway slot");
        assertEq(config.delegate(), address(lzDelegate), "delegate slot");
        assertEq(config.facilitator(), address(facilitator), "facilitator slot");
        assertEq(
            uint256(config.timelockDelay()),
            uint256(INITIAL_TIMELOCK_DELAY),
            "initial timelock delay"
        );
        assertEq(uint256(config.nextActionId()), 1, "nextActionId starts at one");
    }

    function test_constructor_startsDisabled() external {
        // Re-deploy a fresh policy so the test base's `enable("")` does not interfere
        LZBridgeAndDelegateConfig fresh = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
        assertFalse(fresh.isEnabled(), "config should start disabled");
        assertEq(
            uint256(fresh.lastTransitionAt()),
            0,
            "lastTransitionAt should be zero before first enable"
        );
    }

    function test_constructor_emitsTimelockDelaySetAndTargetEvents() external {
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(INITIAL_TIMELOCK_DELAY);
        vm.expectEmit(false, false, false, true);
        emit ILZBridgeAndDelegateConfig.TargetGatewaySet(address(gateway));
        vm.expectEmit(false, false, false, true);
        emit ILZBridgeAndDelegateConfig.TargetDelegateSet(address(lzDelegate));
        vm.expectEmit(false, false, false, true);
        emit ILZBridgeAndDelegateConfig.TargetFacilitatorSet(address(facilitator));
        new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
    }

    function test_constructor_revertsIfKernelZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "kernel"
            )
        );
        new LZBridgeAndDelegateConfig(
            Kernel(address(0)),
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
    }

    function test_constructor_revertsIfGatewayZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "gateway"
            )
        );
        new LZBridgeAndDelegateConfig(
            kernel,
            address(0),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
    }

    function test_constructor_revertsIfDelegateZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "delegate"
            )
        );
        new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(0),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );
    }

    function test_constructor_revertsIfFacilitatorZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeAndDelegateConfig.LZBridgeAndDelegateConfig_InvalidAddress.selector,
                "facilitator"
            )
        );
        new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(0),
            INITIAL_TIMELOCK_DELAY
        );
    }

    function test_constructor_revertsIfDelayBelowMin() external {
        uint48 belowMin = uint48(config.MIN_TIMELOCK_DELAY()) - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                belowMin,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            belowMin
        );
    }

    function test_constructor_revertsIfDelayAboveMax() external {
        uint48 aboveMax = uint48(config.MAX_TIMELOCK_DELAY()) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                aboveMax,
                config.MIN_TIMELOCK_DELAY(),
                config.MAX_TIMELOCK_DELAY()
            )
        );
        new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            aboveMax
        );
    }
}
