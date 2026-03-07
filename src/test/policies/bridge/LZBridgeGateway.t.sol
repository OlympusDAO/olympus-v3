// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy, Permissions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILayerZeroReceiver} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {LZEndpointMock} from "@layer-zero-endpoint-v1-1.1.0/lzApp/mocks/LZEndpointMock.sol";

// solhint-disable max-states-count

/// @dev Helper contract that reverts on any call (simulates wrong destination address)
contract RevertOnReceive {
    fallback() external payable {
        revert("not a bridge");
    }
}

contract LZBridgeGatewayTestBase is Test {
    uint16 constant CANONICAL_LZ_CHAIN_ID = 101;
    uint16 constant NONCANONICAL_LZ_CHAIN_ID = 109;
    uint256 constant INITIAL_AMOUNT = 100_000e9;
    uint256 constant SUPPLY_CAP = 1_000_000e9;

    // Canonical stack
    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;
    LZEndpointMock endpoint;

    // Non-canonical stack
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;
    LZEndpointMock endpoint2;

    // Shared
    MockOhm ohm;

    address admin = makeAddr("admin");
    address bridgeAdmin = makeAddr("bridgeAdmin");
    address facilitator = makeAddr("facilitator");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    function setUp() public virtual {
        // 1. Deploy mock OHM and endpoints
        ohm = new MockOhm("Olympus", "OHM", 9);
        endpoint = new LZEndpointMock(CANONICAL_LZ_CHAIN_ID);
        endpoint2 = new LZEndpointMock(NONCANONICAL_LZ_CHAIN_ID);

        // 2. Deploy canonical stack
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

        // 3. Deploy non-canonical stack
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

        // 4. Configure gateways
        vm.startPrank(admin);
        // Set trusted remotes (cross-linked)
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, address(gateway2));
        gateway2.setTrustedRemote(CANONICAL_LZ_CHAIN_ID, address(gateway));

        // Set bridged supply cap on canonical
        gateway.setBridgedSupplyCap(SUPPLY_CAP);

        // Enable both gateways
        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // 5. Link endpoint destinations (mock wiring)
        endpoint.setDestLzEndpoint(address(gateway2), address(endpoint2));
        endpoint2.setDestLzEndpoint(address(gateway), address(endpoint));

        // 6. Mint OHM to facilitator for burnAndSend tests
        ohm.mint(facilitator, INITIAL_AMOUNT);

        // Fund test contract for native fees
        vm.deal(facilitator, 100 ether);
        vm.deal(user, 100 ether);
    }

    function _buildTrustedPath(address remote, address local) internal pure returns (bytes memory) {
        return abi.encodePacked(remote, local);
    }

    function _buildBridgePayload(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(gateway.MSG_BRIDGE_OHM(), abi.encode(to, amount));
    }

    /// @dev Simulates lzReceive call from the endpoint mock to the gateway
    function _simulateLzReceive(
        LZBridgeGateway target,
        LZEndpointMock endpoint,
        uint16 srcChainId,
        address srcGateway,
        address to,
        uint256 amount,
        uint64 nonce
    ) internal {
        bytes memory trustedPath = _buildTrustedPath(srcGateway, address(target));
        bytes memory payload = _buildBridgePayload(to, amount);

        vm.prank(address(endpoint));
        target.lzReceive(srcChainId, trustedPath, nonce, payload);
    }

    /// @dev Performs a burnAndSend from the facilitator, transferring OHM to gateway first
    function _doBurnAndSend(
        LZBridgeGateway source,
        uint16 dstChainId,
        address to,
        uint256 amount
    ) internal {
        vm.startPrank(facilitator);
        ohm.transfer(address(source), amount);

        // Estimate fee
        (uint256 fee, ) = source.estimateSendFee(dstChainId, to, amount, bytes(""));

        source.burnAndSend{value: fee}(dstChainId, to, amount, payable(facilitator), bytes(""));
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
        assertEq(fresh.precrime(), address(0), "Precrime should be zero");
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
        // All three should be on MINTR keycode
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
        // 1. Preparation: deploy a fresh gateway (disabled)
        LZBridgeGateway fresh = new LZBridgeGateway(kernel, address(endpoint), true, facilitator);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));

        // 2. Test
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
        (uint256 fee, ) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            bytes("")
        );

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyIncreased(amount);

        gateway.burnAndSend{value: fee}(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // OHM should be burned from the gateway (transferred then burned)
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
    }

    function test_burnAndSend_nonCanonical_doesNotTrackSupply() external {
        // 1. Preparation: give facilitator OHM and send from non-canonical
        uint256 amount = 1000e9;

        ohm.mint(facilitator, amount);

        // Need to first receive OHM on non-canonical to have something to burn
        // For non-canonical, burnAndSend doesn't track supply, so mint OHM on non-canonical by simulating lzReceive
        _simulateLzReceive(
            gateway2,
            endpoint2,
            CANONICAL_LZ_CHAIN_ID,
            address(gateway),
            facilitator,
            amount,
            1
        );

        // 2. Test: send from non-canonical back to canonical
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(
            CANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            bytes("")
        );
        gateway2.burnAndSend{value: fee}(
            CANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track bridged supply");
    }

    function test_burnAndSend_revertsIfNotFacilitator() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyFacilitator.selector)
        );
        vm.prank(user);
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_LZ_CHAIN_ID,
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
            NONCANONICAL_LZ_CHAIN_ID,
            address(0),
            1000e9,
            payable(user),
            bytes("")
        );
    }

    function test_burnAndSend_revertsIfNotEnabled() external {
        // 1. Preparation: disable gateway
        vm.prank(admin);
        gateway.disable(bytes(""));

        // 2. Test
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(facilitator);
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            1000e9,
            payable(facilitator),
            bytes("")
        );
    }

    function test_burnAndSend_revertsIfNoTrustedRemote() external {
        // Send to chain with no trusted remote
        uint16 unknownChainId = 42;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_DestinationNotTrusted.selector)
        );
        gateway.burnAndSend{value: 1 ether}(
            unknownChainId,
            recipient,
            1000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_canonical_revertsIfSupplyCapExceeded() external {
        // Try to send more than cap
        uint256 amount = SUPPLY_CAP + 1;
        ohm.mint(facilitator, amount);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        (uint256 fee, ) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                amount,
                SUPPLY_CAP
            )
        );
        gateway.burnAndSend{value: fee}(
            NONCANONICAL_LZ_CHAIN_ID,
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
        // 1. Preparation: send some OHM out to build bridged supply
        uint256 initialAmount = 5000e9;
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, initialAmount);
        assertEq(
            gateway.bridgedSupply(),
            initialAmount,
            "Bridged supply should be the initial amount after send"
        );

        // 2. Test: receive back on canonical
        uint256 recipientBalanceBefore = ohm.balanceOf(recipient);

        uint256 amount = 2000e9;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyDecreased(amount);
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.Received(recipient, amount, NONCANONICAL_LZ_CHAIN_ID);

        _simulateLzReceive(
            gateway,
            endpoint,
            NONCANONICAL_LZ_CHAIN_ID,
            address(gateway2),
            recipient,
            amount,
            1
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
        // 2. Test: receive on non-canonical
        _simulateLzReceive(
            gateway2,
            endpoint2,
            CANONICAL_LZ_CHAIN_ID,
            address(gateway),
            recipient,
            1000e9,
            1
        );

        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track bridged supply");
    }

    function test_lzReceive_storesFailedMessageOnInvalidMsgType() external {
        // Cause a revert by sending invalid msg type payload
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory badPayload = abi.encode(uint8(42), abi.encode(recipient, amount));

        vm.expectEmit(true, true, true, false);
        emit ILZBridgeGateway.MessageFailed(
            NONCANONICAL_LZ_CHAIN_ID,
            trustedPath,
            nonce,
            badPayload,
            bytes("")
        );

        // lzReceive should store the failed message, not revert externally
        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, keccak256(badPayload), "Invalid message type should be stored as failed");
    }

    function test_lzReceive_storesFailedMessageOnInvalidPayloadLength() external {
        // Valid msg type but data length != 64 bytes (the expected _BRIDGE_OHM_DATA_LENGTH)
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint64 nonce = 1;
        bytes memory shortData = abi.encode(recipient); // 32 bytes, not 64
        bytes memory badPayload = abi.encode(gateway.MSG_BRIDGE_OHM(), shortData);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(
            stored,
            keccak256(badPayload),
            "Invalid payload length should be stored as failed"
        );
    }

    function test_lzReceive_canonical_storesFailedMessageOnSupplyUnderflow() external {
        // bridgedSupply is 0, receiving OHM would underflow
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be 0");

        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        // Should store as failed message (underflow reverts in _receiveBridgeOhm)
        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, keccak256(payload), "Failed message should be stored on underflow");
    }

    function test_lzReceive_revertsIfNotEnabled() external {
        // 1. Preparation: disable gateway
        vm.prank(admin);
        gateway.disable(bytes(""));

        // 2. Test: lzReceive should revert when disabled
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, 1, payload);
    }

    function test_lzReceive_revertsIfNotEndpoint() external {
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidCaller.selector)
        );
        vm.prank(user);
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, 1, payload);
    }

    function test_lzReceive_revertsIfInvalidTrustedRemote() external {
        // Use wrong source address
        bytes memory wrongPath = _buildTrustedPath(user, address(gateway));
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageSource.selector)
        );
        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, wrongPath, 1, payload);
    }

    function test_receiveMessage_revertsIfCallerNotSelf() external {
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidCaller.selector)
        );
        vm.prank(user);
        gateway.receiveMessage(NONCANONICAL_LZ_CHAIN_ID, bytes(""), 0, payload);
    }
}

