// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {stdError} from "forge-std/StdError.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDepositFacilityConvertTest is ConvertibleDepositFacilityTest {
    event ConvertedDeposit(
        address indexed asset,
        address indexed depositor,
        uint8 periodMonths,
        uint256 depositAmount,
        uint256 convertedAmount
    );

    struct ConvertTempParams {
        uint256[] positionIds;
        uint256[] amounts;
    }

    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        facility.convert(new uint256[](0), new uint256[](0), true);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // when any position is not valid
    //  [X] it reverts

    function test_anyPositionIsNotValid_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
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
                positionIds_[i] = i < positionIndex ? i : i - 1;
                amounts_[i] = RESERVE_TOKEN_AMOUNT / 2;
            }
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidPositionId.selector, 2)
        );

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // when any position has an owner that is not the caller
    //  [X] it reverts

    function test_anyPositionHasDifferentOwner_reverts(
        uint256 positionIndex_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 10e18)
        givenAddressHasReserveToken(recipientTwo, 5e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(depositManager), 5e18)
    {
        uint256 positionIndex = bound(positionIndex_, 0, 2);

        uint256[] memory positionIds_ = new uint256[](3);
        uint256[] memory amounts_ = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            uint256 positionId;
            if (positionIndex == i) {
                positionId = _createPosition(recipientTwo, 5e18, CONVERSION_PRICE, false);
            } else {
                positionId = _createPosition(recipient, 5e18, CONVERSION_PRICE, false);
            }

            positionIds_[i] = positionId;
            amounts_[i] = 5e18;
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, positionIndex)
        );

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
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
        vm.prank(recipientTwo);
        facility.convert(positionIds_, amounts_, true);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // when any position has a different receipt token
    //  [X] it reverts

    function test_anyPositionHasDifferentReceiptToken_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // when the caller has not approved DepositManager to spend the total amount of receipt tokens
    //  [X] it reverts

    function test_spendingIsNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenWrappedReceiptTokenSpendingIsApproved(
            recipient,
            address(receiptTokenManager),
            RESERVE_TOKEN_AMOUNT - 1
        )
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 5e18;
        positionIds_[1] = 1;
        amounts_[1] = 5e18;

        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // when the converted amount is 0
    //  [X] it reverts

    function test_convertedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT)
        givenWrappedReceiptTokenSpendingIsApproved(
            recipient,
            address(receiptTokenManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256[] memory positionIds_ = new uint256[](1);
        uint256[] memory amounts_ = new uint256[](1);

        positionIds_[0] = 0;
        amounts_[0] = 1; // 1 / 2 = 0

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MINTRv1.MINTR_ZeroAmount.selector));

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // given any position has not been created by the CD facility
    //  [X] it reverts

    function test_anyPositionNotCreatedByConvertibleDepositFacility_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_, true);
    }

    // given the deposit asset has 6 decimals
    //  [X] the amount of receipt tokens converted is correct
    //  [X] the amount of OHM minted is correct

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 10e6)
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 5e6;
        positionIds_[1] = 1;
        amounts_[1] = 5e6;

        uint256 conversionPrice = 2e6;

        // Proof:
        // Converted amount: deposit / price (in OHM scale)
        // Deposit amount: 10e6
        // Conversion price: 2e6 (deposit tokens per OHM)
        // Converted amount (OHM): 10e6 * 1e9 / 2e6 = 5e9
        uint256 expectedConvertedAmount = 5e9;
        uint256 expectedAssets = 10e6;

        // Create positions
        _createPosition(recipient, 10e6 / 2, conversionPrice, false, true);
        _createPosition(recipient, 10e6 / 2, conversionPrice, false, true);

        // Approve spending
        _approveWrappedReceiptTokenSpending(
            recipient,
            address(receiptTokenManager),
            expectedAssets
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ConvertedDeposit(
            address(reserveToken),
            recipient,
            PERIOD_MONTHS,
            expectedAssets,
            expectedConvertedAmount
        );

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(
            positionIds_,
            amounts_,
            true
        );

        // Assert total deposit
        assertEq(totalDeposit, expectedAssets, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        _assertReceiptTokenBalance(recipient, 0, true);

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Assert remaining deposit
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(0).remainingDeposit"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(1).remainingDeposit"
        );

        _assertAssetBalance(expectedAssets, 0);
        _assertVaultBalance();
    }

    // [X] it mints the converted amount of OHM to the account_
    // [X] it updates the remaining deposit of each position
    // [X] it transfers the redeemed vault shares to the TRSRY
    // [X] it returns the total deposit amount and the converted amount
    // [X] it emits a ConvertedDeposit event

    /// forge-config: default.isolate = true
    function test_success()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenWrappedReceiptTokenSpendingIsApproved(
            recipient,
            address(receiptTokenManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 5e18;
        positionIds_[1] = 1;
        amounts_[1] = 5e18;

        // Proof:
        // Converted amount: deposit / price (in OHM scale)
        // Deposit amount: 10e18
        // Conversion price: 2e18 (deposit tokens per OHM)
        // Converted amount (OHM): 10e18 * 1e9 / 2e18 = 5e9
        uint256 expectedConvertedAmount = 5e9;
        uint256 expectedAssets = RESERVE_TOKEN_AMOUNT;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ConvertedDeposit(
            address(reserveToken),
            recipient,
            PERIOD_MONTHS,
            expectedAssets,
            expectedConvertedAmount
        );

        // Start gas snapshot
        vm.startSnapshotGas("convert");

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(
            positionIds_,
            amounts_,
            true
        );

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assert total deposit
        assertEq(totalDeposit, expectedAssets, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        _assertReceiptTokenBalance(recipient, 0, true);

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Assert remaining deposit
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(0).remainingDeposit"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(1).remainingDeposit"
        );

        _assertAssetBalance(expectedAssets, 0);
        _assertVaultBalance();
    }

    function test_success(
        uint256 amountOne_
    )
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenAddressHasPosition(recipient, 5e18)
        givenAddressHasPosition(recipient, 5e18)
        givenWrappedReceiptTokenSpendingIsApproved(
            recipient,
            address(receiptTokenManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Both 2+ so that the converted amount is not 0
        amountOne_ = bound(amountOne_, 2, 5e18);

        ConvertTempParams memory convertParams;
        {
            convertParams = ConvertTempParams({
                positionIds: new uint256[](2),
                amounts: new uint256[](2)
            });

            convertParams.positionIds[0] = 0;
            convertParams.amounts[0] = amountOne_;
            convertParams.positionIds[1] = 1;
            convertParams.amounts[1] = 4e18;
        }

        uint256 expectedConvertedAmount = (amountOne_ * 1e9) /
            CONVERSION_PRICE +
            (4e18 * 1e9) /
            CONVERSION_PRICE;
        uint256 expectedAssets = amountOne_ + 4e18;

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(
            convertParams.positionIds,
            convertParams.amounts,
            true
        );

        // Assert total deposit
        assertEq(totalDeposit, expectedAssets, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        _assertReceiptTokenBalance(recipient, RESERVE_TOKEN_AMOUNT - expectedAssets, true);

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Assert the remaining deposit of each position
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            5e18 - amountOne_,
            "remainingDeposit[0]"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            5e18 - 4e18,
            "remainingDeposit[1]"
        );

        _assertAssetBalance(expectedAssets, 0);
        _assertVaultBalance();
    }

    // when wrapReceipt is false
    //  [X] it converts the unwrapped receipt tokens

    function test_whenWrapReceiptIsFalse()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
        givenReceiptTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Create two positions
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT / 2, CONVERSION_PRICE, false, false);
        _createPosition(recipient, RESERVE_TOKEN_AMOUNT / 2, CONVERSION_PRICE, false, false);

        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 5e18;
        positionIds_[1] = 1;
        amounts_[1] = 5e18;

        // Proof:
        // Converted amount: deposit / price (in OHM scale)
        // Deposit amount: 10e18
        // Conversion price: 2e18 (deposit tokens per OHM)
        // Converted amount (OHM): 10e18 * 1e9 / 2e18 = 5e9
        uint256 expectedConvertedAmount = 5e9;
        uint256 expectedAssets = RESERVE_TOKEN_AMOUNT;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ConvertedDeposit(
            address(reserveToken),
            recipient,
            PERIOD_MONTHS,
            expectedAssets,
            expectedConvertedAmount
        );

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(
            positionIds_,
            amounts_,
            false
        );

        // Assert total deposit
        assertEq(totalDeposit, expectedAssets, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        _assertReceiptTokenBalance(recipient, 0, false);

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        _assertMintApproval(0);

        // Assert remaining deposit
        assertEq(
            convertibleDepositPositions.getPosition(0).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(0).remainingDeposit"
        );
        assertEq(
            convertibleDepositPositions.getPosition(1).remainingDeposit,
            0,
            "convertibleDepositPositions.getPosition(1).remainingDeposit"
        );

        _assertAssetBalance(expectedAssets, 0);
        _assertVaultBalance();
    }
}
