// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

/// @dev Full canonical <-> non-canonical round trip.
contract LZBridgeGatewayTests_EndToEndWithMock is LZBridgeGatewayTestBase {
    function test_roundTrip_canonicalToNonCanonicalAndBack() external {
        uint256 sendAmount = 10_000e9;

        // 1. Bridge canonical -> non-canonical
        _sendCanonicalToNonCanonical(recipient, sendAmount);

        assertEq(gateway.bridgedSupply(), sendAmount, "Canonical supply should increase");
        assertEq(
            mintr.mintApproval(address(gateway)),
            sendAmount,
            "Canonical mint approval should equal bridged supply after outflow"
        );
        assertEq(
            ohm.balanceOf(recipient),
            sendAmount,
            "Recipient should receive OHM on non-canonical"
        );

        // 2. Bridge non-canonical -> canonical (bridge back half)
        uint256 returnAmount = 5_000e9;

        // Recipient needs to give OHM to facilitator first
        vm.prank(recipient);
        ohm.transfer(facilitator, returnAmount);

        _sendNonCanonicalToCanonical(recipient, returnAmount);

        assertEq(
            gateway.bridgedSupply(),
            sendAmount - returnAmount,
            "Canonical supply should decrease"
        );
        assertEq(
            mintr.mintApproval(address(gateway)),
            sendAmount - returnAmount,
            "Canonical mint approval should decrease by return amount"
        );
        assertEq(ohm.balanceOf(recipient), sendAmount, "Recipient should have original + returned");
    }

    function test_canonicalToNonCanonical() external {
        uint256 amount = 5_000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        _sendCanonicalToNonCanonical(recipient, amount);

        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator should have less OHM"
        );
        assertEq(
            ohm.balanceOf(recipient),
            amount,
            "Recipient should receive minted OHM on non-canonical"
        );
        assertEq(gateway.bridgedSupply(), amount, "Canonical bridgedSupply should increase");
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical bridgedSupply should remain zero");
    }

    function test_nonCanonicalToCanonical() external {
        // 1. Preparation: bridge OHM to non-canonical so there's bridgedSupply
        uint256 amount = 5_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply after outbound");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should have OHM on non-canonical");

        // 2. Test: send OHM back from non-canonical to canonical
        vm.prank(recipient);
        ohm.transfer(facilitator, amount);

        _sendNonCanonicalToCanonical(user, amount);

        // Verify
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM on canonical");
        assertEq(gateway.bridgedSupply(), 0, "Canonical bridgedSupply should return to 0");
    }
}
