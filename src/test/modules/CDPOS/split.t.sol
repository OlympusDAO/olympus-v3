// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {Module} from "src/Kernel.sol";

contract SplitCDPOSTest is CDPOSTest {
    event PositionSplit(
        uint256 indexed positionId,
        uint256 indexed newPositionId,
        address indexed convertibleDepositToken,
        uint256 amount,
        address to,
        bool wrap
    );

    // when the position does not exist
    //  [X] it reverts
    // when the caller is not the owner of the position
    //  [X] it reverts
    // when the caller is a permissioned address
    //  [X] it reverts
    // when the amount is 0
    //  [X] it reverts
    // when the amount is greater than the remaining deposit
    //  [X] it reverts
    // when the to_ address is the zero address
    //  [X] it reverts
    // when wrap is true
    //  [X] it wraps the new position
    // given the existing position is wrapped
    //  [X] the new position is unwrapped
    // when the to_ address is the same as the owner
    //  [X] it creates the new position
    // [X] it creates a new position with the new amount, new owner and the same expiry
    // [X] it updates the remaining deposit of the original position
    // [X] it emits a PositionSplit event

    function test_invalidPositionId_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 0));

        // Call function
        _splitPosition(address(this), 0, 1e18, address(0x1), false);
    }

    function test_callerIsNotOwner_reverts()
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_NotOwner.selector, 0));

        // Call function
        _splitPosition(address(0x1), 0, REMAINING_DEPOSIT, address(0x1), false);
    }

    function test_callerIsPermissioned_reverts()
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_NotOwner.selector, 0));

        // Call function
        _splitPosition(godmode, 0, REMAINING_DEPOSIT, address(0x1), false);
    }

    function test_amountIsZero_reverts()
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "amount"));

        // Call function
        _splitPosition(address(this), 0, 0, address(0x1), false);
    }

    function test_amountIsGreaterThanRemainingDeposit_reverts(
        uint256 amount_
    )
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        uint256 amount = bound(amount_, REMAINING_DEPOSIT + 1, REMAINING_DEPOSIT + 2e18);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "amount"));

        // Call function
        _splitPosition(address(this), 0, amount, address(0x1), false);
    }

    function test_recipientIsZeroAddress_reverts()
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "to"));

        // Call function
        _splitPosition(address(this), 0, REMAINING_DEPOSIT, address(0), false);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        uint256 amount = bound(amount_, 1, REMAINING_DEPOSIT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionSplit(0, 1, convertibleDepositToken, amount, address(0x1), false);

        // Call function
        _splitPosition(address(this), 0, amount, address(0x1), false);

        // Assert old position
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT - amount,
            CONVERSION_PRICE,
            EXPIRY,
            false
        );

        // Assert new position
        _assertPosition(1, address(0x1), amount, CONVERSION_PRICE, EXPIRY, false);

        // ERC721 balances are not updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Owner(0, address(this), false);
        _assertERC721Balance(address(0x1), 0);
        _assertERC721Owner(1, address(0x1), false);

        // Assert the ownership is updated
        _assertUserPosition(address(this), 0, 1);
        _assertUserPosition(address(0x1), 1, 1);
    }

    function test_sameRecipient(
        uint256 amount_
    )
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        uint256 amount = bound(amount_, 1, REMAINING_DEPOSIT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionSplit(0, 1, convertibleDepositToken, amount, address(this), false);

        // Call function
        _splitPosition(address(this), 0, amount, address(this), false);

        // Assert old position
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT - amount,
            CONVERSION_PRICE,
            EXPIRY,
            false
        );

        // Assert new position
        _assertPosition(1, address(this), amount, CONVERSION_PRICE, EXPIRY, false);

        // ERC721 balances are not updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Owner(0, address(this), false);
        _assertERC721Owner(1, address(this), false);

        // Assert the ownership is updated
        _assertUserPosition(address(this), 0, 2);
        _assertUserPosition(address(this), 1, 2);
    }

    function test_oldPositionIsWrapped(
        uint256 amount_
    )
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, true)
    {
        uint256 amount = bound(amount_, 1, REMAINING_DEPOSIT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionSplit(0, 1, convertibleDepositToken, amount, address(0x1), false);

        // Call function
        _splitPosition(address(this), 0, amount, address(0x1), false);

        // Assert old position
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT - amount,
            CONVERSION_PRICE,
            EXPIRY,
            true
        );

        // Assert new position
        _assertPosition(1, address(0x1), amount, CONVERSION_PRICE, EXPIRY, false);

        // ERC721 balances are not updated
        _assertERC721Balance(address(this), 1);
        _assertERC721Owner(0, address(this), true);
        _assertERC721Balance(address(0x1), 0);
        _assertERC721Owner(1, address(0x1), false);

        // Assert the ownership is updated
        _assertUserPosition(address(this), 0, 1);
        _assertUserPosition(address(0x1), 1, 1);
    }

    function test_newPositionIsWrapped(
        uint256 amount_
    )
        public
        givenPositionCreated(address(this), REMAINING_DEPOSIT, CONVERSION_PRICE, EXPIRY, false)
    {
        uint256 amount = bound(amount_, 1, REMAINING_DEPOSIT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionSplit(0, 1, convertibleDepositToken, amount, address(0x1), true);

        // Call function
        _splitPosition(address(this), 0, amount, address(0x1), true);

        // Assert old position
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT - amount,
            CONVERSION_PRICE,
            EXPIRY,
            false
        );

        // Assert new position
        _assertPosition(1, address(0x1), amount, CONVERSION_PRICE, EXPIRY, true);

        // ERC721 balances for the old position are not updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Owner(0, address(this), false);

        // ERC721 balances for the new position are updated
        _assertERC721Balance(address(0x1), 1);
        _assertERC721Owner(1, address(0x1), true);

        // Assert the ownership is updated
        _assertUserPosition(address(this), 0, 1);
        _assertUserPosition(address(0x1), 1, 1);
    }
}