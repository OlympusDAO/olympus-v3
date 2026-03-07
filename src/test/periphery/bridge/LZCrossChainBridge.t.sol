// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {Kernel, Actions, toKeycode, Keycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {LZEndpointMock} from "@layer-zero-endpoint-v1-1.1.0/lzApp/mocks/LZEndpointMock.sol";

contract LZCrossChainBridgeTestBase is Test {
    uint16 constant CANONICAL_LZ_CHAIN_ID = 101;
    uint16 constant NONCANONICAL_LZ_CHAIN_ID = 109;
    uint256 constant SUPPLY_CAP = 100_000e9;

    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;
    LZEndpointMock endpoint;

    // Non-canonical stack for receiving
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;
    LZEndpointMock endpoint2;

    LZCrossChainBridge bridge;
    MockOhm ohm;

    address owner;
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    function setUp() public virtual {
        // Owner is this test contract deployer
        owner = address(this);

        // Deploy mock tokens and endpoints
        ohm = new MockOhm("Olympus", "OHM", 9);
        endpoint = new LZEndpointMock(CANONICAL_LZ_CHAIN_ID);
        endpoint2 = new LZEndpointMock(NONCANONICAL_LZ_CHAIN_ID);

        // Deploy bridge (periphery, owned by this test contract)
        bridge = new LZCrossChainBridge(address(ohm), owner);

        // Deploy canonical stack
        kernel = new Kernel();
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        gateway = new LZBridgeGateway(kernel, address(endpoint), true, address(bridge));

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        rolesAdmin.grantRole("admin", admin);

        // Deploy non-canonical stack for destination
        kernel2 = new Kernel();
        mintr2 = new OlympusMinter(kernel2, address(ohm));
        roles2 = new OlympusRoles(kernel2);
        rolesAdmin2 = new RolesAdmin(kernel2);
        gateway2 = new LZBridgeGateway(kernel2, address(endpoint2), false, address(bridge));

        kernel2.executeAction(Actions.InstallModule, address(mintr2));
        kernel2.executeAction(Actions.InstallModule, address(roles2));
        kernel2.executeAction(Actions.ActivatePolicy, address(rolesAdmin2));
        kernel2.executeAction(Actions.ActivatePolicy, address(gateway2));

        rolesAdmin2.grantRole("admin", admin);

        // Configure gateway
        vm.startPrank(admin);
        gateway.setBridgedSupplyCap(SUPPLY_CAP);

        // Set trusted remotes
        gateway.setTrustedRemote(NONCANONICAL_LZ_CHAIN_ID, address(gateway2));
        gateway2.setTrustedRemote(CANONICAL_LZ_CHAIN_ID, address(gateway));

        // Enable gateways
        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // Link endpoints
        endpoint.setDestLzEndpoint(address(gateway2), address(endpoint2));
        endpoint2.setDestLzEndpoint(address(gateway), address(endpoint));

        // Configure bridge
        bridge.setGateway(address(gateway));
        bridge.enable(bytes(""));

        // Mint OHM to user and approve bridge
        ohm.mint(user, 100_000e9);
        vm.prank(user);
        ohm.approve(address(bridge), type(uint256).max);

        // Fund user for native fees
        vm.deal(user, 100 ether);
    }
}

contract LZCrossChainBridgeTests_Constructor is LZCrossChainBridgeTestBase {
    function test_constructor() external {
        LZCrossChainBridge fresh = new LZCrossChainBridge(address(ohm), address(this));

        assertEq(fresh.OHM(), address(ohm), "OHM should be set");
        assertEq(fresh.owner(), address(this), "Owner should be the deployer");
        assertEq(fresh.gateway(), address(0), "Gateway should default to zero address");
        assertFalse(fresh.isEnabled(), "Bridge should start disabled");
    }

    function test_constructor_revertsIfOhmZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "ohm"
            )
        );
        new LZCrossChainBridge(address(0), address(this));
    }

    function test_constructor_revertsIfOwnerZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "owner"
            )
        );
        new LZCrossChainBridge(address(ohm), address(0));
    }
}

