// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

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

/// @notice Fork-based end-to-end tests for LZBridgeGateway cross-chain bridge (LZ V2).
/// @dev Message delivery is simulated by pranking the LZ V2 endpoint to call
///      `gateway.lzReceive()` directly.
contract LZBridgeGatewayForkTests is Test {
    // ========= CONSTANTS ========= //

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

    function setUp() external {
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
        vm.selectFork(ethForkId);
        vm.prank(admin);
        ethGateway.setPeer(LZConfigLib.ARB_EID, LZConfigLib.addressToBytes32(address(arbGateway)));

        vm.selectFork(arbForkId);
        vm.prank(admin);
        arbGateway.setPeer(LZConfigLib.ETH_EID, LZConfigLib.addressToBytes32(address(ethGateway)));
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

    // ========= HELPERS ========= //

    /// @dev Simulates LZ V2 message delivery by pranking the endpoint to call lzReceive.
    function _deliverMessage(
        uint256 dstForkId,
        LZBridgeGateway dstGw,
        uint32 srcEid,
        address srcGw,
        address to,
        uint256 amount
    ) internal {
        vm.selectFork(dstForkId);

        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: LZConfigLib.addressToBytes32(srcGw),
            nonce: 1
        });
        bytes memory message = abi.encode(uint8(1), abi.encode(to, amount));

        vm.prank(dstGw.LZ_ENDPOINT());
        dstGw.lzReceive(origin, bytes32(0), message, address(0), bytes(""));
    }

    // ========= TESTS ========= //

    function test_ethToArb() external {
        uint256 amount = 1000e9;

        // Deliver message to arb (simulates LZ V2 endpoint calling lzReceive)
        // In production, burnAndSend on eth sends the LZ message; here we simulate the receive side.
        _deliverMessage(
            arbForkId,
            arbGateway,
            LZConfigLib.ETH_EID,
            address(ethGateway),
            recipient,
            amount
        );

        // Verify arb: recipient received OHM
        vm.selectFork(arbForkId);
        assertEq(arbOhm.balanceOf(recipient), amount, "Arb: recipient should receive OHM");
    }

    function test_arbToEth() external {
        uint256 amount = 1000e9;

        // First bridge to arb so we have bridgedSupply
        _deliverMessage(
            arbForkId,
            arbGateway,
            LZConfigLib.ETH_EID,
            address(ethGateway),
            recipient,
            amount
        );

        // Set bridgedSupply on eth (simulates the outbound tracking)
        vm.selectFork(ethForkId);
        ethRolesAdmin.grantRole("bridge_admin", admin);
        vm.prank(admin);
        ethGateway.setBridgedSupply(amount);

        // Deliver message from arb to eth
        _deliverMessage(
            ethForkId,
            ethGateway,
            LZConfigLib.ARB_EID,
            address(arbGateway),
            recipient,
            amount
        );

        // Verify eth: bridgedSupply decreases, recipient gets OHM
        vm.selectFork(ethForkId);
        assertEq(ethGateway.bridgedSupply(), 0, "Eth: bridgedSupply should decrease to 0");
        assertEq(ethOhm.balanceOf(recipient), amount, "Eth: recipient should receive OHM");
    }

    function test_roundTrip_fullFlow() external {
        uint256 amount = 500e9;

        // Step 1: eth -> arb (deliver on arb)
        _deliverMessage(
            arbForkId,
            arbGateway,
            LZConfigLib.ETH_EID,
            address(ethGateway),
            recipient,
            amount
        );

        vm.selectFork(arbForkId);
        assertEq(arbOhm.balanceOf(recipient), amount, "Arb: recipient balance after bridge");

        // Set bridgedSupply on eth
        vm.selectFork(ethForkId);
        ethRolesAdmin.grantRole("bridge_admin", admin);
        vm.prank(admin);
        ethGateway.setBridgedSupply(amount);

        // Step 2: arb -> eth (deliver on eth)
        _deliverMessage(
            ethForkId,
            ethGateway,
            LZConfigLib.ARB_EID,
            address(arbGateway),
            recipient,
            amount
        );

        // Verify round-trip
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
    }
}
