// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract PreviewConvertCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when any position is not valid
    //  [X] it reverts
    // when any position has reached the conversion expiry
    //  [X] it reverts
    // when any position has reached the redemption expiry
    //  [X] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts
    // when the amount is 0
    //  [X] it reverts
    // when the converted amount is 0
    //  [X] it reverts
    // when the account is not the owner of all of the positions
    //  [X] it reverts
    // when any position has a different CD token
    //  [X] it reverts
    // given the deposit asset has 6 decimals
    //  [X] it returns the correct amount of CD tokens that would be converted
    //  [X] it returns the correct amount of OHM that would be minted
    // [X] it returns the total CD token amount that would be converted
    // [X] it returns the amount of OHM that would be minted
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        facility.previewConvert(recipient, new uint256[](0), new uint256[](0));
    }

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

    function test_anyPositionIsNotValid_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
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
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 2));

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    function test_anyPositionHasDifferentOwner_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
        givenAddressHasReserveToken(recipientTwo, 9e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(convertibleDepository), 9e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint256 positionId;
            if (positionIndex == i) {
                positionId = _createPosition(
                    recipientTwo,
                    3e18,
                    CONVERSION_PRICE,
                    CONVERSION_EXPIRY,
                    REDEMPTION_EXPIRY,
                    false
                );
            } else {
                positionId = _createPosition(
                    recipient,
                    3e18,
                    CONVERSION_PRICE,
                    CONVERSION_EXPIRY,
                    REDEMPTION_EXPIRY,
                    false
                );
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
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
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

    function test_anyPositionHasReachedConversionExpiry_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint48 expiry = uint48(block.timestamp + 1 days);
            if (positionIndex == i) {
                expiry = uint48(block.timestamp + 1);
            }

            // Create position
            uint256 positionId = _createPosition(
                recipient,
                3e18,
                CONVERSION_PRICE,
                expiry,
                REDEMPTION_EXPIRY,
                false
            );

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Warp to beyond the expiry of positionIndex
        vm.warp(INITIAL_BLOCK + 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionExpired.selector,
                positionIndex
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    function test_anyPositionHasReachedRedemptionExpiry_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint48 expiry = uint48(block.timestamp + 1 days);
            uint48 redemptionExpiry = uint48(block.timestamp + 2 days);
            if (positionIndex == i) {
                expiry = uint48(block.timestamp + 1);
                redemptionExpiry = uint48(block.timestamp + 2);
            }

            // Create position
            uint256 positionId = _createPosition(
                recipient,
                3e18,
                CONVERSION_PRICE,
                expiry,
                redemptionExpiry,
                false
            );

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Warp to beyond the expiry of positionIndex
        vm.warp(INITIAL_BLOCK + 2);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionExpired.selector,
                positionIndex
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    function test_anyAmountIsGreaterThanRemainingDeposit_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
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

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
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

    function test_convertedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
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

    function test_reserveTokenHasSmallerDecimals(
        uint256 amountOne_,
        uint256 amountTwo_,
        uint256 amountThree_
    )
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e6)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e6)
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
        _createPosition(
            recipient,
            3e6,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
        _createPosition(
            recipient,
            3e6,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
        _createPosition(
            recipient,
            3e6,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Call function
        (uint256 totalDeposits, uint256 converted, address spender) = facility.previewConvert(
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

        // Assertion that the spender is the convertible depository
        assertEq(spender, address(convertibleDepository), "spender");
    }

    function test_anyPositionHasDifferentCDToken_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasDifferentTokenAndPosition(recipient, RESERVE_TOKEN_AMOUNT)
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0; // cdToken
        positionIds_[1] = 2; // cdTokenTwo

        amounts_[0] = RESERVE_TOKEN_AMOUNT / 2;
        amounts_[1] = RESERVE_TOKEN_AMOUNT;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidArgs.selector,
                "multiple CD tokens"
            )
        );

        // Call function
        facility.previewConvert(recipient, positionIds_, amounts_);
    }

    function test_success(
        uint256 amountOne_,
        uint256 amountTwo_,
        uint256 amountThree_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
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
        (uint256 totalDeposits, uint256 converted, address spender) = facility.previewConvert(
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

        // Assertion that the spender is the convertible depository
        assertEq(spender, address(convertibleDepository), "spender");
    }
}
