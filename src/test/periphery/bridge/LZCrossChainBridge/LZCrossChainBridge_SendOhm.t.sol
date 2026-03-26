// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {stdError} from "forge-std/Test.sol";

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

contract LZCrossChainBridgeTests_SendOhm is LZCrossChainBridgeTestBase {
    function test_sendOhm() external {
        uint256 amount = 1000e9;
        uint256 userOhmBefore = ohm.balanceOf(user);
        uint256 userEthBefore = user.balance;
        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, amount);

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.Bridged(user, amount, NONCANONICAL_EID, fee.nativeFee);

        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee}(NONCANONICAL_EID, recipient, amount);

        // Deliver packet
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        assertEq(ohm.balanceOf(user), userOhmBefore - amount, "User balance should decrease");
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should receive OHM on destination");
        assertEq(
            user.balance,
            userEthBefore - fee.nativeFee,
            "User should spend exactly the native fee"
        );
        assertEq(address(bridge).balance, 0, "Bridge should hold no ETH after send");
        assertEq(address(gateway).balance, 0, "Gateway should hold no ETH after send");
        assertEq(
            gateway.bridgedSupply(),
            amount,
            "Bridged supply should increase by amount on canonical"
        );
    }

    function test_sendOhm_revertsIfNotEnabled() external {
        // Disable bridge
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_EID, recipient, 1000e9);
    }

    function test_sendOhm_revertsIfAmountZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InsufficientAmount.selector
            )
        );
        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_EID, recipient, 0);
    }

    function test_sendOhm_revertsIfInsufficientBalance() external {
        // User has 100_000e9, try to send more
        uint256 tooMuch = 200_000e9;
        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, tooMuch);

        // Solmate ERC20 reverts with arithmetic underflow on insufficient balance
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee}(NONCANONICAL_EID, recipient, tooMuch);
    }

    function test_sendOhm_revertsIfInsufficientApproval() external {
        // Revoke approval
        vm.prank(user);
        ohm.approve(address(bridge), 0);

        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, 1000e9);

        // Solmate ERC20 reverts with arithmetic underflow on insufficient allowance
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee}(NONCANONICAL_EID, recipient, 1000e9);
    }

    function testFuzz_sendOhm_variousAmounts(uint256 amount_) external {
        amount_ = bound(amount_, 1, 100_000e9);

        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, amount_);

        uint256 userBalBefore = ohm.balanceOf(user);
        uint256 userEthBefore = user.balance;

        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee}(NONCANONICAL_EID, recipient, amount_);

        // Deliver packet
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        assertEq(ohm.balanceOf(user), userBalBefore - amount_, "User should lose exactly amount");
        assertEq(ohm.balanceOf(recipient), amount_, "Recipient should receive exactly amount");
        assertEq(
            user.balance,
            userEthBefore - fee.nativeFee,
            "User should spend exactly the native fee"
        );
    }
}
