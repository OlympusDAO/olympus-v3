// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

// Test calls intentionally ignore return values when asserting only revert behavior or one tuple
// component.
// forge-lint: disable-start(unused-return)

import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {console2} from "@forge-std-1.16.2/console2.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract ConvertibleDepositFacilityDepositTest is ConvertibleDepositFacilityTest {
    // Scenarios: DM-DEPOSIT-T02.
    function test_givenRealDepositManagerNamespaceHasLoss_whenDepositing_revertsAndRollsBack(
        bool wrapped_
    ) public givenLocallyActive {
        reserveToken.mint(recipient, 108);
        vm.prank(recipient);
        reserveToken.approve(address(depositManager), 108);
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, 100, wrapped_);
        reserveToken.burn(address(vault), 20);
        uint256 wrappedSupply = _getWrappedReceiptToken(iReserveToken, PERIOD_MONTHS).totalSupply();

        // 100 shares now represent 80 assets; input 8 buys 10 shares and 8 new liabilities.
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(reserveToken),
                uint256(108),
                uint256(88),
                uint256(0)
            )
        );
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, 8, wrapped_);

        assertEq(reserveToken.balanceOf(recipient), 8, "Payer balance rolls back");
        assertEq(
            reserveToken.allowance(recipient, address(depositManager)),
            8,
            "Payer allowance rolls back"
        );
        assertEq(reserveToken.balanceOf(address(vault)), 80, "Vault backing rolls back");
        assertEq(reserveToken.balanceOf(address(depositManager)), 0, "No manager residual");
        assertEq(reserveToken.balanceOf(address(facility)), 0, "No facility residual");
        assertEq(vault.balanceOf(address(depositManager)), 100, "Physical custody rolls back");
        assertEq(vault.totalSupply(), 100, "Vault share supply rolls back");
        (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(
            iReserveToken,
            address(facility)
        );
        assertEq(shares, 100, "Facility recorded shares roll back");
        assertEq(assets, 80, "Facility custody value rolls back");
        assertEq(
            depositManager.getOperatorLiabilities(iReserveToken, address(facility)),
            100,
            "Liabilities roll back"
        );
        assertEq(
            depositManager.getBorrowedAmount(iReserveToken, address(facility)),
            0,
            "No borrowed principal"
        );
        assertEq(
            depositManager.getAssetDepositCapStatus(iReserveToken).utilization,
            100,
            "Cap utilization rolls back"
        );
        _assertReceiptTokenBalance(recipient, 100, wrapped_);
        assertEq(
            _getWrappedReceiptToken(iReserveToken, PERIOD_MONTHS).totalSupply(),
            wrappedSupply,
            "Wrapper supply rolls back"
        );
        assertEq(convertibleDepositPositions.getPositionCount(), 0, "No DEPOS position created");
        assertEq(
            convertibleDepositPositions.getUserPositionIds(recipient).length,
            0,
            "No user position index"
        );
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the deposit is not configured
    //  [X] it reverts

    function test_givenDepositIsNotConfigured_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertInvalidConfiguration(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS + 1, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the caller has not approved the deposit manager to spend the asset
    //  [X] it reverts

    function test_givenCallerHasNotApprovedDepositManagerToSpendAsset_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, true);
    }

    // given the caller does not have the required asset balance
    //  [X] it reverts

    function test_givenCallerDoesNotHaveRequiredAssetBalance_reverts()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT + 1
        )
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        facility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT + 1, true);
    }

    // when wrap receipt is true
    //  [X] it transfers the asset from the caller
    //  [X] it transfers the wrapped receipt token to the caller
    //  [X] it returns the receipt token id
    //  [X] it returns the actual deposit amount
    //  [X] it does not create a position

    function test_whenWrapReceiptIsTrue()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = facility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            true
        );

        // Assert that the receipt token id is correct
        assertEq(receiptTokenId, expectedReceiptTokenId, "receiptTokenId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the wrapped receipt token amount is correct
        assertApproxEqAbs(actualDepositAmount, RESERVE_TOKEN_AMOUNT, 1, "actualDepositAmount");

        // Assert that the wrapped receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualDepositAmount, true);

        // Assert that the recipient does not have a DEPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 0, "positionIds.length");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(actualDepositAmount);
    }

    // [X] it transfers the asset from the caller
    // [X] it transfers the receipt token to the caller
    // [X] it returns the receipt token id
    // [X] it returns the actual deposit amount
    // [X] it does not create a position

    /// forge-config: default.isolate = true
    function test_success()
        public
        givenLocallyActive
        givenRecipientHasReserveToken
        givenReserveTokenSpendingIsApprovedByRecipient
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS,
            address(facility)
        );

        // Start gas snapshot
        vm.startSnapshotGas("deposit");

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = facility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false
        );

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assert that the receipt token id is correct
        assertEq(receiptTokenId, expectedReceiptTokenId, "receiptTokenId");

        // Assert that the reserve token was transferred from the recipient
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualDepositAmount, false);

        // Assert that the recipient does not have a DEPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 0, "positionIds.length");

        // Assert that the available deposits are correct
        _assertAvailableDeposits(actualDepositAmount);
    }

    function test_givenTwoFacilities_whenSharedAssetCapIsFilled_rejectsFurtherDeposit() public {
        uint256 depositCap = RESERVE_TOKEN_AMOUNT * 2;
        vm.startPrank(admin);
        facility.enable("");
        depositManager.setAssetDepositCap(iReserveToken, depositCap);
        vm.stopPrank();

        reserveToken.mint(recipient, RESERVE_TOKEN_AMOUNT);
        reserveToken.mint(recipientTwo, RESERVE_TOKEN_AMOUNT + 1);
        vm.prank(recipient);
        reserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        vm.prank(recipientTwo);
        reserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT + 1);

        vm.prank(recipient);
        (, uint256 firstCredit) = facility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false
        );
        vm.prank(recipientTwo);
        (, uint256 secondCredit) = facilityTwo.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false
        );

        assertEq(firstCredit, RESERVE_TOKEN_AMOUNT, "first facility credit");
        assertEq(secondCredit, RESERVE_TOKEN_AMOUNT, "second facility credit");
        assertEq(
            depositManager.getAssetDepositCapStatus(iReserveToken).utilization,
            depositCap,
            "shared asset-cap utilization"
        );

        vm.prank(recipientTwo);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(iReserveToken),
                depositCap,
                depositCap
            )
        );
        facilityTwo.deposit(iReserveToken, PERIOD_MONTHS, 1, false);

        assertEq(reserveToken.balanceOf(recipientTwo), 1, "rejected deposit rolled back");
    }
}

// forge-lint: disable-end(unused-return)
