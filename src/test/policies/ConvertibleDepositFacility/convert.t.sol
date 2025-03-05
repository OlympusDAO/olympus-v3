// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

contract ConvertCDFTest is ConvertibleDepositFacilityTest {
    event ConvertedDeposit(address indexed user, uint256 depositAmount, uint256 convertedAmount);

    // given the contract is inactive
    //  [X] it reverts
    // when the length of the positionIds_ array does not match the length of the amounts_ array
    //  [X] it reverts
    // when any position is not valid
    //  [X] it reverts
    // when any position has an owner that is not the caller
    //  [X] it reverts
    // when any position has reached the conversion expiry
    //  [X] it reverts
    // when any position has reached the redemption expiry
    //  [X] it reverts
    // when any position has an amount greater than the remaining deposit
    //  [X] it reverts
    // when the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [X] it reverts
    // when the converted amount is 0
    //  [X] it reverts
    // given the deposit asset has 6 decimals
    //  [X] the amount of CD tokens converted is correct
    //  [X] the amount of OHM minted is correct
    // [X] it mints the converted amount of OHM to the account_
    // [X] it updates the remaining deposit of each position
    // [X] it transfers the redeemed vault shares to the TRSRY
    // [X] it returns the total deposit amount and the converted amount
    // [X] it emits a ConvertedDeposit event

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotActive.selector));

        // Call function
        facility.convert(new uint256[](0), new uint256[](0));
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
        facility.convert(positionIds_, amounts_);
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
                positionIds_[i] = i < positionIndex ? i : i - 1;
                amounts_[i] = RESERVE_TOKEN_AMOUNT / 2;
            }
        }

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 2));

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
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

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_NotOwner.selector, positionIndex)
        );

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
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
        vm.prank(recipientTwo);
        facility.convert(positionIds_, amounts_);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
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
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
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
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT / 2)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
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
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "allowance"));

        // Call function
        vm.prank(recipient);
        facility.convert(positionIds_, amounts_);
    }

    function test_convertedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasPosition(recipient, RESERVE_TOKEN_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
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
        facility.convert(positionIds_, amounts_);
    }

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 10e6)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            10e6
        )
    {
        uint256[] memory positionIds_ = new uint256[](2);
        uint256[] memory amounts_ = new uint256[](2);

        positionIds_[0] = 0;
        amounts_[0] = 5e6;
        positionIds_[1] = 1;
        amounts_[1] = 5e6;

        uint256 conversionPrice = 2e6;

        uint256 expectedConvertedAmount = (10e6 * 1e6) / conversionPrice;
        uint256 expectedVaultShares = vault.previewDeposit(10e6);

        // Create positions
        _createPosition(
            recipient,
            10e6 / 2,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );
        _createPosition(
            recipient,
            10e6 / 2,
            conversionPrice,
            CONVERSION_EXPIRY,
            REDEMPTION_EXPIRY,
            false
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ConvertedDeposit(recipient, 10e6, expectedConvertedAmount);

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(positionIds_, amounts_);

        // Assert total deposit
        assertEq(totalDeposit, 10e6, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            0,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            0,
            "minter.mintApproval(address(facility))"
        );

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

        // Deposit token is not transferred to the TRSRY
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
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Vault shares are transferred to the TRSRY
        assertEq(
            vault.balanceOf(address(treasury)),
            expectedVaultShares,
            "vault.balanceOf(address(treasury))"
        );
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
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
        amounts_[0] = 5e18;
        positionIds_[1] = 1;
        amounts_[1] = 5e18;

        uint256 expectedConvertedAmount = (RESERVE_TOKEN_AMOUNT * 1e18) / CONVERSION_PRICE;
        uint256 expectedVaultShares = vault.previewDeposit(RESERVE_TOKEN_AMOUNT);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ConvertedDeposit(recipient, RESERVE_TOKEN_AMOUNT, expectedConvertedAmount);

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(positionIds_, amounts_);

        // Assert total deposit
        assertEq(totalDeposit, RESERVE_TOKEN_AMOUNT, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            0,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            0,
            "minter.mintApproval(address(facility))"
        );

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

        // Deposit token is not transferred to the TRSRY
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
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Vault shares are transferred to the TRSRY
        assertEq(
            vault.balanceOf(address(treasury)),
            expectedVaultShares,
            "vault.balanceOf(address(treasury))"
        );
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
        uint256 expectedVaultShares = vault.previewDeposit(amountOne + amountTwo);

        // Call function
        vm.prank(recipient);
        (uint256 totalDeposit, uint256 convertedAmount) = facility.convert(positionIds_, amounts_);

        // Assert total deposit
        assertEq(totalDeposit, amountOne + amountTwo, "totalDeposit");

        // Assert converted amount
        assertEq(convertedAmount, expectedConvertedAmount, "convertedAmount");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            convertibleDepository.balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT - amountOne - amountTwo,
            "convertibleDepository.balanceOf(recipient)"
        );

        // Assert OHM minted to the recipient
        assertEq(ohm.balanceOf(recipient), expectedConvertedAmount, "ohm.balanceOf(recipient)");

        // Assert the remaining mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            originalMintApproval - expectedConvertedAmount,
            "mintApproval"
        );

        // Assert the remaining deposit of each position
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

        // Vault shares are transferred to the TRSRY
        assertEq(
            vault.balanceOf(address(treasury)),
            expectedVaultShares,
            "vault.balanceOf(address(treasury))"
        );
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }
}
