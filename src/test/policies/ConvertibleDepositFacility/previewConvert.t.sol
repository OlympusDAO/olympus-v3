// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract ConvertibleDepositFacilityPreviewConvertTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        facility.previewConvert(recipient, new uint256[](0), new uint256[](0));
    }

    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts

    function test_arrayLengthMismatch_reverts() public givenLocallyActive {
        uint256[] memory positionIds_ = new uint256[](1);
        uint256[] memory amounts_ = new uint256[](2);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidArgs.selector,
                "array length"
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when any position is not valid
    //  [X] it reverts

    function test_anyPositionIsNotValid_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            // Invalid position
            if (positionIndex == i) {
                positionIds_[i] = 2;
                amounts_[i] = RESERVE_TOKEN_AMOUNT / 2;
            }
            // Valid position
            else {
                positionIds_[i] = i;
                amounts_[i] = RESERVE_TOKEN_AMOUNT / 2;
            }
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 2)
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when any position has reached the conversion expiry
    //  [X] it reverts

    function test_anyPositionHasReachedConversionExpiry_reverts(
        uint48 warpTime_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
    {
        uint48 warpTime = uint48(bound(warpTime_, CONVERSION_EXPIRY, type(uint48).max));

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            // Create position
            uint256 positionId = _createPosition(recipient, 3e18, CONVERSION_PRICE, false);

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Warp to the expiry of positionIndex
        vm.warp(warpTime);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_PositionExpired.selector, 0)
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts

    function test_anyAmountIsGreaterThanRemainingDeposit_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            positionIds_[i] = i;

            // Invalid position
            if (positionIndex == i) {
                amounts_[i] = 4e18;
            }
            // Valid position
            else {
                amounts_[i] = 3e18;
            }
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidAmount.selector,
                positionIndex,
                4e18
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when the amount is 0
    //  [X] it reverts

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasPosition(recipient, 3e18)
    {
        uint256[] memory positionIds_ = new uint256[](1);
        uint256[] memory amounts_ = new uint256[](1);

        positionIds_[0] = 0;
        amounts_[0] = 0;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_InvalidArgs.selector, "amount")
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when the converted amount is 0
    //  [X] it reverts

    function test_convertedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasPosition(recipient, 3e18)
    {
        uint256[] memory positionIds_ = new uint256[](1);
        uint256[] memory amounts_ = new uint256[](1);

        positionIds_[0] = 0;
        amounts_[0] = 1;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidArgs.selector,
                "converted amount"
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // when the account is not the owner of all of the positions
    //  [X] it reverts

    function test_anyPositionHasDifferentOwner_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasReserveToken(recipientTwo, 9e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(depositManager), 9e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint256 positionId;
            if (positionIndex == i) {
                positionId = _createPosition(recipientTwo, 3e18, CONVERSION_PRICE, false);
            } else {
                positionId = _createPosition(recipient, 3e18, CONVERSION_PRICE, false);
            }

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, positionIndex)
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    function test_allPositionsHaveDifferentOwner_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
    {
        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        positionIds_[0] = 0;
        amounts_[0] = 3e18;
        positionIds_[1] = 1;
        amounts_[1] = 3e18;
        positionIds_[2] = 2;
        amounts_[2] = 3e18;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, 0)
        );

        // Call function
        facility.previewConvert(recipientTwo, positionIds_, amounts_);
    }

    // when any position has a different receipt token
    //  [X] it reverts

    function test_anyPositionHasDifferentReceiptToken_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasDifferentTokenAndPosition(recipient, RESERVE_TOKEN_AMOUNT)
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0; // receiptToken
        positionIds_[1] = 2; // receiptTokenTwo

        amounts_[0] = RESERVE_TOKEN_AMOUNT / 2;
        amounts_[1] = RESERVE_TOKEN_AMOUNT;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidArgs.selector,
                "multiple assets"
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // given any position has not been created by the CD facility
    //  [X] it reverts

    function test_anyPositionNotCreatedByConvertibleDepositFacility_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0; // receiptToken
        positionIds_[1] = 1; // receiptToken yield deposit

        amounts_[0] = RESERVE_TOKEN_AMOUNT / 2;
        amounts_[1] = RESERVE_TOKEN_AMOUNT / 2;

        // Expect revert
        _expectRevertUnsupported(1);

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    // given the deposit asset has 6 decimals
    //  [X] it returns the correct amount of receipt tokens that would be converted
    //  [X] it returns the correct amount of OHM that would be minted

    function test_reserveTokenHasSmallerDecimals(
        uint256 amountOne_,
        uint256 amountTwo_,
        uint256 amountThree_
    )
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e6)
    {
        uint256 amountOne = bound(amountOne_, 1e2, 3e6);
        uint256 amountTwo = bound(amountTwo_, 1e2, 3e6);
        uint256 amountThree = bound(amountThree_, 1e2, 3e6);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        positionIds_[0] = 0;
        amounts_[0] = amountOne;
        positionIds_[1] = 1;
        amounts_[1] = amountTwo;
        positionIds_[2] = 2;
        amounts_[2] = amountThree;

        // Create positions
        uint256 conversionPrice = 2e6;
        _createPosition(recipient, 3e6, conversionPrice, false);
        _createPosition(recipient, 3e6, conversionPrice, false);
        _createPosition(recipient, 3e6, conversionPrice, false);

        // Call function
        (uint256 totalDeposits, uint256 converted) = facility.previewConvert(
            recipient,
            positionIds_,
            amounts_
        );

        // Assertion that the total deposits are the sum of the amounts
        assertEq(totalDeposits, amountOne + amountTwo + amountThree, "totalDeposits");

        // Assertion that the converted amount is the sum of the amounts converted at the conversion price
        // Each amount is converted separately to avoid rounding errors
        assertEq(
            converted,
            (amountOne * 1e6) /
                conversionPrice +
                (amountTwo * 1e6) /
                conversionPrice +
                (amountThree * 1e6) /
                conversionPrice,
            "converted"
        );
    }

    // [X] it returns the total receipt token amount that would be converted
    // [X] it returns the amount of OHM that would be minted
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_success(
        uint256 amountOne_,
        uint256 amountTwo_,
        uint256 amountThree_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasPosition(recipient, 3e18)
    {
        uint256 amountOne = bound(amountOne_, 1e2, 3e18);
        uint256 amountTwo = bound(amountTwo_, 1e2, 3e18);
        uint256 amountThree = bound(amountThree_, 1e2, 3e18);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        positionIds_[0] = 0;
        amounts_[0] = amountOne;
        positionIds_[1] = 1;
        amounts_[1] = amountTwo;
        positionIds_[2] = 2;
        amounts_[2] = amountThree;

        // Call function
        (uint256 totalDeposits, uint256 converted) = facility.previewConvert(
            recipient,
            positionIds_,
            amounts_
        );

        // Assertion that the total deposits are the sum of the amounts
        assertEq(totalDeposits, amountOne + amountTwo + amountThree, "totalDeposits");

        // Assertion that the converted amount is the sum of the amounts converted at the conversion price
        // Each amount is converted separately to avoid rounding errors
        assertEq(
            converted,
            (amountOne * 1e18) /
                CONVERSION_PRICE +
                (amountTwo * 1e18) /
                CONVERSION_PRICE +
                (amountThree * 1e18) /
                CONVERSION_PRICE,
            "converted"
        );
    }
}
