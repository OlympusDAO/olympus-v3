// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract ReclaimCDFTest is ConvertibleDepositFacilityTest {
    event ReclaimedDeposit(address indexed user, uint256 reclaimedAmount, uint256 forfeitedAmount);

    // given the contract is inactive
    //  [X] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when any position is not valid
    //  [X] it reverts
    // when any position has an owner that is not the caller
    //  [X] it reverts
    // when any position has expired
    //  [X] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts
    // when the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [X] it reverts
    // when the reclaim amount is 0
    //  [X] it reverts
    // [X] it updates the remaining deposit of each position
    // [X] it transfers the reclaimed reserve tokens to the caller
    // [X] it decreases the OHM mint approval by the amount of OHM that would have been converted
    // [X] it returns the reclaimed amount
    // [X] it emits a ReclaimedDeposit event

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotActive.selector));

        // Call function
        facility.reclaim(new uint256[](0), new uint256[](0));
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
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
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
                positionId = _createPosition(recipientTwo, 5e18, CONVERSION_PRICE, EXPIRY, false);
            } else {
                positionId = _createPosition(recipient, 5e18, CONVERSION_PRICE, EXPIRY, false);
            }

            positionIds_[i] = positionId;
            amounts_[i] = 5e18;
        }

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, positionIndex)
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
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

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, 0)
        );

        // Call function
        vm.prank(recipientTwo);
        facility.reclaim(positionIds_, amounts_);
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

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 2));

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
    }

    function test_anyPositionHasExpired_reverts(
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
            uint48 expiry = EXPIRY;
            if (positionIndex == i) {
                expiry = EXPIRY - 1;
            }

            // Create position
            uint256 positionId = _createPosition(recipient, 3e18, CONVERSION_PRICE, expiry, false);

            positionIds_[i] = positionId;
            amounts_[i] = 3e18;
        }

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_PositionNotExpired.selector,
                positionIndex
            )
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
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

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_InvalidAmount.selector,
                positionIndex,
                4e18
            )
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
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

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
    }

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT)
    {
        uint256[] memory positionIds_ = new uint256[](1);
        uint256[] memory amounts_ = new uint256[](1);

        positionIds_[0] = 0;
        amounts_[0] = RESERVE_TOKEN_AMOUNT;

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "allowance"));

        // Call function
        vm.prank(recipient);
        facility.reclaim(positionIds_, amounts_);
    }

    function test_success()
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
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = RESERVE_TOKEN_AMOUNT / 2;
        positionIds_[1] = 1;
        amounts_[1] = RESERVE_TOKEN_AMOUNT / 2;

        uint256 expectedReclaimedAmount = ((amounts_[0] + amounts_[1]) * CDEPO.reclaimRate()) /
            100e2;
        uint256 expectedForfeitedAmount = RESERVE_TOKEN_AMOUNT - expectedReclaimedAmount;

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimedDeposit(recipient, expectedReclaimedAmount, expectedForfeitedAmount);

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(positionIds_, amounts_);

        // Assertion that the reclaimed amount is the sum of the amounts adjusted by the reclaim rate
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            0,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            0,
            "minter.mintApproval(address(facility))"
        );

        // Assertion that the remaining deposit of each position is updated
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            0,
            "remainingDeposit[0]"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            0,
            "remainingDeposit[1]"
        );

        // Deposit token is transferred to the recipient
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            0,
            "reserveToken.balanceOf(address(treasury))"
        );
        assertEq(
            reserveToken.balanceOf(address(facility)),
            0,
            "reserveToken.balanceOf(address(facility))"
        );
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Vault shares are not transferred to the TRSRY
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }

    function test_success_fuzz(
        uint256 amountOne_,
        uint256 amountTwo_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, 5e18)
        givenAddressHasPosition(recipient, 5e18)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Both 2+ so that the converted amount is not 0
        uint256 amountOne = bound(amountOne_, 2, 5e18);
        uint256 amountTwo = bound(amountTwo_, 2, 5e18);

        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = amountOne;
        positionIds_[1] = 1;
        amounts_[1] = amountTwo;

        uint256 originalMintApproval = minter.mintApproval(address(facility));
        uint256 expectedConvertedAmount = (amountOne * 1e18) /
            CONVERSION_PRICE +
            (amountTwo * 1e18) /
            CONVERSION_PRICE;

        // Calculate the amount that will be reclaimed
        uint256 expectedReclaimedAmount = ((amountOne + amountTwo) * CDEPO.reclaimRate()) / 100e2;
        uint256 expectedForfeitedAmount = amountOne + amountTwo - expectedReclaimedAmount;

        // Warp to before the expiry
        vm.warp(EXPIRY - 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimedDeposit(recipient, expectedReclaimedAmount, expectedForfeitedAmount);

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(positionIds_, amounts_);

        // Assert reclaimed amount
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT - amountOne - amountTwo,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // Assert the remaining mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            originalMintApproval - expectedConvertedAmount,
            "mintApproval"
        );

        // Assertion that the remaining deposit of each position is updated
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            5e18 - amountOne,
            "remainingDeposit[0]"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            5e18 - amountTwo,
            "remainingDeposit[1]"
        );

        // Deposit token is transferred to the recipient
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            0,
            "reserveToken.balanceOf(address(treasury))"
        );
        assertEq(
            reserveToken.balanceOf(address(facility)),
            0,
            "reserveToken.balanceOf(address(facility))"
        );
        assertEq(
            reserveToken.balanceOf(recipient),
            amountOne + amountTwo,
            "reserveToken.balanceOf(recipient)"
        );

        // Vault shares are not transferred to the TRSRY
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }
}