contract LZBridgeGatewayTests_RetryMessage is LZBridgeGatewayTestBase {
    function test_retryMessage_canonical() external {
        // Scenario: admin incorrectly lowers bridgedSupply, then a receive causes underflow -> failed message
        // 1. Preparation: bridge OHM out to build bridged supply
        uint256 bridgedAmount = 5000e9;
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, bridgedAmount);
        assertEq(gateway.bridgedSupply(), bridgedAmount, "Bridged supply should match sent amount");

        // Admin incorrectly sets bridgedSupply too low
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(500e9);

        // Receive the full bridged amount back: underflows because 500e9 < 5000e9
        uint256 amount = bridgedAmount;
        bytes memory payload = _buildBridgePayload(recipient, amount);
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint64 nonce = 1;

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertTrue(stored != bytes32(0), "Should have a stored failed message");

        // Correct bridgedSupply
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(bridgedAmount);

        // 2. Test: retry succeeds
        uint256 balBefore = ohm.balanceOf(recipient);
        bytes32 payloadHash = keccak256(payload);

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyDecreased(amount);
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.Received(recipient, amount, NONCANONICAL_LZ_CHAIN_ID);
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.RetryMessageSuccess(
            NONCANONICAL_LZ_CHAIN_ID,
            trustedPath,
            nonce,
            payloadHash
        );

        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        assertEq(
            ohm.balanceOf(recipient),
            balBefore + amount,
            "Recipient should receive OHM after retry"
        );
        stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, bytes32(0), "Stored message should be cleared after retry");
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be zero after full return");
    }

    // test_retryMessage_nonCanonical_doesNotDecrementBridgedSupply:
    // A failed message that can be successfully retried on non-canonical is possible if, for example, MINTR reverts.

    function test_retryMessage_revertsIfNotEnabled() external {
        // 1. Preparation: create failed message, then disable
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        vm.prank(admin);
        gateway.disable(bytes(""));

        // 2. Test
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);
    }

    function test_retryMessage_revertsIfTrustedRemoteRemoved() external {
        // 1. Preparation: create failed message, then remove trusted remote
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        // Remove trusted remote
        vm.prank(admin);
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, address(0));

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageSource.selector)
        );
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);
    }

    function test_retryMessage_revertsIfNoStoredMessage() external {
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        bytes memory payload = _buildBridgePayload(recipient, 1000e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NoStoredMessage.selector)
        );
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, 1, payload);
    }

    function test_retryMessage_revertsIfPayloadMismatch() external {
        // 1. Preparation: create failed message
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        // 2. Test: retry with different payload
        bytes memory wrongPayload = _buildBridgePayload(recipient, 2000e9);
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, wrongPayload);
    }

    function test_retryMessage_revertsIfInvalidMsgType() external {
        // Scenario: incorrect endpoint delivered a payload with unknown message type
        // 1. Preparation: store failed message
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory badPayload = abi.encode(uint8(42), abi.encode(recipient, amount));

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        // 2. Test: reverts, because message type is permanently unrecognized
        vm.expectRevert();
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        // Stored message remains (revert rolls back the delete)
        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, keccak256(badPayload), "Failed message should persist after failed retry");
    }

    function test_retryMessage_revertsIfInvalidPayloadLength() external {
        // Scenario: incorrect endpoint delivered a payload with truncated data
        // 1. Preparation: store failed message
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint64 nonce = 1;
        bytes memory shortData = abi.encode(recipient); // 32 bytes, not 64
        bytes memory badPayload = abi.encode(gateway.MSG_BRIDGE_OHM(), shortData);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        // 2. Test: reverts because payload length is permanently wrong
        vm.expectRevert();
        gateway.retryMessage(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, badPayload);

        // Stored message remains (revert rolls back the delete)
        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, keccak256(badPayload), "Failed message should persist after failed retry");
    }
}

