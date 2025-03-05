// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {Module} from "src/Kernel.sol";

contract CreateCDPOSTest is CDPOSTest {
    event PositionCreated(
        uint256 indexed positionId,
        address indexed owner,
        address indexed convertibleDepositToken,
        uint256 remainingDeposit,
        uint256 conversionPrice,
        uint48 conversionExpiry,
        uint48 redemptionExpiry,
        bool wrapped
    );

    // when the caller is not a permissioned address
    //  [X] it reverts
    // when the owner is the zero address
    //  [X] it reverts
    // when the convertible deposit token is the zero address
    //  [X] it reverts
    // when the remaining deposit is 0
    //  [X] it reverts
    // when the conversion price is 0
    //  [X] it reverts
    // when the expiry is in the past or now
    //  [X] it reverts
    // when the redemption expiry is less than or equal to the conversion expiry
    //  [X] it reverts
    // when multiple positions are created
    //  [X] the position IDs are sequential
    //  [X] the position IDs are unique
    //  [X] the owner's list of positions is updated
    // when the expiry is in the future
    //  [X] it sets the expiry
    // when the wrap flag is true
    //  when the receiver cannot receive ERC721 tokens
    //   [X] it reverts
    //  [X] it mints the ERC721 token
    //  [X] it marks the position as wrapped
    //  [X] the position is listed as owned by the owner
    //  [X] the ERC721 position is listed as owned by the owner
    //  [X] the ERC721 balance of the owner is increased
    // [X] it emits a PositionCreated event
    // [X] the position is marked as unwrapped
    // [X] the position is listed as owned by the owner
    // [X] the owner's list of positions is updated
    // [X] the ERC721 position is not listed as owned by the owner
    // [X] the ERC721 balance of the owner is not increased

    function test_callerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        vm.prank(address(this));
        CDPOS.create(
            address(this),
            convertibleDepositToken,
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_ownerIsZeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "owner"));

        // Call function
        _createPosition(
            address(0),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_convertibleDepositTokenIsZeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                CDPOSv1.CDPOS_InvalidParams.selector,
                "convertible deposit token"
            )
        );

        // Call function
        vm.prank(godmode);
        CDPOS.create(
            address(this),
            address(0),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_remainingDepositIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "deposit"));

        // Call function
        _createPosition(
            address(this),
            0,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_conversionPriceIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "conversion price")
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            0,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
    }

    function test_conversionExpiryIsInPastOrNow_reverts(uint48 expiry_) public {
        uint48 expiry = uint48(bound(expiry_, 0, block.timestamp));
        uint48 redemptionExpiry = expiry + REDEMPTION_PERIOD;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "conversion expiry")
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            expiry,
            redemptionExpiry,
            false
        );
    }

    function test_singlePosition() public {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionCreated(
            0,
            address(this),
            convertibleDepositToken,
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Assert that this contract did not receive the position ERC721
        _assertERC721PositionReceived(0, 0, false);

        // Assert that the ERC721 balances were not updated
        _assertERC721Balance(address(this), 0);
        _assertERC721Owner(0, address(this), false);

        // Assert that the position is correct
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Assert that the owner's list of positions is updated
        _assertUserPosition(address(this), 0, 1);
    }

    function test_singlePosition_whenWrapped_unsafeRecipient_reverts() public {
        // Expect revert
        vm.expectRevert();

        // Call function
        _createPosition(
            address(convertibleDepositToken), // Needs to be a contract
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            true
        );
    }

    function test_singlePosition_whenWrapped() public {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionCreated(
            0,
            address(this),
            convertibleDepositToken,
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            true
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            true
        );

        // Assert that this contract received the position ERC721
        _assertERC721PositionReceived(0, 1, true);

        // Assert that the ERC721 balances were updated
        _assertERC721Balance(address(this), 1);
        _assertERC721Owner(0, address(this), true);

        // Assert that the position is correct
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            true
        );

        // Assert that the owner's list of positions is updated
        _assertUserPosition(address(this), 0, 1);
    }

    function test_multiplePositions_singleOwner() public {
        // Create 10 positions
        for (uint256 i = 0; i < 10; i++) {
            _createPosition(
                address(this),
                REMAINING_DEPOSIT,
                CONVERSION_PRICE,
                CONVERSION_EXPIRY,
                REDEMPTION_EXPIRY,
                false
            );
        }

        // Assert that the position count is correct
        assertEq(CDPOS.positionCount(), 10, "positionCount");

        // Assert that the owner has sequential position IDs
        for (uint256 i = 0; i < 10; i++) {
            CDPOSv1.Position memory position = CDPOS.getPosition(i);
            assertEq(position.owner, address(this), "position.owner");

            // Assert that the ERC721 position is not updated
            _assertERC721Owner(i, address(this), false);
        }

        // Assert that the ERC721 balance of the owner is not updated
        _assertERC721Balance(address(this), 0);

        // Assert that the owner's positions list is correct
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        assertEq(ownerPositions.length, 10, "ownerPositions.length");
        for (uint256 i = 0; i < 10; i++) {
            assertEq(ownerPositions[i], i, "ownerPositions[i]");
        }
    }

    function test_multiplePositions_multipleOwners() public {
        address owner1 = address(this);
        address owner2 = address(mockERC721Receiver);

        // Create 5 positions for owner1
        for (uint256 i = 0; i < 5; i++) {
            _createPosition(
                owner1,
                REMAINING_DEPOSIT,
                CONVERSION_PRICE,
                CONVERSION_EXPIRY,
                REDEMPTION_EXPIRY,
                false
            );
        }

        // Create 5 positions for owner2
        for (uint256 i = 0; i < 5; i++) {
            _createPosition(
                owner2,
                REMAINING_DEPOSIT,
                CONVERSION_PRICE,
                CONVERSION_EXPIRY,
                REDEMPTION_EXPIRY,
                false
            );
        }

        // Assert that the position count is correct
        assertEq(CDPOS.positionCount(), 10, "positionCount");

        // Assert that the owner1's positions are correct
        for (uint256 i = 0; i < 5; i++) {
            CDPOSv1.Position memory position = CDPOS.getPosition(i);
            assertEq(position.owner, owner1, "position.owner");
        }

        // Assert that the owner2's positions are correct
        for (uint256 i = 5; i < 10; i++) {
            CDPOSv1.Position memory position = CDPOS.getPosition(i);
            assertEq(position.owner, owner2, "position.owner");
        }

        // Assert that the ERC721 balances of the owners are correct
        _assertERC721Balance(owner1, 0);
        _assertERC721Balance(owner2, 0);

        // Assert that the owner1's positions list is correct
        uint256[] memory owner1Positions = CDPOS.getUserPositionIds(owner1);
        assertEq(owner1Positions.length, 5, "owner1Positions.length");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(owner1Positions[i], i, "owner1Positions[i]");
        }

        // Assert that the owner2's positions list is correct
        uint256[] memory owner2Positions = CDPOS.getUserPositionIds(owner2);
        assertEq(owner2Positions.length, 5, "owner2Positions.length");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(owner2Positions[i], i + 5, "owner2Positions[i]");
        }
    }

    function test_conversionExpiryInFuture(uint48 expiry_) public {
        uint48 expiry = uint48(
            bound(expiry_, block.timestamp + 1, type(uint48).max - REDEMPTION_PERIOD)
        );
        uint48 redemptionExpiry = expiry + REDEMPTION_PERIOD;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit PositionCreated(
            0,
            address(this),
            convertibleDepositToken,
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            expiry,
            redemptionExpiry,
            false
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            expiry,
            redemptionExpiry,
            false
        );

        // Assert that the position is correct
        _assertPosition(
            0,
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            expiry,
            redemptionExpiry,
            false
        );
    }

    function test_redemptionExpiryLessThanOrEqualToConversionExpiry_reverts(
        uint48 redemptionExpiry_
    ) public {
        uint48 redemptionExpiry = uint48(bound(redemptionExpiry_, 0, CONVERSION_EXPIRY));

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidParams.selector, "redemption expiry")
        );

        // Call function
        _createPosition(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            CONVERSION_EXPIRY,
            redemptionExpiry,
            false
        );
    }
}
