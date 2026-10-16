// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

// Scripting
import {console2} from "@forge-std-1.16.2/console2.sol";
import {LZBridgeTestnetBase} from "./LZBridgeTestnetBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Contracts
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";

// Local
import {LZTestnetConfig} from "./LZTestnetConfig.sol";

/// @title LZBridgeTestnetSend
/// @notice Sends OHM across the testnet LZ bridge from the active chain to a chosen destination.
/// @dev Separate from the deploy/configure script so message sending stays isolated. The active
///      (source) chain is resolved from `block.chainid`; the destination is passed in. The caller
///      must already hold the OHM being bridged (on arbitrum-sepolia, OHM appears only after a
///      message has been bridged in from another testnet).
///
///      The source transaction hash needed to track the message is captured by the `send.sh`
///      wrapper from the forge broadcast output and appended to `deployments/messages.json`.
contract LZBridgeTestnetSend is LZBridgeTestnetBase {
    error LZTestnet_InsufficientOhm(uint256 balance, uint256 amount);

    /// @notice Bridges `amount_` OHM (9 decimals) from the active chain to `dstChain_`, crediting
    ///         `to_` on the destination.
    /// @dev Reverts with `LZTestnet_InsufficientOhm` if the caller's OHM balance is below
    ///      `amount_`. The native LayerZero fee is quoted on-chain and paid as msg.value, so the
    ///      caller also needs enough native gas token to cover it.
    /// @param dstChain_ Destination chain name (sepolia / base-sepolia / arbitrum-sepolia).
    /// @param to_ Recipient address on the destination chain.
    /// @param amount_ OHM amount with 9 decimals (1 OHM == 1e9).
    function send(string calldata dstChain_, address to_, uint256 amount_) external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);
        address sender = msg.sender;

        string memory json = _readDeployment(chain_);
        address periphery = vm.parseJsonAddress(json, ".periphery");
        address ohm = vm.parseJsonAddress(json, ".ohm");
        uint32 dstEid = LZTestnetConfig.eidForChain(dstChain_);

        // The caller must already hold the OHM being bridged.
        uint256 balance = IERC20(ohm).balanceOf(sender);
        if (balance < amount_) revert LZTestnet_InsufficientOhm(balance, amount_);

        // Quote the native fee (read-only, before broadcasting).
        MessagingFee memory fee = LZCrossChainBridge(periphery).estimateSendFee(
            dstEid,
            to_,
            amount_
        );

        console2.log("\n=== [LZ testnet] Send:", chain_, "===");
        console2.log("  dstChain:", dstChain_);
        console2.log("  dstEid:", dstEid);
        console2.log("  recipient:", to_);
        console2.log("  amount (9dp):", amount_);
        console2.log("  nativeFee (wei):", fee.nativeFee);

        vm.startBroadcast();
        if (IERC20(ohm).allowance(sender, periphery) < amount_) {
            IERC20(ohm).approve(periphery, amount_);
        }
        LZCrossChainBridge(periphery).sendOhm{value: fee.nativeFee}(dstEid, to_, amount_);
        vm.stopBroadcast();

        console2.log("  Sent. Track with shell/lz-bridge/testnet/message_status.sh");
    }
}