contract LZCrossChainBridgeTests_Version is LZCrossChainBridgeTestBase {
    function test_VERSION() external view {
        (uint8 major, uint8 minor) = bridge.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}

contract LZCrossChainBridgeTests_SendOhm is LZCrossChainBridgeTestBase {
    function test_sendOhm() external {
        uint256 amount = 1000e9;
        uint256 userOhmBefore = ohm.balanceOf(user);
        uint256 userEthBefore = user.balance;
        (uint256 fee, ) = bridge.estimateSendFee(NONCANONICAL_LZ_CHAIN_ID, recipient, amount);

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.Bridged(user, amount, NONCANONICAL_LZ_CHAIN_ID, fee);

        vm.prank(user);
        bridge.sendOhm{value: fee}(NONCANONICAL_LZ_CHAIN_ID, recipient, amount);

        assertEq(ohm.balanceOf(user), userOhmBefore - amount, "User balance should decrease");
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should receive OHM on destination");
        assertEq(user.balance, userEthBefore - fee, "User should spend exactly the native fee");
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
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_LZ_CHAIN_ID, recipient, 1000e9);
    }

    function test_sendOhm_revertsIfAmountZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InsufficientAmount.selector
            )
        );
        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_LZ_CHAIN_ID, recipient, 0);
    }

    function test_sendOhm_revertsIfInsufficientBalance() external {
        // User has 100_000e9, try to send more
        uint256 tooMuch = 200_000e9;
        (uint256 fee, ) = bridge.estimateSendFee(NONCANONICAL_LZ_CHAIN_ID, recipient, tooMuch);

        // Solmate ERC20 reverts with arithmetic underflow on insufficient balance
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user);
        bridge.sendOhm{value: fee}(NONCANONICAL_LZ_CHAIN_ID, recipient, tooMuch);
    }

    function test_sendOhm_revertsIfInsufficientApproval() external {
        // Revoke approval
        vm.prank(user);
        ohm.approve(address(bridge), 0);

        (uint256 fee, ) = bridge.estimateSendFee(NONCANONICAL_LZ_CHAIN_ID, recipient, 1000e9);

        // Solmate ERC20 reverts with arithmetic underflow on insufficient allowance
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user);
        bridge.sendOhm{value: fee}(NONCANONICAL_LZ_CHAIN_ID, recipient, 1000e9);
    }

    function testFuzz_sendOhm_variousAmounts(uint256 amount_) external {
        amount_ = bound(amount_, 1, 100_000e9);

        (uint256 fee, ) = bridge.estimateSendFee(NONCANONICAL_LZ_CHAIN_ID, recipient, amount_);

        uint256 userBalBefore = ohm.balanceOf(user);
        uint256 userEthBefore = user.balance;

        vm.prank(user);
        bridge.sendOhm{value: fee}(NONCANONICAL_LZ_CHAIN_ID, recipient, amount_);

        assertEq(ohm.balanceOf(user), userBalBefore - amount_, "User should lose exactly amount");
        assertEq(ohm.balanceOf(recipient), amount_, "Recipient should receive exactly amount");
        assertEq(user.balance, userEthBefore - fee, "User should spend exactly the native fee");
    }
}

contract LZCrossChainBridgeTests_SetGateway is LZCrossChainBridgeTestBase {
    function test_setGateway() external {
        address newGateway = makeAddr("newGateway");

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.GatewaySet(newGateway);

        bridge.setGateway(newGateway);

        assertEq(bridge.gateway(), newGateway, "Gateway should be updated");
    }

    function test_setGateway_revertsIfNotOwner() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user);
        bridge.setGateway(makeAddr("newGateway"));
    }

    function test_setGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        bridge.setGateway(address(0));
    }
}

contract LZCrossChainBridgeTests_EstimateSendFee is LZCrossChainBridgeTestBase {
    function test_estimateSendFee_proxiesToGateway() external view {
        // Bridge estimate should match gateway estimate
        (uint256 bridgeFee, uint256 bridgeZro) = bridge.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            1000e9
        );
        (uint256 gatewayFee, uint256 gatewayZro) = gateway.estimateSendFee(
            NONCANONICAL_LZ_CHAIN_ID,
            recipient,
            1000e9,
            bytes("")
        );

        assertEq(bridgeFee, gatewayFee, "Native fee should match gateway");
        assertEq(bridgeZro, gatewayZro, "ZRO fee should match gateway");
    }
}

contract LZCrossChainBridgeTests_EnableDisable is LZCrossChainBridgeTestBase {
    function test_enable() external {
        // Disable first
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Should be disabled");

        bridge.enable(bytes(""));
        assertTrue(bridge.isEnabled(), "Should be enabled");
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        bridge.enable(bytes(""));
    }

    function test_enable_revertsIfNotOwner() external {
        bridge.disable(bytes(""));

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user);
        bridge.enable(bytes(""));
    }

    function test_disable() external {
        bridge.disable(bytes(""));
        assertFalse(bridge.isEnabled(), "Should be disabled");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        bridge.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        bridge.disable(bytes(""));
    }

    function test_disable_revertsIfNotOwner() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user);
        bridge.disable(bytes(""));
    }
}

contract LZCrossChainBridgeTests_SupportsInterface is LZCrossChainBridgeTestBase {
    function test_supportsInterface_ILZCrossChainBridge() external view {
        assertTrue(
            bridge.supportsInterface(type(ILZCrossChainBridge).interfaceId),
            "Should support ILZCrossChainBridge"
        );
    }

    function test_supportsInterface_IVersioned() external view {
        assertTrue(
            bridge.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_IEnabler() external view {
        assertTrue(bridge.supportsInterface(type(IEnabler).interfaceId), "Should support IEnabler");
    }

    function test_supportsInterface_ERC165() external view {
        assertTrue(bridge.supportsInterface(bytes4(0x01ffc9a7)), "Should support ERC-165");
    }

    function test_supportsInterface_unsupported() external view {
        assertFalse(
            bridge.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}
