// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract WrapDEPOSTest is DEPOSTest {
    event PositionWrapped(uint256 indexed positionId);

    // when the position does not exist
    //  [X] it reverts
    // when the caller is not the owner of the position
    //  [X] it reverts
    // when the caller is a permissioned address
    //  [X] it reverts
    // when the position is already wrapped
    //  [X] it reverts
    // when the owner has an existing wrapped position
    //  [X] the balance of the owner is increased
    //  [X] the position is listed as owned by the owner
    //  [X] the owner's list of positions is updated
    // [X] it mints the ERC721 token
    // [X] it emits a PositionWrapped event
    // [X] the position is marked as wrapped
    // [X] the balance of the owner is increased
    // [X] the position is listed as owned by the owner
    // [X] the owner's list of positions is updated

    function test_invalidPositionId_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 0)
        );

        // Call function
        _wrapPosition(address(this), 0);
    }

    function test_callerIsNotOwner_reverts()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotOwner.selector, 0));

        // Call function
        _wrapPosition(OTHER, 0);
    }

    function test_callerIsPermissionedAddress_reverts()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotOwner.selector, 0));

        // Call function
        _wrapPosition(godmode, 0);
    }

    function test_positionIsAlreadyWrapped_reverts()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        )
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_AlreadyWrapped.selector, 0)
        );

        // Call function
        _wrapPosition(address(this), 0);
    }

    function test_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionWrapped(0);

        // Call function
        _wrapPosition(address(this), 0);

        // Assert position is updated
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );

        // Assert ERC721 token is minted
        _assertERC721PositionReceived(0, 1, true);

        // Assert ERC721 balances are updated
        _assertERC721Balance(address(this), 1);
        _assertERC721Owner(0, address(this), true);

        // Assert owner's list of positions is updated
        _assertUserPosition(address(this), 0, 1);
    }

    function test_multiplePositions()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        )
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionWrapped(1);

        // Call function
        _wrapPosition(address(this), 1);

        // Assert position is updated
        _assertPosition(
            1,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );

        // Assert ERC721 token is minted
        _assertERC721PositionReceived(1, 2, true);

        // Assert ERC721 balances are updated
        _assertERC721Balance(address(this), 2);
        _assertERC721Owner(0, address(this), true);
        _assertERC721Owner(1, address(this), true);

        // Assert owner's list of positions is updated
        _assertUserPosition(address(this), 0, 2);
        _assertUserPosition(address(this), 1, 2);
    }
}
