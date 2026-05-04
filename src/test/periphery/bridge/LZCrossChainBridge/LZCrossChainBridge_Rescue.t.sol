// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @dev Tests for the unified rescue function on LZCrossChainBridge.
///      Passing address(0) as the token rescues the native balance.
contract LZCrossChainBridgeTests_Rescue is LZCrossChainBridgeTestBase {
    MockOhm internal randomToken;
    address internal recoveryRecipient = makeAddr("recoveryRecipient");

    function setUp() public override {
        super.setUp();
        randomToken = new MockOhm("Random Token", "RAND", 18);
    }

    // ========= rescue (ERC20) ========= //

    function test_rescue_givenOwner_transfersBalance() external {
        uint256 amount = 100e18;
        randomToken.mint(address(bridge), amount);

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

    function test_rescue_givenOwner_emitsEvent() external {
        uint256 amount = 50e18;
        randomToken.mint(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.Rescued(address(randomToken), recoveryRecipient, amount);

        bridge.rescue(address(randomToken), payable(recoveryRecipient));
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
        // No revert on empty balance. Rescue is a rare ops function and sweep semantics are fine.
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "to"
            )
        );
        bridge.rescue(address(randomToken), payable(address(0)));
    }

    // ========= rescue (native, token == address(0)) ========= //

    function test_rescue_native_givenOwner_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        bridge.rescue(address(0), payable(recoveryRecipient));

        assertEq(
            recoveryRecipient.balance,
            recipientBefore + amount,
            "Recipient should receive rescued native"
        );
        assertEq(address(bridge).balance, 0, "Bridge should have zero native balance");
    }

    function test_rescue_native_givenOwner_emitsEvent() external {
        uint256 amount = 0.5 ether;
        vm.deal(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.Rescued(address(0), recoveryRecipient, amount);

        bridge.rescue(address(0), payable(recoveryRecipient));
    }

    function test_rescue_native_givenDisabled_succeeds() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        bridge.disable(bytes(""));

        bridge.rescue(address(0), payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, amount, "Native rescue should work while disabled");
    }

    function testFuzz_rescue_native_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.rescue(address(0), payable(recoveryRecipient));
    }

    function test_rescue_native_revertsIfRecipientZero() external {
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "to"
            )
        );
        bridge.rescue(address(0), payable(address(0)));
    }

    function test_rescue_native_givenZeroBalance_succeeds() external {
        bridge.rescue(address(0), payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, 0, "Recipient should receive nothing");
    }

    function test_rescue_native_revertsIfTransferFails() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        RejectingReceiver rejector = new RejectingReceiver();

        // OZ Address.sendValue bubbles up the receiver's revert reason via Errors.FailedCall
        // when no return data is provided, otherwise re-reverts with the original data.
        // RejectingReceiver reverts with a string, which propagates as-is.
        vm.expectRevert("RejectingReceiver: no native");
        bridge.rescue(address(0), payable(address(rejector)));
    }
}

/// @dev Contract that rejects native transfers, used to test rescue() native failure paths.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no native");
    }
}
