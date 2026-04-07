// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Vm} from "forge-std/Test.sol";

// Interfaces
import {MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {Errors} from "@lz-evm-protocol-v2-3.0.162/libs/Errors.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Contracts
import {LZBridgeGatewayForkTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayForkTestBase.sol";

/// @notice Fork-based tests for LZBridgeGateway cross-chain bridge (LZ V2).
/// @dev Each test exercises the real sendOhm() -> burnAndSend() -> EndpointV2.send() path,
///      verifying encoding, fee estimation, burn, bridgedSupply tracking, and packet delivery.
contract LZBridgeGatewayForkTests is LZBridgeGatewayForkTestBase {
    /// @notice Full e2e: sendOhm on ETH fork via real EndpointV2, parse PacketSent, deliver on ARB fork.
    function test_ethToArb_sendAndRelay() external {
        uint256 amount = 1000e9;

        // === SOURCE: ETH fork (already selected by setUp) ===

        // Estimate fee
        MessagingFee memory fee = ethBridge.estimateSendFee(LZConfigLib.ARB_EID, recipient, amount);
        assertGt(fee.nativeFee, 0, "Fee should be non-zero");

        // Send OHM cross-chain
        uint256 senderBalBefore = ethOhm.balanceOf(sender);

        vm.startPrank(sender);
        ethOhm.approve(address(ethBridge), amount);
        vm.recordLogs();
        ethBridge.sendOhm{value: fee.nativeFee}(LZConfigLib.ARB_EID, recipient, amount);
        vm.stopPrank();

        // Verify source side: OHM burned, bridgedSupply increased
        assertEq(ethOhm.balanceOf(sender), senderBalBefore - amount, "Sender OHM should decrease");
        assertEq(ethGateway.bridgedSupply(), amount, "BridgedSupply should increase");

        // Parse the PacketSent event from the real V2 endpoint
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory encodedPacket = _findPacketSent(logs);
        (Origin memory origin, bytes32 guid, bytes memory message) = _parsePacket(encodedPacket);

        // Verify parsed packet matches expected values
        assertEq(origin.srcEid, LZConfigLib.ETH_EID, "Packet srcEid should be ETH");
        assertEq(
            origin.sender,
            LZConfigLib.addressToBytes32(address(ethGateway)),
            "Packet sender should be ethGateway"
        );
        assertGt(origin.nonce, 0, "Packet nonce should be non-zero");
        assertTrue(guid != bytes32(0), "GUID should be non-zero");

        // Decode the payload to verify encoding correctness
        (uint8 msgType, bytes memory data) = abi.decode(message, (uint8, bytes));
        assertEq(msgType, 1, "Message type should be MSG_BRIDGE_OHM");
        (address decodedTo, uint256 decodedAmount) = abi.decode(data, (address, uint256));
        assertEq(decodedTo, recipient, "Decoded recipient should match");
        assertEq(decodedAmount, amount, "Decoded amount should match");

        // === DESTINATION: ARB fork ===
        vm.selectFork(arbForkId);

        vm.prank(arbGateway.LZ_ENDPOINT());
        arbGateway.lzReceive(origin, guid, message, address(0), bytes(""));

        // Verify destination: recipient received OHM
        assertEq(arbOhm.balanceOf(recipient), amount, "Recipient should receive OHM on Arb");
    }

    /// @notice Verifies that fee estimation is consistent with actual send cost.
    function test_feeEstimationMatchesSend() external {
        uint256 amount = 500e9;

        // Estimate fee
        MessagingFee memory fee = ethBridge.estimateSendFee(LZConfigLib.ARB_EID, recipient, amount);

        // Send with exact fee should succeed
        vm.startPrank(sender);
        ethOhm.approve(address(ethBridge), amount);
        ethBridge.sendOhm{value: fee.nativeFee}(LZConfigLib.ARB_EID, recipient, amount);
        vm.stopPrank();

        // Send with less than estimated fee should revert with exact error
        uint256 amount2 = 500e9;
        MessagingFee memory fee2 = ethBridge.estimateSendFee(
            LZConfigLib.ARB_EID,
            recipient,
            amount2
        );
        vm.startPrank(sender);
        ethOhm.approve(address(ethBridge), amount2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LZ_InsufficientFee.selector,
                fee2.nativeFee,
                uint256(1),
                uint256(0),
                uint256(0)
            )
        );
        ethBridge.sendOhm{value: 1}(LZConfigLib.ARB_EID, recipient, amount2);
        vm.stopPrank();
    }

    /// @notice Fork-based round-trip test for LZBridgeGateway cross-chain bridge (LZ V2).
    /// @dev Exercises the real sendOhm() -> burnAndSend() -> EndpointV2.send() path in both
    ///      directions, proving source-side burn and bridgedSupply tracking end-to-end.
    function test_roundTrip() external {
        uint256 amount = 500e9;

        // Step 1: Eth->Arb via real sendOhm path
        vm.selectFork(ethForkId);
        uint256 ethSenderBalBefore = ethOhm.balanceOf(sender);
        uint256 ethTotalSupplyBeforeOutbound = ethOhm.totalSupply();
        vm.selectFork(arbForkId);
        uint256 arbTotalSupplyBeforeInbound = arbOhm.totalSupply();
        vm.selectFork(ethForkId);

        _sendAndDeliver(
            ethForkId,
            arbForkId,
            ethBridge,
            arbGateway,
            ethOhm,
            LZConfigLib.ARB_EID,
            sender,
            recipient,
            amount
        );

        // Verify Eth source: OHM burned, bridgedSupply increased, total supply decreased
        vm.selectFork(ethForkId);
        assertEq(
            ethOhm.balanceOf(sender),
            ethSenderBalBefore - amount,
            "Eth: sender balance after bridge out"
        );
        assertEq(ethGateway.bridgedSupply(), amount, "Eth: bridgedSupply after outbound");
        assertEq(
            ethOhm.totalSupply(),
            ethTotalSupplyBeforeOutbound - amount,
            "Eth: total supply should decrease after burn"
        );

        // Verify Arb destination: recipient received OHM, total supply increased
        vm.selectFork(arbForkId);
        assertEq(arbOhm.balanceOf(recipient), amount, "Arb: recipient balance after bridge");
        assertEq(
            arbOhm.totalSupply(),
            arbTotalSupplyBeforeInbound + amount,
            "Arb: total supply should increase after mint"
        );

        // Transfer bridged OHM from recipient to sender for the return leg
        vm.prank(recipient);
        arbOhm.transfer(sender, amount);

        // Snapshot Eth total supply before the return leg delivers (mint on Eth)
        vm.selectFork(ethForkId);
        uint256 ethTotalSupplyBefore = ethOhm.totalSupply();

        // Step 2: Arb->Eth via real sendOhm path (proves Arb-side burn happens)
        vm.selectFork(arbForkId);
        uint256 arbSenderBalBefore = arbOhm.balanceOf(sender);
        uint256 arbTotalSupplyBefore = arbOhm.totalSupply();

        _sendAndDeliver(
            arbForkId,
            ethForkId,
            arbBridge,
            ethGateway,
            arbOhm,
            LZConfigLib.ETH_EID,
            sender,
            recipient,
            amount
        );

        // Verify Arb: OHM was actually burned
        vm.selectFork(arbForkId);
        assertEq(
            arbOhm.balanceOf(sender),
            arbSenderBalBefore - amount,
            "Arb: sender OHM burned on return leg"
        );
        assertEq(
            arbOhm.totalSupply(),
            arbTotalSupplyBefore - amount,
            "Arb: total supply should decrease after burn"
        );

        // Verify round-trip on Eth: bridgedSupply back to zero, recipient received OHM, supply increased
        vm.selectFork(ethForkId);
        assertEq(
            ethGateway.bridgedSupply(),
            0,
            "Bridged supply should return to zero after round-trip"
        );
        assertEq(
            ethOhm.balanceOf(recipient),
            amount,
            "Recipient should receive OHM after round-trip on mainnet"
        );
        assertEq(
            ethOhm.totalSupply(),
            ethTotalSupplyBefore + amount,
            "Eth: total supply should increase after mint"
        );
    }
}