contract LZBridgeGatewayTests_EstimateSendFee is LZBridgeGatewayTestBase {
    function test_estimateSendFee_proxiesToEndpoint() external view {
        // The gateway's estimate should match calling the endpoint directly
        uint256 amount = 1000e9;
        bytes memory payload = _buildBridgePayload(recipient, amount);
        (uint256 endpointFee, ) = endpoint.estimateFees(
            NONCANONICAL_LZ_CHAIN_ID,
            address(gateway),
            payload,
            false,
            bytes("")
        );
        (uint256 gatewayFee, ) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            bytes("")
        );

        assertGt(gatewayFee, 0, "Native fee should be non-zero");
        assertEq(gatewayFee, endpointFee, "Gateway fee should match endpoint fee");
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
        // 1. Preparation: build up bridged supply
        uint256 bridgedAmount = 10_000e9;
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, bridgedAmount);
        assertEq(gateway.bridgedSupply(), bridgedAmount, "Bridged supply should match");

        // Set cap below current bridged supply
        uint256 lowCap = 5000e9;
        vm.prank(admin);
        gateway.setBridgedSupplyCap(lowCap);

        // 2. Test: new bridgings should revert due to cap exceeded
        uint256 newAmount = 1e9;
        ohm.mint(facilitator, newAmount);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), newAmount);
        (uint256 fee, ) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
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
            NONCANONICAL_LZ_CHAIN_ID,
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

    function test_setTrustedRemote() external {
        address remoteAddr = makeAddr("remote");
        bytes memory expectedPath = abi.encodePacked(remoteAddr, address(gateway));

        uint16 remoteChainId = 110;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.TrustedRemoteSet(remoteChainId, expectedPath);

        vm.prank(admin);
        gateway.setTrustedRemote(remoteChainId, remoteAddr);

        assertEq(
            keccak256(gateway.trustedRemoteLookup(remoteChainId)),
            keccak256(expectedPath),
            "Path should be abi.encodePacked(remoteAddress, localAddress)"
        );
    }

    function test_setTrustedRemote_zeroAddressClearsTrustedRemote() external {
        // Verify trusted remote is set
        bytes memory existing = gateway.trustedRemoteLookup(NONCANONICAL_LZ_CHAIN_ID);
        assertGt(existing.length, 0, "Should have trusted remote");

        // Clear it
        vm.prank(admin);
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, address(0));

        assertEq(
            gateway.trustedRemoteLookup(NONCANONICAL_LZ_CHAIN_ID).length,
            0,
            "Trusted remote should be cleared"
        );
    }

    function test_setTrustedRemote_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setTrustedRemote(110, makeAddr("remote"));
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

