// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";

contract PreviewConvertCDFTest is ConvertibleDepositFacilityTest {
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when any position is not valid
    //  [X] it reverts
    // when any position has expired
    //  [X] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts
    // [X] it returns the total CD token amount that would be converted
    // [X] it returns the amount of OHM that would be minted
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_arrayLengthMismatch_reverts() public {
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
        facility.previewConvert(positionIds_, amounts_);
    }

    function test_anyPositionIsNotValid_reverts(
        uint256 positionIndex_
    )
        public
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
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, positionIndex)
        );

        // Call function
        facility.previewConvert(positionIds_, amounts_);
    }

    function test_anyPositionHasExpired_reverts(
        uint256 positionIndex_
    )
        public
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
            uint256 positionId = _createPosition(recipient, 3e18, CONVERSION_PRICE, expiry, false);

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionExpired.selector,
                positionIndex
            )
        );

        // Call function
        facility.previewConvert(positionIds_, amounts_);
    }

    function test_anyAmountIsGreaterThanRemainingDeposit_reverts(
        uint256 positionIndex_
    )
        public
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
        facility.previewConvert(positionIds_, amounts_);
    }

    function test_success(
        uint256 amountOne_,
        uint256 amountTwo_,
        uint256 amountThree_
    )
        public
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

        // Call function
        (uint256 totalDeposits, uint256 converted, address spender) = facility.previewConvert(
            positionIds_,
            amounts_
        );

        // Assertions
        assertEq(totalDeposits, amountOne + amountTwo + amountThree);
        assertEq(converted, ((amountOne + amountTwo + amountThree) * 1e18) / CONVERSION_PRICE);
        assertEq(spender, address(convertibleDepository));
    }
}
