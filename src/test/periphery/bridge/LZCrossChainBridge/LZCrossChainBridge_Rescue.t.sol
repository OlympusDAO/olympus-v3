// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Libraries
import {ERC7528Constants} from "src/libraries/ERC7528Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {RejectingReceiver} from "src/test/bases/Rescueable/RejectingReceiver.sol";

/// @dev Tests for the unified rescue function on LZCrossChainBridge.
///      Passing the EIP-7528 native sentinel as the token rescues the native balance.
contract LZCrossChainBridgeTests_Rescue is LZCrossChainBridgeTestBase {
    MockOhm internal randomToken;
    address internal recoveryRecipient = makeAddr("recoveryRecipient");
    address internal nativeToken;

    function setUp() public override {
        super.setUp();
        randomToken = new MockOhm("Random Token", "RAND", 18);
        nativeToken = ERC7528Constants.NATIVE_ASSET;
    }

    // ========= rescue (ERC20) ========= //

    function test_rescue_givenOwner_transfersBalance() external {
        uint256 amount = 100e18;
        randomToken.mint(address(bridge), amount);

        vm.expectEmit(true, true, true, true, address(randomToken));
        emit IERC20.Transfer(address(bridge), recoveryRecipient, amount);

        bridge.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Recipient should receive rescued tokens"
        );
        assertEq(
            randomToken.balanceOf(address(bridge)),
            0,
            "Bridge should have zero token balance"
        );
    }

    function test_rescue_canRescueOhm() external {
        // Bridge does not hold OHM during normal operation (transferred immediately to gateway).
        // Any OHM balance is from accidental sends and should be recoverable.
        uint256 amount = 1_000e9;
        ohm.mint(address(bridge), amount);

        bridge.rescue(address(ohm), payable(recoveryRecipient));

        assertEq(ohm.balanceOf(recoveryRecipient), amount, "Recipient should receive rescued OHM");
        assertEq(ohm.balanceOf(address(bridge)), 0, "Bridge should have zero OHM balance");
    }

    function test_rescue_givenDisabled_succeeds() external {
        uint256 amount = 100e18;
        randomToken.mint(address(bridge), amount);

        bridge.disable(bytes(""));

        bridge.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Rescue should work while disabled"
        );
    }

    function test_rescue_givenZeroBalance_succeeds() external {
        // No revert on empty balance. Rescue is a rare ops function and sweep semantics are fine
        vm.expectEmit(true, true, true, true, address(randomToken));
        emit IERC20.Transfer(address(bridge), recoveryRecipient, 0);

        bridge.rescue(address(randomToken), payable(recoveryRecipient));

        assertEq(randomToken.balanceOf(recoveryRecipient), 0, "Recipient should receive nothing");
    }

    function testFuzz_rescue_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);
        randomToken.mint(address(bridge), 100e18);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.rescue(address(randomToken), payable(recoveryRecipient));
    }

    function test_rescue_revertsIfRecipientZero() external {
        randomToken.mint(address(bridge), 100e18);

        vm.expectRevert(Errors.InvalidRecipient.selector);
        bridge.rescue(address(randomToken), payable(address(0)));
    }

    // ========= rescue (native, token == EIP-7528 sentinel) ========= //

    function test_rescue_native_givenOwner_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        bridge.rescue(nativeToken, payable(recoveryRecipient));

        assertEq(
            recoveryRecipient.balance,
            recipientBefore + amount,
            "Recipient should receive rescued native"
        );
        assertEq(address(bridge).balance, 0, "Bridge should have zero native balance");
    }

    function test_rescue_native_givenDisabled_succeeds() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        bridge.disable(bytes(""));

        bridge.rescue(nativeToken, payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, amount, "Native rescue should work while disabled");
    }

    function testFuzz_rescue_native_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.rescue(nativeToken, payable(recoveryRecipient));
    }

    function test_rescue_native_revertsIfRecipientZero() external {
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert(Errors.InvalidRecipient.selector);
        bridge.rescue(nativeToken, payable(address(0)));
    }

    function test_rescue_native_givenZeroBalance_succeeds() external {
        bridge.rescue(nativeToken, payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, 0, "Recipient should receive nothing");
    }

    function test_rescue_native_revertsIfTransferFails() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        RejectingReceiver rejector = new RejectingReceiver();

        // OZ Address.sendValue bubbles up the receiver's revert data.
        vm.expectRevert(abi.encodeWithSelector(RejectingReceiver.NoNative.selector));
        bridge.rescue(nativeToken, payable(address(rejector)));
    }
}