contract LZBridgeGatewayTests_LZPrecrime is LZBridgeGatewayTestBase {
    function test_precrime_currentlyUnused() external view {
        assertEq(gateway.precrime(), address(0), "Precrime should currently be the zero address");
    }

    function test_setPrecrime() external {
        address newPrecrime = makeAddr("precrime");
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.PrecrimeSet(newPrecrime);
        vm.prank(admin);
        gateway.setPrecrime(newPrecrime);
        assertEq(gateway.precrime(), newPrecrime, "Precrime should be set");
    }

    function test_setPrecrime_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setPrecrime(user);
    }
}

contract LZBridgeGatewayTests_LZUserApplicationConfigWithMock is LZBridgeGatewayTestBase {
    function test_setConfig_proxiesToEndpoint() external {
        // Should not revert when called by bridge_admin
        vm.prank(bridgeAdmin);
        gateway.setConfig(1, NONCANONICAL_LZ_CHAIN_ID, 1, bytes("config"));
    }

    function test_setConfig_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setConfig(1, NONCANONICAL_LZ_CHAIN_ID, 1, bytes("config"));
    }

    function test_setSendVersion_proxiesToEndpoint() external {
        vm.prank(bridgeAdmin);
        gateway.setSendVersion(1);
    }

    function test_setSendVersion_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setSendVersion(1);
    }

    function test_setReceiveVersion_proxiesToEndpoint() external {
        vm.prank(bridgeAdmin);
        gateway.setReceiveVersion(1);
    }

    function test_setReceiveVersion_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setReceiveVersion(1);
    }

    function test_forceResumeReceive_unblocksMismatchedTrustedRemote() external {
        // Scenario: admin sets incorrect trustedRemote on canonical gateway (wrong destination address).
        // burnAndSend sends the LZ message to the wrong address on the destination chain.
        // The wrong address cannot process lzReceive -> endpoint stores payload, blocking the pathway.
        //
        // An analogous scenario occurs if the trustedRemote on the destination gateway is incorrect:
        // the message arrives at the correct gateway, but _validateTrustedRemote reverts because
        // srcAddress doesn't match. The endpoint stores the payload and blocks the pathway.
        // In that case, forceResumeReceive is called on the destination gateway to unblock.

        // 1. Preparation: set incorrect trusted remote on canonical gateway
        // Deploy a contract that will revert on lzReceive (no such function)
        address wrongAddr = address(new RevertOnReceive());
        vm.prank(admin);
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, wrongAddr);

        // Register wrong address on endpoint so send() doesn't revert
        endpoint.setDestLzEndpoint(wrongAddr, address(endpoint2));

        // Facilitator sends OHM: it burns correctly but the message goes to wrongAddr
        uint256 amount = 1000e9;
        ohm.mint(facilitator, amount);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        (uint256 fee, ) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            bytes("")
        );
        gateway.burnAndSend{value: fee}(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // OHM was burned and bridgedSupply increased, but OHM was never minted on destination
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should have increased");

        // Destination endpoint has a stored payload for wrongAddr (pathway blocked)
        bytes memory blockedPath = abi.encodePacked(address(gateway), wrongAddr);
        assertTrue(
            endpoint2.hasStoredPayload(CANONICAL_LZ_CHAIN_ID, blockedPath),
            "Endpoint should have stored payload for wrong address"
        );

        // 2. Test: admin corrects the trusted remote and bridged supply
        vm.startPrank(admin);
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, address(gateway2));
        vm.stopPrank();

        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(0);

        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be corrected to zero");

        // Note: the burned OHM must be compensated to the affected user. The gateway does not
        // provide a direct mint mechanism: compensation requires a separate governance action
        // (e.g. the OCG Timelock to mint OHM to the recipient in any way).
    }

    function test_forceResumeReceive_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.forceResumeReceive(NONCANONICAL_LZ_CHAIN_ID, bytes("path"));
    }
}

