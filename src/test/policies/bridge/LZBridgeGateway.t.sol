// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy, Permissions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroReceiver.sol";
import {Origin, MessagingFee} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroEndpointV2.sol";
import {ISendLib, Packet} from "@lz-evm-protocol-v2-3.0.142/interfaces/ISendLib.sol";
import {IMessageLib, MessageLibType} from "@lz-evm-protocol-v2-3.0.142/interfaces/IMessageLib.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.142/interfaces/IMessageLibManager.sol";
import {EndpointV2Mock} from "@lz-test-devtools-0.2.11/mocks/EndpointV2Mock.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

// solhint-disable max-states-count

/// @dev Minimal mock send/receive library for EndpointV2Mock tests.
///      Returns a fixed 100 wei native fee. No packet scheduling or relay.
contract MockSendLib {
    uint256 public constant NATIVE_FEE = 100;

    function send(
        Packet calldata,
        bytes calldata,
        bool
    ) external pure returns (MessagingFee memory fee, bytes memory encodedPacket) {
        fee = MessagingFee(NATIVE_FEE, 0);
        encodedPacket = bytes("");
    }

    function quote(
        Packet calldata,
        bytes calldata,
        bool
    ) external pure returns (MessagingFee memory) {
        return MessagingFee(NATIVE_FEE, 0);
    }

    function setConfig(address, SetConfigParam[] calldata) external {}

    function getConfig(uint32, address, uint32) external pure returns (bytes memory) {
        return bytes("");
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        return true;
    }

    function version() external pure returns (uint64, uint8, uint8) {
        return (0, 0, 2);
    }

    function messageLibType() external pure returns (MessageLibType) {
        return MessageLibType.SendAndReceive;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IMessageLib).interfaceId || interfaceId == 0x01ffc9a7; // ERC165
    }

    fallback() external payable {}

    receive() external payable {}
}

