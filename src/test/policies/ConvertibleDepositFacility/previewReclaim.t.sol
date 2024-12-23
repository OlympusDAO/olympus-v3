// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract PreviewReclaimCDFTest is ConvertibleDepositFacilityTest {
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when the account_ is not the owner of all of the positions
    //  [X] it reverts
    // when any position is not valid
    //  [ ] it reverts
    // when any position has a convertible deposit token that is not CDEPO
    //  [ ] it reverts
    // when any position has not expired
    //  [ ] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [ ] it reverts
    // when the reclaim amount is 0
    //  [ ] it reverts
    // [ ] it returns the total amount of deposit token that would be reclaimed
    // [ ] it returns the address that will spend the convertible deposit tokens

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
        facility.previewReclaim(recipient, positionIds_, amounts_);
    }

    function test_anyPositionHasDifferentOwner_reverts()
        public
        givenAddressHasReserveToken(recipient, 3e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 3e18)
        givenAddressHasPosition(recipient, 3e18)
        givenAddressHasReserveToken(recipientTwo, 3e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(convertibleDepository), 3e18)
        givenAddressHasPosition(recipientTwo, 3e18)
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 3e18;
        positionIds_[1] = 1;
        amounts_[1] = 3e18;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, 0)
        );

        // Call function
        facility.previewReclaim(recipientTwo, positionIds_, amounts_);
    }

    function test_allPositionsHaveDifferentOwner_reverts()
        public
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
        facility.previewReclaim(recipientTwo, positionIds_, amounts_);
    }
}
