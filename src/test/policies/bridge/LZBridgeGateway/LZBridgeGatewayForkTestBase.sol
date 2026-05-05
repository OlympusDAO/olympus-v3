// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

// Interfaces
import {MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @notice Shared setup, deploy helpers, and packet-parsing utilities for LZBridgeGateway fork tests.
/// @dev Deploys full Eth (canonical) and Arb (non-canonical) stacks against real LZ V2 endpoints,
///      cross-configures peers and enforced options, and provides helpers that exercise the real
///      sendOhm() -> burnAndSend() -> EndpointV2.send() path.
abstract contract LZBridgeGatewayForkTestBase is Test {
    // ========= CONSTANTS ========= //

    /// @dev PacketV1Codec: message bytes start at offset 113.
    uint256 constant MESSAGE_OFFSET = 113;

    uint256 constant MINT_AMOUNT = 10_000e9;
    uint32 constant GRACE_SECONDS = 1 days;

    // ========= FORKS ========= //

    uint256 ethForkId;
    uint256 arbForkId;

    // ========= ETHEREUM CONTRACTS ========= //

    MockOhm ethOhm;
    Kernel ethKernel;
    OlympusMinter ethMintr;
    OlympusRoles ethRoles;
    RolesAdmin ethRolesAdmin;
    LZBridgeGateway ethGateway;
    LZCrossChainBridge ethBridge;

    // ========= ARBITRUM CONTRACTS ========= //

    MockOhm arbOhm;
    Kernel arbKernel;
    OlympusMinter arbMintr;
    OlympusRoles arbRoles;
    RolesAdmin arbRolesAdmin;
    LZBridgeGateway arbGateway;
    LZCrossChainBridge arbBridge;

    // ========= ADDRESSES ========= //

    address admin;
    address sender;
    address recipient;

    // ========= SETUP ========= //

    function setUp() public virtual {
        ethForkId = vm.createFork("mainnet");
        arbForkId = vm.createFork("arbitrum");

        admin = makeAddr("admin");
        sender = makeAddr("sender");
        recipient = makeAddr("recipient");
        vm.makePersistent(admin);
        vm.makePersistent(sender);
        vm.makePersistent(recipient);

        // Deploy Ethereum stack
        vm.selectFork(ethForkId);
        _deployEthStack();

        // Deploy Arbitrum stack
        vm.selectFork(arbForkId);
        _deployArbStack();

        // Cross-configure peers
        vm.selectFork(arbForkId);
        vm.prank(admin);
        arbGateway.setPeer(LZConfigLib.ETH_EID, LZConfigLib.addressToBytes32(address(ethGateway)));

        vm.selectFork(ethForkId);
        vm.prank(admin);
        ethGateway.setPeer(LZConfigLib.ARB_EID, LZConfigLib.addressToBytes32(address(arbGateway)));

        // Set enforced options on both gateways (required for endpoint.send)
        // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
        bytes memory lzReceiveOptions = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(200_000)
        );

        EnforcedOptionParam[] memory ethOpts = new EnforcedOptionParam[](1);
        ethOpts[0] = EnforcedOptionParam({
            eid: LZConfigLib.ARB_EID,
            msgType: 1, // MSG_BRIDGE_OHM
            options: lzReceiveOptions
        });
        vm.prank(admin);
        ethGateway.setEnforcedOptions(ethOpts);

        vm.selectFork(arbForkId);
        EnforcedOptionParam[] memory arbOpts = new EnforcedOptionParam[](1);
        arbOpts[0] = EnforcedOptionParam({
            eid: LZConfigLib.ETH_EID,
            msgType: 1, // MSG_BRIDGE_OHM
            options: lzReceiveOptions
        });
        vm.prank(admin);
        arbGateway.setEnforcedOptions(arbOpts);

        // End on ethFork
        vm.selectFork(ethForkId);
    }

    // ========= DEPLOY HELPERS ========= //

    function _deployEthStack() internal {
        ethOhm = new MockOhm("OHM", "OHM", 9);
        ethKernel = new Kernel();
        ethMintr = new OlympusMinter(ethKernel, address(ethOhm));
        ethRoles = new OlympusRoles(ethKernel);
        ethRolesAdmin = new RolesAdmin(ethKernel);
        ethGateway = new LZBridgeGateway(
            ethKernel,
            LZConfigLib.ETH_LZ_ENDPOINT,
            true, // Canonical
            GRACE_SECONDS
        );

        ethKernel.executeAction(Actions.InstallModule, address(ethMintr));
        ethKernel.executeAction(Actions.InstallModule, address(ethRoles));
        ethKernel.executeAction(Actions.ActivatePolicy, address(ethRolesAdmin));
        ethKernel.executeAction(Actions.ActivatePolicy, address(ethGateway));

        ethRolesAdmin.grantRole("admin", admin);
        ethBridge = new LZCrossChainBridge(
            address(ethOhm),
            admin,
            address(ethGateway),
            admin,
            GRACE_SECONDS
        );
        ethRolesAdmin.grantRole("bridge_facilitator", address(ethBridge));

        vm.startPrank(admin);
        ethGateway.enable(bytes(""));
        ethBridge.enable(bytes(""));
        vm.stopPrank();

        ethOhm.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);

        _makePersistent(
            ethOhm,
            ethKernel,
            ethMintr,
            ethRoles,
            ethRolesAdmin,
            ethGateway,
            ethBridge
        );
    }

    function _deployArbStack() internal {
        arbOhm = new MockOhm("OHM", "OHM", 9);
        arbKernel = new Kernel();
        arbMintr = new OlympusMinter(arbKernel, address(arbOhm));
        arbRoles = new OlympusRoles(arbKernel);
        arbRolesAdmin = new RolesAdmin(arbKernel);
        arbGateway = new LZBridgeGateway(
            arbKernel,
            LZConfigLib.ARB_LZ_ENDPOINT,
            false, // Non-canonical
            GRACE_SECONDS
        );

        arbKernel.executeAction(Actions.InstallModule, address(arbMintr));
        arbKernel.executeAction(Actions.InstallModule, address(arbRoles));
        arbKernel.executeAction(Actions.ActivatePolicy, address(arbRolesAdmin));
        arbKernel.executeAction(Actions.ActivatePolicy, address(arbGateway));

        arbRolesAdmin.grantRole("admin", admin);
        arbBridge = new LZCrossChainBridge(
            address(arbOhm),
            admin,
            address(arbGateway),
            admin,
            GRACE_SECONDS
        );
        arbRolesAdmin.grantRole("bridge_facilitator", address(arbBridge));

        vm.startPrank(admin);
        arbGateway.enable(bytes(""));
        arbBridge.enable(bytes(""));
        vm.stopPrank();

        arbOhm.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);

        _makePersistent(
            arbOhm,
            arbKernel,
            arbMintr,
            arbRoles,
            arbRolesAdmin,
            arbGateway,
            arbBridge
        );
    }

    function _makePersistent(
        MockOhm ohm_,
        Kernel kernel_,
        OlympusMinter mintr_,
        OlympusRoles roles_,
        RolesAdmin rolesAdmin_,
        LZBridgeGateway gateway_,
        LZCrossChainBridge bridge_
    ) internal {
        vm.makePersistent(address(ohm_));
        vm.makePersistent(address(kernel_));
        vm.makePersistent(address(mintr_));
        vm.makePersistent(address(roles_));
        vm.makePersistent(address(rolesAdmin_));
        vm.makePersistent(address(gateway_));
        vm.makePersistent(address(bridge_));
    }

    // ========= PACKET PARSING HELPERS ========= //

    /// @dev Finds the PacketSent event in recorded logs and returns the encoded packet.
    function _findPacketSent(Vm.Log[] memory logs_) internal pure returns (bytes memory) {
        bytes32 sig = keccak256("PacketSent(bytes,bytes,address)");
        for (uint256 i = 0; i < logs_.length; ++i) {
            if (logs_[i].topics[0] == sig) {
                (bytes memory encoded, , ) = abi.decode(logs_[i].data, (bytes, bytes, address));
                return encoded;
            }
        }
        revert("PacketSent event not found");
    }

    /// @dev Extracts Origin, guid, and message from an encoded LZ V2 packet (PacketV1Codec layout).
    function _parsePacket(
        bytes memory pkt_
    ) internal pure returns (Origin memory origin, bytes32 guid, bytes memory message) {
        uint64 nonce_;
        uint32 srcEid_;
        bytes32 senderB32_;

        // PacketV1Codec: [version(1)][nonce(8)][srcEid(4)][sender(32)][dstEid(4)][receiver(32)][guid(32)][message(...)]
        assembly {
            let p := add(pkt_, 32) // skip memory length prefix
            nonce_ := shr(192, mload(add(p, 1))) // uint64 at offset 1
            srcEid_ := shr(224, mload(add(p, 9))) // uint32 at offset 9
            senderB32_ := mload(add(p, 13)) // bytes32 at offset 13
            guid := mload(add(p, 81)) // bytes32 at offset 81
        }

        origin = Origin({srcEid: srcEid_, sender: senderB32_, nonce: nonce_});

        uint256 msgLen = pkt_.length - MESSAGE_OFFSET;
        message = new bytes(msgLen);
        for (uint256 i = 0; i < msgLen; ++i) {
            message[i] = pkt_[MESSAGE_OFFSET + i];
        }
    }

    /// @dev Sends OHM via the real bridge path on srcFork and delivers the parsed packet on dstFork.
    ///      Exercises: sendOhm() -> transferFrom -> burnAndSend() -> burn -> EndpointV2.send().
    function _sendAndDeliver(
        uint256 srcForkId_,
        uint256 dstForkId_,
        LZCrossChainBridge srcBridge_,
        LZBridgeGateway dstGw_,
        MockOhm srcOhm_,
        uint32 dstEid_,
        address from_,
        address to_,
        uint256 amount_
    ) internal {
        // === SOURCE: estimate fee, approve, send ===
        vm.selectFork(srcForkId_);

        MessagingFee memory fee = srcBridge_.estimateSendFee(dstEid_, to_, amount_);

        vm.startPrank(from_);
        srcOhm_.approve(address(srcBridge_), amount_);
        vm.recordLogs();
        srcBridge_.sendOhm{value: fee.nativeFee}(dstEid_, to_, amount_);
        vm.stopPrank();

        // Parse the real PacketSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory encodedPacket = _findPacketSent(logs);
        (Origin memory origin, bytes32 guid, bytes memory message) = _parsePacket(encodedPacket);

        // === DESTINATION: deliver the real packet ===
        vm.selectFork(dstForkId_);
        vm.prank(dstGw_.LZ_ENDPOINT());
        dstGw_.lzReceive(origin, guid, message, address(0), bytes(""));
    }
}