contract LZBridgeGatewayTestBase is Test {
    uint32 constant CANONICAL_EID = 1;
    uint32 constant NONCANONICAL_EID = 2;
    uint256 constant INITIAL_AMOUNT = 100_000e9;
    uint256 constant SUPPLY_CAP = 1_000_000e9;

    // Canonical stack
    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;
    EndpointV2Mock endpoint;

    // Non-canonical stack
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;
    EndpointV2Mock endpoint2;

    // Shared
    MockOhm ohm;

    address admin = makeAddr("admin");
    address bridgeAdmin = makeAddr("bridgeAdmin");
    address facilitator = makeAddr("facilitator");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    function setUp() public virtual {
        // 1. Deploy mock V2 endpoints
        endpoint = new EndpointV2Mock(CANONICAL_EID, address(this));
        endpoint2 = new EndpointV2Mock(NONCANONICAL_EID, address(this));

        // 2. Deploy and register mock send libraries
        MockSendLib sendLib1 = new MockSendLib();
        MockSendLib sendLib2 = new MockSendLib();
        endpoint.registerLibrary(address(sendLib1));
        endpoint2.registerLibrary(address(sendLib2));

        // Set default send/receive libraries for each remote EID
        endpoint.setDefaultSendLibrary(NONCANONICAL_EID, address(sendLib1));
        endpoint.setDefaultReceiveLibrary(NONCANONICAL_EID, address(sendLib1), 0);
        endpoint2.setDefaultSendLibrary(CANONICAL_EID, address(sendLib2));
        endpoint2.setDefaultReceiveLibrary(CANONICAL_EID, address(sendLib2), 0);

        // 3. Deploy mock OHM
        ohm = new MockOhm("Olympus", "OHM", 9);

        // 4. Deploy canonical stack
        kernel = new Kernel();
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        gateway = new LZBridgeGateway(kernel, address(endpoint), true, facilitator);

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        // Grant roles on canonical
        rolesAdmin.grantRole("admin", admin);
        rolesAdmin.grantRole("bridge_admin", bridgeAdmin);

        // 5. Deploy non-canonical stack
        kernel2 = new Kernel();
        mintr2 = new OlympusMinter(kernel2, address(ohm));
        roles2 = new OlympusRoles(kernel2);
        rolesAdmin2 = new RolesAdmin(kernel2);
        gateway2 = new LZBridgeGateway(kernel2, address(endpoint2), false, facilitator);

        kernel2.executeAction(Actions.InstallModule, address(mintr2));
        kernel2.executeAction(Actions.InstallModule, address(roles2));
        kernel2.executeAction(Actions.ActivatePolicy, address(rolesAdmin2));
        kernel2.executeAction(Actions.ActivatePolicy, address(gateway2));

        // Grant roles on non-canonical
        rolesAdmin2.grantRole("admin", admin);
        rolesAdmin2.grantRole("bridge_admin", bridgeAdmin);

        // 6. Configure gateways
        vm.startPrank(admin);
        // Set peers (cross-linked)
        gateway.setPeer(NONCANONICAL_EID, address(gateway2));
        gateway2.setPeer(CANONICAL_EID, address(gateway));

        // Set bridged supply cap on canonical
        gateway.setBridgedSupplyCap(SUPPLY_CAP);

        // Enable both gateways
        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // 7. Mint OHM to facilitator for burnAndSend tests
        ohm.mint(facilitator, INITIAL_AMOUNT);

        // Fund test contract for native fees
        vm.deal(facilitator, 100 ether);
        vm.deal(user, 100 ether);
    }

    function _buildBridgePayload(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(gateway.MSG_BRIDGE_OHM(), abi.encode(to, amount));
    }

    /// @dev Simulates lzReceive call directly to the gateway via vm.prank(endpoint)
    function _simulateLzReceive(
        LZBridgeGateway target,
        address endpointAddr,
        uint32 srcEid,
        address srcGateway,
        address to,
        uint256 amount
    ) internal {
        bytes memory payload = _buildBridgePayload(to, amount);
        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(srcGateway))),
            nonce: 1
        });

        vm.prank(endpointAddr);
        target.lzReceive{value: 0}(origin, bytes32(0), payload, address(0), bytes(""));
    }

    /// @dev Performs a burnAndSend from the facilitator.
    ///      Note: With MockSendLib, messages are NOT relayed. For E2E tests,
    ///      simulate the receive separately via _simulateLzReceive.
    function _doBurnAndSend(
        LZBridgeGateway source,
        uint32 dstEid,
        address to,
        uint256 amount
    ) internal {
        vm.startPrank(facilitator);
        ohm.transfer(address(source), amount);

        // Estimate fee
        (uint256 fee, ) = source.estimateSendFee(dstEid, to, amount, bytes(""));

        source.burnAndSend{value: fee}(dstEid, to, amount, payable(facilitator), bytes(""));
        vm.stopPrank();
    }
}

contract LZBridgeGatewayTests_Constructor is LZBridgeGatewayTestBase {
    function test_constructor_canonical() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(facilitator);

        LZBridgeGateway fresh = new LZBridgeGateway(kernel, address(endpoint), true, facilitator);

        // Immutables
        assertEq(fresh.LZ_ENDPOINT(), address(endpoint), "LZ_ENDPOINT should be set");
        assertTrue(fresh.IS_CANONICAL(), "IS_CANONICAL should be true");
        // State
        assertEq(address(fresh.kernel()), address(kernel), "Kernel should be set");
        assertEq(fresh.facilitator(), facilitator, "Facilitator should be set");
        assertFalse(fresh.isEnabled(), "Should start disabled");

        assertEq(fresh.bridgedSupply(), 0, "Bridged supply should be zero");
        assertEq(fresh.bridgedSupplyCap(), 0, "Bridged supply cap should be zero");
    }

    function test_constructor_nonCanonical() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(facilitator);

        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel2,
            address(endpoint2),
            false,
            facilitator
        );

        assertEq(address(fresh.kernel()), address(kernel2), "Kernel should be set");
        assertEq(
            fresh.LZ_ENDPOINT(),
            address(endpoint2),
            "LZ_ENDPOINT should be the non-canonical endpoint"
        );
        assertFalse(fresh.IS_CANONICAL(), "IS_CANONICAL should be false for non-canonical gateway");
        assertEq(fresh.facilitator(), facilitator, "Facilitator should be set");
        assertFalse(fresh.isEnabled(), "Gateway should start disabled");
    }

    function test_constructor_revertsIfKernelZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "kernel"
            )
        );
        new LZBridgeGateway(Kernel(address(0)), address(endpoint), true, facilitator);
    }

    function test_constructor_revertsIfEndpointZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "lzEndpoint"
            )
        );
        new LZBridgeGateway(kernel, address(0), true, facilitator);
    }

    function test_constructor_revertsIfFacilitatorZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "facilitator"
            )
        );
        new LZBridgeGateway(kernel, address(endpoint), true, address(0));
    }
}

