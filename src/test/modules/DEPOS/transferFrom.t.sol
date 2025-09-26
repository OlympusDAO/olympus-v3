// SPDX-License-Identifier: Unlicensed
/// forge-lint: disable-start(erc20-unchecked-transfer)
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

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
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 0)
        );

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
        vm.prank(OTHER);
        DEPOS.transferFrom(address(this), OTHER, 0);
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
        DEPOS.transferFrom(address(this), OTHER, 0);
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
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_NotWrapped.selector, 0)
        );

        // Call function
        vm.prank(address(this));
        DEPOS.transferFrom(address(this), OTHER, 0);
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
        DEPOS.transferFrom(address(this), OTHER, 0);

        // ERC721 balance updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Balance(OTHER, 1);
        _assertERC721Owner(0, OTHER, true);

        // Position record updated
        _assertPosition(0, OTHER, REMAINING_DEPOSIT, CONVERSION_PRICE, CONVERSION_EXPIRY, true);

        // Position ownership updated
        assertEq(
            DEPOS.getUserPositionIds(address(this)).length,
            0,
            "getUserPositionIds should return 0 length"
        );
        _assertUserPosition(OTHER, 0, 1);
    }

    function test_transferToSelf_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        )
    {
        // Get initial state
        uint256 initialBalance = DEPOS.balanceOf(address(this));
        uint256[] memory initialUserPositions = DEPOS.getUserPositionIds(address(this));

        // Call function - transfer to self
        DEPOS.transferFrom(address(this), address(this), 0);

        // ERC721 balance should remain the same
        _assertERC721Balance(address(this), initialBalance);
        _assertERC721Owner(0, address(this), true);

        // Position record should remain unchanged
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            true
        );

        // Position ownership should remain unchanged
        assertEq(
            DEPOS.getUserPositionIds(address(this)).length,
            initialUserPositions.length,
            "getUserPositionIds length should remain the same"
        );
        _assertUserPosition(address(this), 0, initialUserPositions.length);
    }
}
/// forge-lint: disable-end(erc20-unchecked-transfer)
