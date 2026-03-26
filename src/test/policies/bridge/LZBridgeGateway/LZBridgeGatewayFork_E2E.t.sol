// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

// Interfaces
import {MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {Errors} from "@lz-evm-protocol-v2-3.0.162/libs/Errors.sol";

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

/// @notice E2E fork tests: full send path via LZCrossChainBridge -> gateway -> real EndpointV2,
///         then relay by parsing the PacketSent event and delivering on the destination fork.
/// @dev Unlike the tests above (which construct messages manually), these tests exercise the
///      complete send path on production LZ V2 endpoints, verifying encoding, fee estimation,
///      burn, bridgedSupply tracking, and the real PacketSent event payload.
contract LZBridgeGatewayForkTests_E2E is Test {
    // ========= CONSTANTS ========= //

    /// @dev PacketV1Codec byte offsets for decoding the encoded packet.
    uint256 constant NONCE_OFFSET = 1;
    uint256 constant SRC_EID_OFFSET = 9;
    uint256 constant SENDER_OFFSET = 13;
    uint256 constant GUID_OFFSET = 81;
    uint256 constant MESSAGE_OFFSET = 113;

    uint256 constant MINT_AMOUNT = 10_000e9;
    uint256 constant SUPPLY_CAP = 1_000_000e9;

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

    function setUp() public {
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

        // Cross-configure peers (end on ethFork to avoid fork-switch issues)
        vm.selectFork(arbForkId);
        vm.prank(admin);
        arbGateway.setPeer(LZConfigLib.ETH_EID, LZConfigLib.addressToBytes32(address(ethGateway)));

        vm.selectFork(ethForkId);
        vm.prank(admin);
        ethGateway.setPeer(LZConfigLib.ARB_EID, LZConfigLib.addressToBytes32(address(arbGateway)));

        // Set enforced options on ethGateway for LZConfigLib.ARB_EID (required for endpoint.send)
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: LZConfigLib.ARB_EID,
            msgType: 1, // MSG_BRIDGE_OHM
            // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
            options: abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), uint128(200_000))
        });
        vm.prank(admin);
        ethGateway.setEnforcedOptions(opts);

        // setUp ends on ethFork
    }

    function _deployEthStack() internal {
        ethOhm = new MockOhm("OHM", "OHM", 9);
        ethKernel = new Kernel();
        ethMintr = new OlympusMinter(ethKernel, address(ethOhm));
        ethRoles = new OlympusRoles(ethKernel);
        ethRolesAdmin = new RolesAdmin(ethKernel);
        ethGateway = new LZBridgeGateway(
            ethKernel,
            LZConfigLib.ETH_LZ_ENDPOINT,
            true // Canonical
        );

        ethKernel.executeAction(Actions.InstallModule, address(ethMintr));
        ethKernel.executeAction(Actions.InstallModule, address(ethRoles));
        ethKernel.executeAction(Actions.ActivatePolicy, address(ethRolesAdmin));
        ethKernel.executeAction(Actions.ActivatePolicy, address(ethGateway));

        ethRolesAdmin.grantRole("admin", admin);
        ethBridge = new LZCrossChainBridge(address(ethOhm), admin, address(ethGateway));
        ethRolesAdmin.grantRole("bridge_facilitator", address(ethBridge));

        vm.startPrank(admin);
        ethGateway.setBridgedSupplyCap(SUPPLY_CAP);
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
            false // Non-canonical
        );

        arbKernel.executeAction(Actions.InstallModule, address(arbMintr));
        arbKernel.executeAction(Actions.InstallModule, address(arbRoles));
        arbKernel.executeAction(Actions.ActivatePolicy, address(arbRolesAdmin));
        arbKernel.executeAction(Actions.ActivatePolicy, address(arbGateway));

        arbRolesAdmin.grantRole("admin", admin);
        arbBridge = new LZCrossChainBridge(address(arbOhm), admin, address(arbGateway));
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

        // PacketV1Codec layout: [version(1)][nonce(8)][srcEid(4)][sender(32)][dstEid(4)][receiver(32)][guid(32)][message(...)]
        assembly {
            let p := add(pkt_, 32) // skip memory length prefix
            nonce_ := shr(192, mload(add(p, 1))) // uint64 at offset 1
            srcEid_ := shr(224, mload(add(p, 9))) // uint32 at offset 9
            senderB32_ := mload(add(p, 13)) // bytes32 at offset 13
            guid := mload(add(p, 81)) // bytes32 at offset 81
        }

        origin = Origin({srcEid: srcEid_, sender: senderB32_, nonce: nonce_});

        // Extract message bytes from offset 113 onwards
        uint256 msgLen = pkt_.length - MESSAGE_OFFSET;
        message = new bytes(msgLen);
        for (uint256 i = 0; i < msgLen; ++i) {
            message[i] = pkt_[MESSAGE_OFFSET + i];
        }
    }

    // ========= E2E TESTS ========= //

    /// @notice Full e2e: sendOhm on ETH fork via real EndpointV2, parse PacketSent, deliver on ARB fork.
    function test_e2e_ethToArb_sendAndRelay() external {
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
    function test_e2e_feeEstimation_matchesSend() external {
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

    /// @notice Verifies bridgedSupply cap enforcement on the real endpoint send path.
    function test_e2e_bridgedSupplyCap_enforced() external {
        // Set a low cap
        vm.prank(admin);
        ethGateway.setBridgedSupplyCap(500e9);

        MessagingFee memory fee = ethBridge.estimateSendFee(LZConfigLib.ARB_EID, recipient, 1000e9);

        vm.startPrank(sender);
        ethOhm.approve(address(ethBridge), 1000e9);
        vm.expectRevert();
        ethBridge.sendOhm{value: fee.nativeFee}(LZConfigLib.ARB_EID, recipient, 1000e9);
        vm.stopPrank();
    }
}