contract LZBridgeGatewayTests_PolicySetup is LZBridgeGatewayTestBase {
    function test_configureDependencies() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should be set");
        assertEq(gateway.ohm(), address(ohm), "OHM address should be set from MINTR");
    }

    function test_requestPermissions() external view {
        Permissions[] memory perms = gateway.requestPermissions();

        assertEq(perms.length, 3, "Should request 3 permissions");
        assertEq(
            Keycode.unwrap(perms[0].keycode),
            bytes5("MINTR"),
            "Permission 0 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[1].keycode),
            bytes5("MINTR"),
            "Permission 1 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[2].keycode),
            bytes5("MINTR"),
            "Permission 2 should be on MINTR"
        );
    }

    function test_VERSION() external view {
        (uint8 major, uint8 minor) = gateway.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}

contract LZBridgeGatewayTests_EnableDisable is LZBridgeGatewayTestBase {
    function test_enable() external {
        LZBridgeGateway fresh = new LZBridgeGateway(kernel, address(endpoint), true, facilitator);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));

        vm.prank(admin);
        fresh.enable(bytes(""));

        assertTrue(fresh.isEnabled(), "Gateway should be enabled after enable()");
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(admin);
        gateway.enable(bytes(""));
    }

    function test_enable_revertsIfNotAdmin() external {
        LZBridgeGateway fresh = new LZBridgeGateway(kernel, address(endpoint), true, facilitator);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        fresh.enable(bytes(""));
    }

    function test_disable() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        assertFalse(gateway.isEnabled(), "Gateway should be disabled after disable()");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(admin);
        gateway.disable(bytes(""));
    }

    function test_disable_revertsIfNotAdmin() external {
        vm.expectRevert();
        vm.prank(user);
        gateway.disable(bytes(""));
    }
}

