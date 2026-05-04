// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @dev Tests for the unified rescue function on LZBridgeGateway.
///      Passing address(0) as the token rescues the native (ETH) balance.
/// @dev Rescue is restricted to the manager role (the DAO multisig).
contract LZBridgeGatewayTests_Rescue is LZBridgeGatewayTestBase {
    MockOhm internal randomToken;
    address internal manager = makeAddr("manager");
    address internal recoveryRecipient = makeAddr("recoveryRecipient");

    function setUp() public override {
        super.setUp();
        randomToken = new MockOhm("Random Token", "RAND", 18);
        rolesAdmin.grantRole("manager", manager);
    }

    // ========= rescue (ERC20) ========= //

    function test_rescue_givenManager_transfersBalance() external {
        uint256 amount = 100e18;
        randomToken.mint(address(gateway), amount);

        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Recipient should receive rescued tokens"
        );
        assertEq(
            randomToken.balanceOf(address(gateway)),
            0,
            "Gateway should have zero token balance"
        );
    }

    function test_rescue_givenManager_emitsEvent() external {
        uint256 amount = 50e18;
        randomToken.mint(address(gateway), amount);

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.Rescued(address(randomToken), recoveryRecipient, amount);

        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));
    }

    function test_rescue_canRescueOhm() external {
        // Gateway shouldn't normally hold OHM, but if it does (accidental send), it must be recoverable.
        uint256 amount = 1_000e9;
        ohm.mint(address(gateway), amount);

        vm.prank(manager);
        gateway.rescue(address(ohm), payable(recoveryRecipient));

        assertEq(ohm.balanceOf(recoveryRecipient), amount, "Recipient should receive rescued OHM");
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have zero OHM balance");
    }

    function test_rescue_givenDisabled_succeeds() external {
        uint256 amount = 100e18;
        randomToken.mint(address(gateway), amount);

        // Disable gateway first (admin role required)
        vm.prank(admin);
        gateway.disable(bytes(""));

        // Rescue should still work while disabled
        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Rescue should work while disabled"
        );
    }

    function test_rescue_givenZeroBalance_succeeds() external {
        // No revert on empty balance — rescue is a rare ops function and a sweep semantics is fine.
        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(randomToken.balanceOf(recoveryRecipient), 0, "Recipient should receive nothing");
    }

    function testFuzz_rescue_revertsIfNotManager(address caller_) external {
        vm.assume(caller_ != manager);
        randomToken.mint(address(gateway), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(caller_);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));
    }

    function test_rescue_revertsIfAdminNotManager() external {
        // Admin role is NOT sufficient — rescue is manager-only.
        randomToken.mint(address(gateway), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(admin);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));
    }

    function test_rescue_revertsIfRecipientZero() external {
        randomToken.mint(address(gateway), 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(address(0)));
    }

    // ========= rescue (native — token == address(0)) ========= //

    function test_rescue_native_givenManager_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        vm.prank(manager);
        gateway.rescue(address(0), payable(recoveryRecipient));

        assertEq(
            recoveryRecipient.balance,
            recipientBefore + amount,
            "Recipient should receive rescued native"
        );
        assertEq(address(gateway).balance, 0, "Gateway should have zero native balance");
    }

    function test_rescue_native_givenManager_emitsEvent() external {
        uint256 amount = 0.5 ether;
        vm.deal(address(gateway), amount);

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.Rescued(address(0), recoveryRecipient, amount);

        vm.prank(manager);
        gateway.rescue(address(0), payable(recoveryRecipient));
    }

    function test_rescue_native_givenDisabled_succeeds() external {
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.prank(manager);
        gateway.rescue(address(0), payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, amount, "Native rescue should work while disabled");
    }

    function testFuzz_rescue_native_revertsIfNotManager(address caller_) external {
        vm.assume(caller_ != manager);
        vm.deal(address(gateway), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(caller_);
        gateway.rescue(address(0), payable(recoveryRecipient));
    }

    function test_rescue_native_revertsIfAdminNotManager() external {
        // Admin role is NOT sufficient — rescue is manager-only.
        vm.deal(address(gateway), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, MANAGER_ROLE));
        vm.prank(admin);
        gateway.rescue(address(0), payable(recoveryRecipient));
    }

    function test_rescue_native_revertsIfRecipientZero() external {
        vm.deal(address(gateway), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        vm.prank(manager);
        gateway.rescue(address(0), payable(address(0)));
    }

    function test_rescue_native_givenZeroBalance_succeeds() external {
        vm.prank(manager);
        gateway.rescue(address(0), payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, 0, "Recipient should receive nothing");
    }

    function test_rescue_native_revertsIfTransferFails() external {
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        // Deploy a contract that rejects ETH and use it as recipient
        RejectingReceiver rejector = new RejectingReceiver();

        // OZ Address.sendValue bubbles up the receiver's revert string.
        vm.expectRevert("RejectingReceiver: no eth");
        vm.prank(manager);
        gateway.rescue(address(0), payable(address(rejector)));
    }
}

/// @dev Contract that rejects ETH transfers, used to test rescue() native failure paths.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no eth");
    }
}