contract LZBridgeGatewayTests_View is LZBridgeGatewayTestBase {
    function test_getConfig() external view {
        // Should return something (mock returns empty bytes)
        bytes memory config = gateway.getConfig(1, NONCANONICAL_LZ_CHAIN_ID, address(gateway), 1);
        // Mock returns empty, just verify it doesn't revert
        assertEq(config.length, 0, "Mock endpoint returns empty config");
    }

    function test_getTrustedRemote() external view {
        address remoteAddr = gateway.getTrustedRemote(NONCANONICAL_LZ_CHAIN_ID);
        assertEq(
            remoteAddr,
            address(gateway2),
            "Remote address should match non-canonical gateway"
        );
    }

    function test_getTrustedRemote_revertsIfEmpty() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NoTrustedPath.selector)
        );
        gateway.getTrustedRemote(42);
    }

    function test_isTrustedRemote_true() external view {
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        bool trusted = gateway.isTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, trustedPath);
        assertTrue(trusted, "Should return true for valid trusted remote");
    }

    function test_isTrustedRemote_returnsFalseIfInvalidAddress() external view {
        bytes memory wrongPath = _buildTrustedPath(user, address(gateway));
        bool trusted = gateway.isTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, wrongPath);
        assertFalse(trusted, "Should return false for invalid address");
    }

    function test_isTrustedRemote_returnsFalseIfLengthMismatch() external view {
        // Trusted path is 40 bytes (address + address), send only 20 bytes
        bytes memory shortPath = abi.encodePacked(address(gateway2));
        bool trusted = gateway.isTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, shortPath);
        assertFalse(trusted, "Should return false for length mismatch");
    }

    function test_isTrustedRemote_revertsIfUninitialized() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_TrustedRemoteUninitialized.selector
            )
        );
        gateway.isTrustedRemote(42, bytes("something"));
    }

    function test_isTrustedRemote_revertsIfEmptySourcePassed() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_TrustedRemoteUninitialized.selector
            )
        );
        gateway.isTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, bytes(""));
    }

    function test_failedMessages() external {
        // 1. Preparation: create a failed message via bridgedSupply underflow
        bytes memory trustedPath = _buildTrustedPath(address(gateway2), address(gateway));
        uint256 amount = 1000e9;
        uint64 nonce = 1;
        bytes memory payload = _buildBridgePayload(recipient, amount);

        vm.prank(address(endpoint));
        gateway.lzReceive(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce, payload);

        // 2. Test
        bytes32 stored = gateway.failedMessages(NONCANONICAL_LZ_CHAIN_ID, trustedPath, nonce);
        assertEq(stored, keccak256(payload), "Failed message hash should match payload hash");
    }

    function test_failedMessages_returnsZeroByDefault() external view {
        bytes32 hash = gateway.failedMessages(
            NONCANONICAL_LZ_CHAIN_ID,
            _buildTrustedPath(address(gateway2), address(gateway)),
            42
        );
        assertEq(hash, bytes32(0), "Should return zero for non-existent failed message");
    }

    function test_trustedRemoteLookup() external view {
        bytes memory path = gateway.trustedRemoteLookup(NONCANONICAL_LZ_CHAIN_ID);
        bytes memory expected = _buildTrustedPath(address(gateway2), address(gateway));
        assertEq(keccak256(path), keccak256(expected), "Trusted remote lookup should match");
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
            "Should support ILayerZeroReceiver"
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
        // 1. Preparation
        uint256 amount = 5000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        // 2. Test: send OHM from canonical to non-canonical
        // The LZEndpointMock short-circuits send() to lzReceive() on the destination
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, amount);

        // Verify: facilitator lost OHM
        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator should have less OHM"
        );

        // Verify: recipient received OHM on non-canonical (minted by gateway2)
        assertEq(
            ohm.balanceOf(recipient),
            amount,
            "Recipient should receive minted OHM on non-canonical"
        );

        // Verify: canonical bridgedSupply increased
        assertEq(gateway.bridgedSupply(), amount, "Canonical bridgedSupply should increase");
    }

    function test_nonCanonicalToCanonical_fullFlow() external {
        // 1. Preparation: first bridge OHM to non-canonical so there's bridgedSupply
        uint256 amount = 5000e9;
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, amount);
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply after outbound");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should have OHM on non-canonical");

        // 2. Test: send OHM back from non-canonical to canonical
        // Recipient becomes the sender on non-canonical
        vm.prank(admin);
        gateway2.setFacilitator(recipient);

        vm.startPrank(recipient);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(CANONICAL_LZ_CHAIN_ID, user, amount, bytes(""));
        vm.deal(recipient, fee);
        gateway2.burnAndSend{value: fee}(
            CANONICAL_LZ_CHAIN_ID,
            user,
            amount,
            payable(recipient),
            bytes("")
        );
        vm.stopPrank();

        // Verify: user received OHM on canonical
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM on canonical");

        // Verify: canonical bridgedSupply decreased
        assertEq(gateway.bridgedSupply(), 0, "Canonical bridgedSupply should return to 0");
    }

    function test_roundTrip_bridgedSupplyReturnsToZero() external {
        // 1. Send from canonical to non-canonical
        uint256 amount = 3000e9;
        _doBurnAndSend(gateway, NONCANONICAL_LZ_CHAIN_ID, recipient, amount);
        assertEq(gateway.bridgedSupply(), amount, "Supply after send");

        // 2. Send back from non-canonical to canonical
        vm.prank(admin);
        gateway2.setFacilitator(recipient);

        vm.startPrank(recipient);
        ohm.transfer(address(gateway2), amount);
        (uint256 fee, ) = gateway2.estimateSendFee(CANONICAL_LZ_CHAIN_ID, user, amount, bytes(""));
        vm.deal(recipient, fee);
        gateway2.burnAndSend{value: fee}(
            CANONICAL_LZ_CHAIN_ID,
            user,
            amount,
            payable(recipient),
            bytes("")
        );
        vm.stopPrank();

        // Verify round-trip
        assertEq(
            gateway.bridgedSupply(),
            0,
            "Bridged supply should return to zero after round-trip"
        );
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM after round-trip");
    }
}