contract LZBridgeGatewayTests_BurnAndSend is LZBridgeGatewayTestBase {
    function test_burnAndSend_canonical() external {
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        uint256 amount = 1000e9;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        (uint256 fee, ) = gateway.estimateSendFee(NONCANONICAL_EID, recipient, amount, bytes(""));

        uint256 facilitatorEthBefore = facilitator.balance;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyIncreased(amount);

        gateway.burnAndSend{value: fee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Verify
        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator balance should decrease by amount"
        );
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(
            gateway.bridgedSupply(),
            amount,
            "Bridged supply should increase by amount on canonical"
        );
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway).balance, 0, "Gateway should hold no ETH after send");
    }

    function test_burnAndSend_nonCanonical_doesNotTrackSupply() external {
        uint256 amount = 1000e9;

        ohm.mint(facilitator, amount);

        // Mint OHM on non-canonical by simulating lzReceive
        _simulateLzReceive(
            gateway2,
            address(endpoint2),
            CANONICAL_EID,
            address(gateway),
            facilitator,
            amount
        );

        // Send from non-canonical back to canonical
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(CANONICAL_EID, recipient, amount, bytes(""));

        uint256 facilitatorEthBefore = facilitator.balance;

        gateway2.burnAndSend{value: fee}(
            CANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Verify
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track bridged supply");
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway2).balance, 0, "Gateway should hold no ETH after send");
    }

    function test_burnAndSend_revertsIfNotFacilitator() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyFacilitator.selector)
        );
        vm.prank(user);
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            1000e9,
            payable(user),
            bytes("")
        );
    }

    function test_burnAndSend_revertsIfToZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        vm.prank(facilitator);
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            address(0),
            1000e9,
            payable(user),
            bytes("")
        );
    }

    function test_burnAndSend_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(facilitator);
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            1000e9,
            payable(facilitator),
            bytes("")
        );
    }

    function test_burnAndSend_revertsIfNoPeer() external {
        uint32 unknownEid = 42;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_DestinationNotTrusted.selector)
        );
        gateway.burnAndSend{value: 1 ether}(
            unknownEid,
            recipient,
            1000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_canonical_revertsIfSupplyCapExceeded() external {
        uint256 amount = SUPPLY_CAP + 1;
        ohm.mint(facilitator, amount);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        (uint256 fee, ) = gateway.estimateSendFee(NONCANONICAL_EID, recipient, amount, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                amount,
                SUPPLY_CAP
            )
        );
        gateway.burnAndSend{value: fee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }
}

contract LZBridgeGatewayTests_LZReceiver is LZBridgeGatewayTestBase {
    function test_lzReceive_canonical() external {
        // 1. Send some OHM out to build bridged supply
        uint256 initialAmount = 5000e9;
        _doBurnAndSend(gateway, NONCANONICAL_EID, recipient, initialAmount);
        assertEq(
            gateway.bridgedSupply(),
            initialAmount,
            "Bridged supply should be the initial amount after send"
        );

        // 2. Receive back on canonical
        uint256 recipientBalanceBefore = ohm.balanceOf(recipient);
        uint256 amount = 2000e9;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyDecreased(amount);
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.Received(recipient, amount, NONCANONICAL_EID);

        _simulateLzReceive(
            gateway,
            address(endpoint),
            NONCANONICAL_EID,
            address(gateway2),
            recipient,
            amount
        );

        assertEq(
            ohm.balanceOf(recipient),
            recipientBalanceBefore + amount,
            "Recipient should receive minted OHM"
        );
        assertEq(
            gateway.bridgedSupply(),
            initialAmount - amount,
            "Bridged supply should decrease by received amount"
        );
    }

    function test_lzReceive_nonCanonical_doesNotTrackSupply() external {
        _simulateLzReceive(
            gateway2,
            address(endpoint2),
            CANONICAL_EID,
            address(gateway),
            recipient,
            1000e9
        );

        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track bridged supply");
    }

    function test_lzReceive_revertsOnInvalidMsgType() external {
        uint256 amount = 1000e9;
        bytes memory badPayload = abi.encode(uint8(42), abi.encode(recipient, amount));

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageType.selector, 42)
        );
        vm.prank(address(endpoint));
        gateway.lzReceive{value: 0}(origin, bytes32(0), badPayload, address(0), bytes(""));
    }

    function test_lzReceive_revertsOnInvalidPayloadLength() external {
        bytes memory shortData = abi.encode(recipient); // 32 bytes, not 64
        bytes memory badPayload = abi.encode(gateway.MSG_BRIDGE_OHM(), shortData);

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpoint));
        gateway.lzReceive{value: 0}(origin, bytes32(0), badPayload, address(0), bytes(""));
    }

    function test_lzReceive_canonical_revertsOnSupplyUnderflow() external {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be 0");

        uint256 amount = 1000e9;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                amount
            )
        );
        vm.prank(address(endpoint));
        gateway.lzReceive{value: 0}(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(address(endpoint));
        gateway.lzReceive{value: 0}(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfNotEndpoint() external {
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidCaller.selector)
        );
        vm.prank(user);
        gateway.lzReceive{value: 0}(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfInvalidSender() external {
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(user))),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageSource.selector)
        );
        vm.prank(address(endpoint));
        gateway.lzReceive{value: 0}(origin, bytes32(0), payload, address(0), bytes(""));
    }
}

