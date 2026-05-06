// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IRescuable} from "../../../../bases/interfaces/IRescuable.sol";

// Contracts
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

/// @dev Tests for the unified rescue function on LZBridgeGateway.
///      Passing the EIP-7528 native sentinel (`NATIVE_TOKEN`) as the token rescues the native (ETH) balance.
///      Rescue is restricted to the manager or admin role.
contract LZBridgeGatewayTests_Rescue is LZBridgeGatewayTestBase {
    MockOhm internal randomToken;
    address internal manager = makeAddr("manager");
    address internal recoveryRecipient = makeAddr("recoveryRecipient");
    address internal nativeToken;

    function setUp() public override {
        super.setUp();
        randomToken = new MockOhm("Random Token", "RAND", 18);
        rolesAdmin.grantRole("manager", manager);
        nativeToken = gateway.NATIVE_TOKEN();
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
        emit IRescuable.Rescued(address(randomToken), recoveryRecipient, amount);

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

    function testFuzz_rescue_revertsIfNotManagerOrAdmin(address caller_) external {
        vm.assume(caller_ != manager && caller_ != admin);
        randomToken.mint(address(gateway), 100e18);

        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));
    }

    function test_rescue_givenAdmin_transfersBalance() external {
        // Admin role is also sufficient — rescue allows manager or admin.
        uint256 amount = 100e18;
        randomToken.mint(address(gateway), amount);

        vm.prank(admin);
        gateway.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Recipient should receive rescued tokens"
        );
    }

    function test_rescue_revertsIfRecipientZero() external {
        randomToken.mint(address(gateway), 100e18);

        vm.expectRevert(IRescuable.Rescuable_InvalidRecipient.selector);
        vm.prank(manager);
        gateway.rescue(address(randomToken), payable(address(0)));
    }

    // ========= rescue (native — token == NATIVE_TOKEN sentinel) ========= //

    function test_rescue_native_givenManager_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        vm.prank(manager);
        gateway.rescue(nativeToken, payable(recoveryRecipient));

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
        emit IRescuable.Rescued(nativeToken, recoveryRecipient, amount);

        vm.prank(manager);
        gateway.rescue(nativeToken, payable(recoveryRecipient));
    }

    function test_rescue_native_givenDisabled_succeeds() external {
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.prank(manager);
        gateway.rescue(nativeToken, payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, amount, "Native rescue should work while disabled");
    }

    function testFuzz_rescue_native_revertsIfNotManagerOrAdmin(address caller_) external {
        vm.assume(caller_ != manager && caller_ != admin);
        vm.deal(address(gateway), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.rescue(nativeToken, payable(recoveryRecipient));
    }

    function test_rescue_native_givenAdmin_transfersBalance() external {
        // Admin role is also sufficient — rescue allows manager or admin.
        uint256 amount = 1 ether;
        vm.deal(address(gateway), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        vm.prank(admin);
        gateway.rescue(nativeToken, payable(recoveryRecipient));

        assertEq(
            recoveryRecipient.balance,
            recipientBefore + amount,
            "Recipient should receive rescued native"
        );
    }

    function test_rescue_native_revertsIfRecipientZero() external {
        vm.deal(address(gateway), 1 ether);

        vm.expectRevert(IRescuable.Rescuable_InvalidRecipient.selector);
        vm.prank(manager);
        gateway.rescue(nativeToken, payable(address(0)));
    }

    function test_rescue_native_givenZeroBalance_succeeds() external {
        vm.prank(manager);
        gateway.rescue(nativeToken, payable(recoveryRecipient));

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
        gateway.rescue(nativeToken, payable(address(rejector)));
    }
}

/// @dev Contract that rejects ETH transfers, used to test rescue() native failure paths.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no eth");
    }
}
