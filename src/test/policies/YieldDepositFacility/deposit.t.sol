// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract YieldDepositFacilityDepositTest is YieldDepositFacilityTest {
    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, false);
    }

    // given the deposit is not configured
    //  [X] it reverts

    function test_givenDepositIsNotConfigured_reverts() public givenLocallyActive {
        // Expect revert
        _expectRevertDepositManagerInvalidConfiguration(iReserveToken, PERIOD_MONTHS + 1);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.deposit(iReserveToken, PERIOD_MONTHS + 1, RESERVE_TOKEN_AMOUNT, false);
    }

    // given the asset is not yield-bearing
    //  [X] it reverts

    function test_givenAssetIsNotYieldBearing_reverts() public givenLocallyActive {
        // Create a new asset
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);
        vm.prank(admin);
        depositManager.addAsset(IERC20(address(newAsset)), IERC4626(address(0)), type(uint256).max);
        IERC20 iNewAsset = IERC20(address(newAsset));

        // Expect revert
        _expectRevertInvalidToken(iNewAsset, PERIOD_MONTHS);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.deposit(iNewAsset, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, false);
    }

    // given the caller has not approved the deposit manager to spend the asset
    //  [X] it reverts

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT, false);
    }

    // given the caller does not have the required asset balance
    //  [X] it reverts

    function test_insufficientBalance_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT + 1
        )
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.deposit(iReserveToken, PERIOD_MONTHS, RESERVE_TOKEN_AMOUNT + 1, false);
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
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS
        );

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = yieldDepositFacility.deposit(
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
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(depositManager),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iReserveToken,
            PERIOD_MONTHS
        );

        // Start gas snapshot
        vm.startSnapshotGas("deposit");

        // Call function
        vm.prank(recipient);
        (uint256 receiptTokenId, uint256 actualDepositAmount) = yieldDepositFacility.deposit(
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

        // Assert that the receipt token amount is correct
        assertApproxEqAbs(actualDepositAmount, RESERVE_TOKEN_AMOUNT, 1, "actualDepositAmount");

        // Assert that the receipt token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualDepositAmount, false);

        // Assert that the recipient does not have a DEPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 0, "positionIds.length");
    }
}
