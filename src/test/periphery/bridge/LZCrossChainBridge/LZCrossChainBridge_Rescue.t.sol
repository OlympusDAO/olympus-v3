// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @dev Tests for the rescue and rescueNative functions on LZCrossChainBridge.
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

        bridge.rescue(address(randomToken), recoveryRecipient);

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

        bridge.rescue(address(randomToken), recoveryRecipient);
    }

    function test_rescue_canRescueOhm() external {
        // Bridge does not hold OHM during normal operation (transferred immediately to gateway).
        // Any OHM balance is from accidental sends and should be recoverable.
        uint256 amount = 1_000e9;
        ohm.mint(address(bridge), amount);

        bridge.rescue(address(ohm), recoveryRecipient);

        assertEq(ohm.balanceOf(recoveryRecipient), amount, "Recipient should receive rescued OHM");
        assertEq(ohm.balanceOf(address(bridge)), 0, "Bridge should have zero OHM balance");
    }

    function test_rescue_givenDisabled_succeeds() external {
        uint256 amount = 100e18;
        randomToken.mint(address(bridge), amount);

        bridge.disable(bytes(""));

        bridge.rescue(address(randomToken), recoveryRecipient);

        assertEq(
            randomToken.balanceOf(recoveryRecipient),
            amount,
            "Rescue should work while disabled"
        );
    }

    function testFuzz_rescue_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);
        randomToken.mint(address(bridge), 100e18);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.rescue(address(randomToken), recoveryRecipient);
    }

    function test_rescue_revertsIfTokenZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "token"
            )
        );
        bridge.rescue(address(0), recoveryRecipient);
    }

    function test_rescue_revertsIfRecipientZero() external {
        randomToken.mint(address(bridge), 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "to"
            )
        );
        bridge.rescue(address(randomToken), address(0));
    }

    function test_rescue_revertsIfZeroBalance() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZCrossChainBridge.LZCrossChainBridge_NothingToRescue.selector)
        );
        bridge.rescue(address(randomToken), recoveryRecipient);
    }

    // ========= rescueNative (ETH) ========= //

    function test_rescueNative_givenOwner_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        uint256 recipientBefore = recoveryRecipient.balance;

        bridge.rescueNative(payable(recoveryRecipient));

        assertEq(
            recoveryRecipient.balance,
            recipientBefore + amount,
            "Recipient should receive rescued native"
        );
        assertEq(address(bridge).balance, 0, "Bridge should have zero native balance");
    }

    function test_rescueNative_givenOwner_emitsEvent() external {
        uint256 amount = 0.5 ether;
        vm.deal(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.NativeRescued(recoveryRecipient, amount);

        bridge.rescueNative(payable(recoveryRecipient));
    }

    function test_rescueNative_givenDisabled_succeeds() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        bridge.disable(bytes(""));

        bridge.rescueNative(payable(recoveryRecipient));

        assertEq(recoveryRecipient.balance, amount, "Native rescue should work while disabled");
    }

    function testFuzz_rescueNative_revertsIfNotOwner(address caller_) external {
        vm.assume(caller_ != owner);
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        bridge.rescueNative(payable(recoveryRecipient));
    }

    function test_rescueNative_revertsIfRecipientZero() external {
        vm.deal(address(bridge), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "to"
            )
        );
        bridge.rescueNative(payable(address(0)));
    }

    function test_rescueNative_revertsIfZeroBalance() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZCrossChainBridge.LZCrossChainBridge_NothingToRescue.selector)
        );
        bridge.rescueNative(payable(recoveryRecipient));
    }

    function test_rescueNative_revertsIfTransferFails() external {
        uint256 amount = 1 ether;
        vm.deal(address(bridge), amount);

        RejectingReceiver rejector = new RejectingReceiver();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_NativeTransferFailed.selector,
                address(rejector),
                amount
            )
        );
        bridge.rescueNative(payable(address(rejector)));
    }
}

/// @dev Contract that rejects ETH transfers, used to test rescueNative failure paths.
contract RejectingReceiver {
    receive() external payable {
        revert("RejectingReceiver: no eth");
    }
}
