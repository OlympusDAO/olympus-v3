// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";

contract TransferFromDEPOSTest is DEPOSTest {
    // when the position does not exist
    //  [X] it reverts
    // when the ERC721 has not been minted
    //  [X] it reverts
    // when the caller is not the owner of the position
    //  [X] it reverts
    // when the caller is a permissioned address
    //  [X] it reverts
    // [X] it transfers the ownership of the position to the to_ address
    // [X] it adds the position to the to_ address's list of positions
    // [X] it removes the position from the from_ address's list of positions

    function test_invalidPositionId_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(DEPOSv1.DEPOS_InvalidPositionId.selector, 0));

        // Call function
        DEPOS.transferFrom(address(this), address(1), 0);
    }

    function test_callerIsNotOwner_reverts()
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
        vm.expectRevert("NOT_AUTHORIZED");

        // Call function
        vm.prank(address(0x1));
        DEPOS.transferFrom(address(this), address(0x1), 0);
    }

    function test_callerIsPermissioned_reverts()
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
        vm.expectRevert("NOT_AUTHORIZED");

        // Call function
        vm.prank(godmode);
        DEPOS.transferFrom(address(this), address(0x1), 0);
    }

    function test_notMinted_reverts()
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
        vm.prank(address(this));
        DEPOS.transferFrom(address(this), address(0x1), 0);
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
        // Call function
        DEPOS.transferFrom(address(this), address(0x1), 0);

        // ERC721 balance updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Balance(address(0x1), 1);
        _assertERC721Owner(0, address(0x1), true);

        // Position record updated
        _assertPosition(
            0,
            address(0x1),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );

        // Position ownership updated
        assertEq(
            DEPOS.getUserPositionIds(address(this)).length,
            0,
            "getUserPositionIds should return 0 length"
        );
        _assertUserPosition(address(0x1), 0, 1);
    }
}