contract LZBridgeGatewayTests_EstimateSendFee is LZBridgeGatewayTestBase {
    function test_estimateSendFee_returnsNonZeroFee() external view {
        uint256 amount = 1000e9;
        (uint256 nativeFee, ) = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        // MockSendLib returns 100 wei native fee
        assertEq(nativeFee, 100, "Native fee should be 100 (MockSendLib default)");
    }
}

contract LZBridgeGatewayTests_Administrative is LZBridgeGatewayTestBase {
    function test_setFacilitator() external {
        address newFacilitator = makeAddr("newFacilitator");
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(newFacilitator);
        vm.prank(admin);
        gateway.setFacilitator(newFacilitator);
        assertEq(gateway.facilitator(), newFacilitator, "Facilitator should be updated");
    }

    function test_setFacilitator_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setFacilitator(user);
    }

    function test_setFacilitator_revertsIfZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "facilitator"
            )
        );
        vm.prank(admin);
        gateway.setFacilitator(address(0));
    }

    function test_setBridgedSupplyCap() external {
        uint256 newCap = 100_000e9;
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyCapSet(newCap);
        vm.prank(admin);
        gateway.setBridgedSupplyCap(newCap);
        assertEq(gateway.bridgedSupplyCap(), newCap, "Bridged supply cap should be set");
    }

    function test_setBridgedSupplyCap_lessThanCurrentSupplyPreventsNewBridgings() external {
        uint256 bridgedAmount = 10_000e9;
        _doBurnAndSend(gateway, NONCANONICAL_EID, recipient, bridgedAmount);
        assertEq(gateway.bridgedSupply(), bridgedAmount, "Bridged supply should match");

        uint256 lowCap = 5000e9;
        vm.prank(admin);
        gateway.setBridgedSupplyCap(lowCap);

        uint256 newAmount = 1e9;
        ohm.mint(facilitator, newAmount);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), newAmount);
        (uint256 fee, ) = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                bridgedAmount + newAmount,
                lowCap
            )
        );
        gateway.burnAndSend{value: fee}(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_setBridgedSupplyCap_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setBridgedSupplyCap(100_000e9);
    }

    function test_setBridgedSupplyCap_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(admin);
        gateway2.setBridgedSupplyCap(100_000e9);
    }

    function test_setPeer() external {
        address remoteAddr = makeAddr("remote");
        uint32 remoteEid = 30110;
        bytes32 expectedPeer = bytes32(uint256(uint160(remoteAddr)));

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.PeerSet(remoteEid, expectedPeer);

        vm.prank(admin);
        gateway.setPeer(remoteEid, remoteAddr);

        assertEq(
            gateway.peers(remoteEid),
            expectedPeer,
            "Peer should be set to address encoded as bytes32"
        );
    }

    function test_setPeer_zeroAddressClearsPeer() external {
        bytes32 existing = gateway.peers(NONCANONICAL_EID);
        assertTrue(existing != bytes32(0), "Should have peer");

        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, address(0));

        assertEq(gateway.peers(NONCANONICAL_EID), bytes32(0), "Peer should be cleared");
    }

    function test_setPeer_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setPeer(30110, makeAddr("remote"));
    }

    // --- lzClear ---

    function test_lzClear_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.lzClear(Origin(30110, bytes32(uint256(1)), 1), bytes32(0), "");
    }

    // --- lzRetryReceive ---

    function test_lzRetryReceive_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.lzRetryReceive(Origin(30110, bytes32(uint256(1)), 1), bytes32(0), "", "");
    }

    // --- lzSkip ---

    function test_lzSkip_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.lzSkip(30110, bytes32(uint256(1)), 1);
    }

    // --- lzNilify ---

    function test_lzNilify_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.lzNilify(30110, bytes32(uint256(1)), 1, bytes32(0));
    }

    // --- lzBurn ---

    function test_lzBurn_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.lzBurn(30110, bytes32(uint256(1)), 1, bytes32(0));
    }

    function test_setSendLibrary_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setSendLibrary(NONCANONICAL_EID, makeAddr("lib"));
    }

    function test_setReceiveLibrary_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setReceiveLibrary(NONCANONICAL_EID, makeAddr("lib"), 0);
    }

    function test_setLZConfig_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setLZConfig(makeAddr("lib"), bytes("config"));
    }

    function test_setBridgedSupply() external {
        uint256 amount = 5000e9;
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplySet(amount);
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(amount);
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should be set");
    }

    function test_setBridgedSupply_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setBridgedSupply(5000e9);
    }

    function test_setBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.setBridgedSupply(5000e9);
    }
}

