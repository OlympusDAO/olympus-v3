// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Libraries
import {ERC7528Constants} from "src/libraries/ERC7528Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockRescueable} from "src/test/bases/Rescueable/MockRescueable.sol";
import {RejectingReceiver} from "src/test/bases/Rescueable/RejectingReceiver.sol";

/// @dev Unit tests for the `Rescueable` abstract contract.
///      A harness (`MockRescueable`) exposes the parent's logic with a toggleable auth
///      check so we can exercise `rescue()` without coupling to a specific permission
///      model.
contract RescueableTests is Test {
    MockRescueable internal target;
    MockERC20 internal token;
    address internal recipient = makeAddr("recipient");

    address internal nativeSentinel = ERC7528Constants.NATIVE_ASSET;

    function setUp() public {
        target = new MockRescueable();
        token = new MockERC20("Token", "TKN", 18);
    }

    // ========= rescue (ERC20) ========= //

    function test_rescue_erc20_transfersBalance() external {
        uint256 amount = 100e18;
        token.mint(address(target), amount);

        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(address(target), recipient, amount);

        target.rescue(address(token), payable(recipient));

        assertEq(token.balanceOf(recipient), amount, "Recipient receives tokens");
        assertEq(token.balanceOf(address(target)), 0, "Target balance is zero");
    }

    function test_rescue_erc20_zeroBalance_succeeds() external {
        // Sweep semantics: zero balance is a no-op, not a revert
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(address(target), recipient, 0);

        target.rescue(address(token), payable(recipient));

        assertEq(token.balanceOf(recipient), 0, "Recipient receives nothing");
    }

    // ========= rescue (native) ========= //

    function test_rescue_native_transfersBalance() external {
        uint256 amount = 1 ether;
        vm.deal(address(target), amount);

        target.rescue(nativeSentinel, payable(recipient));

        assertEq(recipient.balance, amount, "Recipient receives native");
        assertEq(address(target).balance, 0, "Target balance is zero");
    }

    function test_rescue_native_zeroBalance_succeeds() external {
        target.rescue(nativeSentinel, payable(recipient));

        assertEq(recipient.balance, 0, "Recipient receives nothing");
    }

    function test_rescue_native_revertsIfTransferFails() external {
        uint256 amount = 1 ether;
        vm.deal(address(target), amount);

        RejectingReceiver rejector = new RejectingReceiver();

        // OZ Address.sendValue propagates the receiver's revert data.
        vm.expectRevert(abi.encodeWithSelector(RejectingReceiver.NoNative.selector));
        target.rescue(nativeSentinel, payable(address(rejector)));
    }

    // ========= rescue (auth) ========= //

    function test_rescue_revertsIfAuthFails_erc20() external {
        target.setAuthShouldRevert(true);
        token.mint(address(target), 100e18);

        vm.expectRevert(MockRescueable.MockRescueable_Unauthorized.selector);
        target.rescue(address(token), payable(recipient));
    }

    function test_rescue_revertsIfAuthFails_native() external {
        target.setAuthShouldRevert(true);
        vm.deal(address(target), 1 ether);

        vm.expectRevert(MockRescueable.MockRescueable_Unauthorized.selector);
        target.rescue(nativeSentinel, payable(recipient));
    }

    function test_rescue_authChecked_beforeRecipientValidation() external {
        // Auth is the first check, so even an invalid recipient should not surface its
        // error if the caller is not authorised.
        target.setAuthShouldRevert(true);

        vm.expectRevert(MockRescueable.MockRescueable_Unauthorized.selector);
        target.rescue(address(token), payable(address(0)));
    }

    // ========= rescue (recipient validation) ========= //

    function test_rescue_revertsIfRecipientZero_erc20() external {
        token.mint(address(target), 100e18);

        vm.expectRevert(Errors.InvalidRecipient.selector);
        target.rescue(address(token), payable(address(0)));
    }

    function test_rescue_revertsIfRecipientZero_native() external {
        vm.deal(address(target), 1 ether);

        vm.expectRevert(Errors.InvalidRecipient.selector);
        target.rescue(nativeSentinel, payable(address(0)));
    }

    // ========= rescue (token semantics) ========= //

    function test_rescue_erc20_doesNotTouchNativeBalance() external {
        // Rescuing an ERC20 must not move the native balance, even if both are non-zero.
        uint256 tokenAmount = 100e18;
        uint256 nativeAmount = 1 ether;
        token.mint(address(target), tokenAmount);
        vm.deal(address(target), nativeAmount);

        target.rescue(address(token), payable(recipient));

        assertEq(recipient.balance, 0, "Recipient should not receive native");
        assertEq(address(target).balance, nativeAmount, "Target retains native balance");
        assertEq(token.balanceOf(recipient), tokenAmount, "Recipient receives token balance");
    }

    function test_rescue_native_doesNotTouchTokenBalance() external {
        uint256 tokenAmount = 100e18;
        uint256 nativeAmount = 1 ether;
        token.mint(address(target), tokenAmount);
        vm.deal(address(target), nativeAmount);

        target.rescue(nativeSentinel, payable(recipient));

        assertEq(token.balanceOf(recipient), 0, "Recipient should not receive tokens");
        assertEq(token.balanceOf(address(target)), tokenAmount, "Target retains token balance");
        assertEq(recipient.balance, nativeAmount, "Recipient receives native balance");
    }
}
