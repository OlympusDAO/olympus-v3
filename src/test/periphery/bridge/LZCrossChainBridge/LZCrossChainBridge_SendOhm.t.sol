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
        emit ILZCrossChainBridge.Bridged(
            user,
            amount,
            NONCANONICAL_EID,
            fee.nativeFee,
            fee.nativeFee
        );

        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee}(NONCANONICAL_EID, recipient, amount);

        // Deliver packet
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        assertEq(ohm.balanceOf(user), userOhmBefore - amount, "User balance should decrease");
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(ohm2.balanceOf(recipient), amount, "Recipient should receive OHM on destination");
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

    /// @notice When the caller overpays, the Bridged event reports the actual nativeFee
    ///         charged by LayerZero, and the excess is refunded to msg.sender.
    function test_sendOhm_emitsActualNativeFeeOnOverpayment() external {
        uint256 amount = 1000e9;
        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, amount);

        uint256 excess = 3 ether;
        uint256 totalSent = fee.nativeFee + excess;
        uint256 userEthBefore = user.balance;

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.Bridged(user, amount, NONCANONICAL_EID, fee.nativeFee, totalSent);

        vm.prank(user);
        bridge.sendOhm{value: totalSent}(NONCANONICAL_EID, recipient, amount);

        // Deliver packet so the OHM is credited on destination
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        // User should only be debited the actual fee (excess is refunded to msg.sender).
        uint256 userEthAfter = user.balance;
        assertGe(
            userEthAfter,
            userEthBefore - fee.nativeFee - 0.01 ether,
            "User should be charged only the actual fee (plus small refund tolerance)"
        );
        assertLe(
            userEthAfter,
            userEthBefore - fee.nativeFee,
            "User cannot be charged less than the actual fee"
        );

        assertEq(address(bridge).balance, 0, "Bridge should hold no ETH after send");
        assertEq(address(gateway).balance, 0, "Gateway should hold no ETH after send");
    }

    function test_sendOhm_revertsIfNotEnabled() external {
        // Disable bridge
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_EID, recipient, 1000e9);
    }

    function test_sendOhm_revertsIfRecipientZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "to"
            )
        );
        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_EID, address(0), 1000e9);
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

    function test_sendOhm_revertsIfInsufficientNativeFee() external {
        uint256 amount = 1000e9;
        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, amount);

        // Send half the required fee
        vm.expectRevert(
            abi.encodeWithSignature(
                "LZ_InsufficientFee(uint256,uint256,uint256,uint256)",
                fee.nativeFee,
                fee.nativeFee / 2,
                0,
                0
            )
        );
        vm.prank(user);
        bridge.sendOhm{value: fee.nativeFee / 2}(NONCANONICAL_EID, recipient, amount);
    }

    function test_sendOhm_revertsIfInsufficientNativeFeeBalance() external {
        uint256 amount = 1000e9;
        MessagingFee memory fee = bridge.estimateSendFee(NONCANONICAL_EID, recipient, amount);

        // Drain user's ETH so they can't cover the fee
        uint256 userBalance = user.balance;
        vm.prank(user);
        payable(address(0xdead)).transfer(userBalance);
        assertEq(user.balance, 0, "User should have no ETH");

        // Low-level call because vm.prank + {value} reverts at cheatcode level
        // when sender has insufficient balance
        vm.prank(user);
        (bool success, ) = address(bridge).call{value: fee.nativeFee}(
            abi.encodeWithSelector(bridge.sendOhm.selector, NONCANONICAL_EID, recipient, amount)
        );
        assertFalse(success, "Should revert with insufficient ETH balance");
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
        assertEq(ohm2.balanceOf(recipient), amount_, "Recipient should receive exactly amount");
        assertEq(
            user.balance,
            userEthBefore - fee.nativeFee,
            "User should spend exactly the native fee"
        );
    }
}