contract LZBridgeGatewayTests_V2Receiver is LZBridgeGatewayTestBase {
    function test_allowInitializePath_trueForPeer() external view {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });
        assertTrue(gateway.allowInitializePath(origin), "Should allow init for trusted peer");
    }

    function test_allowInitializePath_falseForNonPeer() external view {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(uint160(user))),
            nonce: 1
        });
        assertFalse(gateway.allowInitializePath(origin), "Should deny init for non-peer");
    }

    function test_allowInitializePath_falseForUnknownEid() external view {
        Origin memory origin = Origin({
            srcEid: 42,
            sender: bytes32(uint256(uint160(address(gateway2)))),
            nonce: 1
        });
        assertFalse(gateway.allowInitializePath(origin), "Should deny init for unknown EID");
    }

    function test_nextNonce_returnsZero() external view {
        assertEq(gateway.nextNonce(NONCANONICAL_EID, bytes32(0)), 0, "nextNonce should return 0");
    }
}

contract LZBridgeGatewayTests_View is LZBridgeGatewayTestBase {
    function test_peers() external view {
        bytes32 peer = gateway.peers(NONCANONICAL_EID);
        bytes32 expected = bytes32(uint256(uint160(address(gateway2))));
        assertEq(peer, expected, "Peer should match non-canonical gateway address");
    }

    function test_peers_returnsZeroForUnknown() external view {
        assertEq(gateway.peers(42), bytes32(0), "Should return zero for unknown EID");
    }

    function test_LZ_ENDPOINT() external view {
        assertEq(gateway.LZ_ENDPOINT(), address(endpoint), "LZ_ENDPOINT should match endpoint");
    }

    function test_IS_CANONICAL() external view {
        assertTrue(gateway.IS_CANONICAL(), "Canonical gateway should return true");
    }

    function test_MINTR() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should match deployed module");
    }

    function test_ohm() external view {
        assertEq(gateway.ohm(), address(ohm), "OHM should match token address");
    }

    function test_facilitator() external view {
        assertEq(gateway.facilitator(), facilitator, "Facilitator should match configured address");
    }

    function test_bridgedSupply() external view {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be zero initially");
    }

    function test_bridgedSupplyCap() external view {
        assertEq(
            gateway.bridgedSupplyCap(),
            SUPPLY_CAP,
            "Bridged supply cap should match setUp value"
        );
    }
}

