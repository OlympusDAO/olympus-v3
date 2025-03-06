// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract PreviewRedeemCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when the account_ is not the owner of all of the positions
    //  [X] it reverts
    // when any position is not valid
    //  [X] it reverts
    // when any position has not reached the conversion expiry
    //  [X] it reverts
    // when any position has reached the redemption expiry
    //  [X] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts
    // when the redeem amount is 0
    //  [X] it reverts
    // [X] it returns the total amount of deposit token that would be redeemed
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        facility.previewRedeem(recipient, new uint256[](0), new uint256[](0));
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
        facility.previewRedeem(recipient, positionIds_, amounts_);
    }

    function test_anyPositionHasDifferentOwner_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 10e18)
        givenAddressHasReserveToken(recipientTwo, 5e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(convertibleDepository), 5e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint256 positionId;
            if (positionIndex == i) {
                positionId = _createPosition(
                    recipientTwo,
                    5e18,
                    CONVERSION_PRICE,
                    CONVERSION_EXPIRY,
                    REDEMPTION_EXPIRY,
                    false
                );
            } else {
                positionId = _createPosition(
                    recipient,
                    5e18,
                    CONVERSION_PRICE,
                    CONVERSION_EXPIRY,
                    REDEMPTION_EXPIRY,
                    false
                );
            }

            positionIds_[i] = positionId;
            amounts_[i] = 5e18;
        }

        // Warp to beyond the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, positionIndex)
        );

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
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

        // Warp to beyond the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, 0)
        );

        // Call function
        facility.previewRedeem(recipientTwo, positionIds_, amounts_);
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

        // Warp to beyond the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 2));

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
    }

    function test_anyPositionHasNotReachedConversionExpiry_reverts(
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
            uint48 expiry = CONVERSION_EXPIRY;
            if (positionIndex == i) {
                expiry = CONVERSION_EXPIRY + 1;
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

        // Warp to beyond the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionNotExpired.selector,
                positionIndex
            )
        );

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
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
            uint48 redemptionExpiry = REDEMPTION_EXPIRY;
            if (positionIndex == i) {
                redemptionExpiry = REDEMPTION_EXPIRY - 1;
            }

            // Create position
            uint256 positionId = _createPosition(
                recipient,
                3e18,
                CONVERSION_PRICE,
                CONVERSION_EXPIRY,
                redemptionExpiry,
                false
            );

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Warp to before the normal redemption expiry
        vm.warp(REDEMPTION_EXPIRY - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionExpired.selector,
                positionIndex
            )
        );

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
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

        // Warp to beyond the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidAmount.selector,
                positionIndex,
                4e18
            )
        );

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
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

        // Warp to the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        facility.previewRedeem(recipient, positionIds_, amounts_);
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
        uint256 amountOne = bound(amountOne_, 0, 3e18);
        uint256 amountTwo = bound(amountTwo_, 0, 3e18);
        uint256 amountThree = bound(amountThree_, 0, 3e18);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        positionIds_[0] = 0;
        amounts_[0] = amountOne;
        positionIds_[1] = 1;
        amounts_[1] = amountTwo;
        positionIds_[2] = 2;
        amounts_[2] = amountThree;

        // Warp to the normal expiry
        vm.warp(CONVERSION_EXPIRY);

        // Call function
        (uint256 redeemed, address spender) = facility.previewRedeem(
            recipient,
            positionIds_,
            amounts_
        );

        // Assertion that the redeemed amount is the sum of the amounts
        assertEq(redeemed, amountOne + amountTwo + amountThree, "redeemed");

        // Assertion that the spender is the convertible depository
        assertEq(spender, address(convertibleDepository), "spender");
    }
}
