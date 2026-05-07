// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IGracePeriod} from "src/interfaces/IGracePeriod.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_Constructor is LZCrossChainBridgeTestBase {
    function test_constructor() external {
        LZCrossChainBridge fresh = new LZCrossChainBridge(
            address(ohm),
            address(this),
            address(gateway),
            reEnablerAddr,
            GRACE_SECONDS
        );

        assertEq(fresh.OHM(), address(ohm), "OHM should be set");
        assertEq(fresh.owner(), address(this), "Owner should be the deployer");
        assertEq(fresh.gateway(), address(gateway), "Gateway should be set from constructor");
        assertEq(fresh.reEnabler(), reEnablerAddr, "ReEnabler should be set from constructor");
        assertEq(uint256(fresh.gracePeriod()), uint256(GRACE_SECONDS), "gracePeriod should be set");
        assertFalse(fresh.isEnabled(), "Bridge should start disabled");
        assertEq(
            uint256(fresh.lastTransitionAt()),
            0,
            "lastTransitionAt should be zero before first enable"
        );
    }

    function test_constructor_acceptsZeroReEnabler() external {
        // Zero address is permitted at construction time; the owner can set the
        // re-enabler later via `setReEnabler`. While unset, `reEnable()` reverts.
        LZCrossChainBridge fresh = new LZCrossChainBridge(
            address(ohm),
            address(this),
            address(gateway),
            address(0),
            GRACE_SECONDS
        );

        assertEq(fresh.reEnabler(), address(0), "ReEnabler should accept zero");
    }

    function test_constructor_revertsIfOhmZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "ohm"
            )
        );
        new LZCrossChainBridge(
            address(0),
            address(this),
            address(gateway),
            reEnablerAddr,
            GRACE_SECONDS
        );
    }

    function test_constructor_revertsIfOwnerZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "owner"
            )
        );
        new LZCrossChainBridge(
            address(ohm),
            address(0),
            address(gateway),
            reEnablerAddr,
            GRACE_SECONDS
        );
    }

    function test_constructor_revertsIfGatewayZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        new LZCrossChainBridge(
            address(ohm),
            address(this),
            address(0),
            reEnablerAddr,
            GRACE_SECONDS
        );
    }

    function test_constructor_revertsIfGraceZero() external {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new LZCrossChainBridge(address(ohm), address(this), address(gateway), reEnablerAddr, 0);
    }
}