contract LZBridgeGatewayTests_SupportsInterface is LZBridgeGatewayTestBase {
    function test_supportsInterface_ILZBridgeGateway() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZBridgeGateway).interfaceId),
            "Should support ILZBridgeGateway"
        );
    }

    function test_supportsInterface_ILayerZeroReceiver() external view {
        assertTrue(
            gateway.supportsInterface(type(ILayerZeroReceiver).interfaceId),
            "Should support ILayerZeroReceiver (V2)"
        );
    }

    function test_supportsInterface_IVersioned() external view {
        assertTrue(
            gateway.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_IEnabler() external view {
        assertTrue(
            gateway.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );
    }

    function test_supportsInterface_ERC165() external view {
        assertTrue(gateway.supportsInterface(bytes4(0x01ffc9a7)), "Should support ERC-165");
    }

    function test_supportsInterface_unsupported() external view {
        assertFalse(
            gateway.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

contract LZBridgeGatewayTests_EndToEndViaMock is LZBridgeGatewayTestBase {
    function test_canonicalToNonCanonical_fullFlow() external {
        uint256 amount = 5000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        // Send OHM from canonical (burns OHM, increases bridgedSupply)
        _doBurnAndSend(gateway, NONCANONICAL_EID, recipient, amount);

        // Simulate receiving on non-canonical (mints OHM to recipient)
        _simulateLzReceive(
            gateway2,
            address(endpoint2),
            CANONICAL_EID,
            address(gateway),
            recipient,
            amount
        );

        // Verify: facilitator lost OHM
        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator should have less OHM"
        );

        // Verify: recipient received OHM on non-canonical
        assertEq(
            ohm.balanceOf(recipient),
            amount,
            "Recipient should receive minted OHM on non-canonical"
        );

        // Verify: canonical bridgedSupply increased
        assertEq(gateway.bridgedSupply(), amount, "Canonical bridgedSupply should increase");
    }

    function test_nonCanonicalToCanonical_fullFlow() external {
        // 1. Bridge OHM to non-canonical
        uint256 amount = 5000e9;
        _doBurnAndSend(gateway, NONCANONICAL_EID, recipient, amount);
        _simulateLzReceive(
            gateway2,
            address(endpoint2),
            CANONICAL_EID,
            address(gateway),
            recipient,
            amount
        );

        assertEq(gateway.bridgedSupply(), amount, "Bridged supply after outbound");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should have OHM on non-canonical");

        // 2. Send OHM back from non-canonical to canonical
        vm.prank(admin);
        gateway2.setFacilitator(recipient);

        vm.startPrank(recipient);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(CANONICAL_EID, user, amount, bytes(""));
        vm.deal(recipient, fee);
        gateway2.burnAndSend{value: fee}(
            CANONICAL_EID,
            user,
            amount,
            payable(recipient),
            bytes("")
        );
        vm.stopPrank();

        // Simulate receiving on canonical (mints OHM to user, decreases bridgedSupply)
        _simulateLzReceive(
            gateway,
            address(endpoint),
            NONCANONICAL_EID,
            address(gateway2),
            user,
            amount
        );

        // Verify: user received OHM on canonical
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM on canonical");

        // Verify: canonical bridgedSupply decreased
        assertEq(gateway.bridgedSupply(), 0, "Canonical bridgedSupply should return to 0");
    }

    function test_roundTrip_bridgedSupplyReturnsToZero() external {
        // 1. Send from canonical to non-canonical
        uint256 amount = 3000e9;
        _doBurnAndSend(gateway, NONCANONICAL_EID, recipient, amount);
        _simulateLzReceive(
            gateway2,
            address(endpoint2),
            CANONICAL_EID,
            address(gateway),
            recipient,
            amount
        );
        assertEq(gateway.bridgedSupply(), amount, "Supply after send");

        // 2. Send back from non-canonical to canonical
        vm.prank(admin);
        gateway2.setFacilitator(recipient);

        vm.startPrank(recipient);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(CANONICAL_EID, user, amount, bytes(""));
        vm.deal(recipient, fee);
        gateway2.burnAndSend{value: fee}(
            CANONICAL_EID,
            user,
            amount,
            payable(recipient),
            bytes("")
        );
        vm.stopPrank();

        _simulateLzReceive(
            gateway,
            address(endpoint),
            NONCANONICAL_EID,
            address(gateway2),
            user,
            amount
        );

        // Verify round-trip
        assertEq(
            gateway.bridgedSupply(),
            0,
            "Bridged supply should return to zero after round-trip"
        );
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM after round-trip");
    }
}
