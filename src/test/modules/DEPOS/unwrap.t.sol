// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";

contract UnwrapDEPOSTest is DEPOSTest {
    event PositionUnwrapped(uint256 indexed positionId);

    // when the position does not exist
    //  [X] it reverts
    // when the caller is not the owner of the position
    //  [X] it reverts
    // when the caller is a permissioned address
    //  [X] it reverts
    // when the position is not wrapped
    //  [X] it reverts
    // when the owner has multiple positions
    //  [X] the balance of the owner is decreased
    //  [X] the position is listed as not owned by the owner
    //  [X] the owner's list of positions is updated
    // [X] it burns the ERC721 token
    // [X] it emits a PositionUnwrapped event
    // [X] the position is marked as unwrapped
    // [X] the balance of the owner is decreased
    // [X] the position is listed as owned by the owner
    // [X] the owner's list of positions is updated

    function test_invalidPositionId_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(DEPOSv1.DEPOS_InvalidPositionId.selector, 0));

        // Call function
        _unwrapPosition(godmode, 0);
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
        vm.expectRevert(abi.encodeWithSelector(DEPOSv1.DEPOS_NotOwner.selector, 0));

        // Call function
        _unwrapPosition(address(0x1), 0);
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
        vm.expectRevert(abi.encodeWithSelector(DEPOSv1.DEPOS_NotOwner.selector, 0));

        // Call function
        _unwrapPosition(address(0x1), 0);
    }

    function test_positionIsNotWrapped_reverts()
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
        vm.expectRevert(abi.encodeWithSelector(DEPOSv1.DEPOS_NotWrapped.selector, 0));

        // Call function
        _unwrapPosition(address(this), 0);
    }

    function test_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        )
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionUnwrapped(0);

        // Call function
        _unwrapPosition(address(this), 0);

        // Assert position is unwrapped
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        );

        // Assert ERC721 balances are updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Owner(0, address(this), false);

        // Assert owner's list of positions is updated
        _assertUserPosition(address(this), 0, 1);
    }

    function test_multiplePositions_unwrapFirst()
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
            true
        )
    {
        // Call function
        _unwrapPosition(address(this), 0);

        // Assert position is unwrapped
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        );
        _assertPosition(
            1,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );

        // Assert ERC721 balances are updated
        _assertERC721Balance(address(this), 1);
        _assertERC721Owner(0, address(this), false);
        _assertERC721Owner(1, address(this), true);

        // Assert owner's list of positions is updated
        _assertUserPosition(address(this), 0, 2);
        _assertUserPosition(address(this), 1, 2);
    }

    function test_multiplePositions_unwrapSecond()
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
            true
        )
    {
        // Call function
        _unwrapPosition(address(this), 1);

        // Assert position is unwrapped
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );
        _assertPosition(
            1,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            false
        );

        // Assert ERC721 balances are updated
        _assertERC721Balance(address(this), 1);
        _assertERC721Owner(0, address(this), true);
        _assertERC721Owner(1, address(this), false);

        // Assert owner's list of positions is updated
        _assertUserPosition(address(this), 0, 2);
        _assertUserPosition(address(this), 1, 2);
    }
}
