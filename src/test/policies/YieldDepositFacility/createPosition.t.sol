// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract YieldDepositFacilityCreatePositionTest is YieldDepositFacilityTest {
    event CreatedDeposit(
        address indexed asset,
        address indexed depositor,
        uint256 indexed positionId,
        uint8 periodMonths,
        uint256 depositAmount
    );

    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.createPosition(
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false,
            false
        );
    }

    // given the asset is not yield-bearing
    //  [X] it reverts

    function test_givenAssetIsNotYieldBearing_reverts() public givenLocallyActive {
        // Create a new asset
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);
        vm.prank(admin);
        depositManager.configureAssetVault(IERC20(address(newAsset)), IERC4626(address(0)));
        IERC20 iNewAsset = IERC20(address(newAsset));

        // Expect revert
        _expectRevertInvalidToken(iNewAsset, PERIOD_MONTHS);

        // Call function
        vm.prank(recipient);
        yieldDepositFacility.createPosition(
            iNewAsset,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT,
            false,
            false
        );
    }

    // when the recipient has not approved CDEPO to spend the reserve tokens
    //  [X] it reverts

    function test_spendingNotApproved_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);
    }

    // given the deposit asset has 6 decimals
    //  [X] the amount of CD tokens minted is correct

    function test_reserveTokenHasSmallerDecimals()
        public
        givenReserveTokenHasDecimals(6)
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 10e6)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 10e6)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(address(reserveToken), recipient, 0, PERIOD_MONTHS, 10e6);

        // Call function
        (
            uint256 actualPositionId,
            uint256 actualReceiptTokenId,
            uint256 actualAmount
        ) = _createYieldDepositPosition(recipient, 10e6);

        // Assert that the position ID is 0
        assertEq(actualPositionId, 0, "positionId");

        // Assert that the receipt token ID is correct
        assertEq(actualReceiptTokenId, _receiptTokenId, "_receiptTokenId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(actualPositionId).conversionPrice,
            type(uint256).max,
            "conversionPrice"
        );

        // Assert that the actual amount is correct
        assertApproxEqAbs(actualAmount, 10e6, 1, "actualAmount");

        // Assert that the reserve token was transferred from the recipient
        _assertReserveTokenBalance(0);

        // Assert that the CDEPO token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualAmount, false);

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");
    }

    // [X] it mints the CD tokens to account_
    // [X] it creates a new position in the CDPOS module
    // [X] the position does not have a conversion price
    // [X] it returns the position ID
    // [X] it emits a CreatedDeposit event
    // [X] it sets the last yield conversion rate

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
        uint256 lastYieldConversionRate = vault.convertToAssets(1e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreatedDeposit(
            address(reserveToken),
            recipient,
            0,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        );

        // Call function
        (
            uint256 actualPositionId,
            uint256 actualReceiptTokenId,
            uint256 actualAmount
        ) = _createYieldDepositPosition(recipient, RESERVE_TOKEN_AMOUNT);

        // Assert that the position ID is 0
        assertEq(actualPositionId, 0, "positionId");

        // Assert that the receipt token ID is correct
        assertEq(actualReceiptTokenId, _receiptTokenId, "_receiptTokenId");

        // Assert that the conversion price is correct
        assertEq(
            convertibleDepositPositions.getPosition(actualPositionId).conversionPrice,
            type(uint256).max,
            "conversionPrice"
        );

        // Assert that the actual amount is correct
        assertApproxEqAbs(actualAmount, RESERVE_TOKEN_AMOUNT, 1, "actualAmount");

        // Assert that the position is not convertible
        assertEq(
            convertibleDepositPositions.isConvertible(actualPositionId),
            false,
            "isConvertible"
        );

        // Assert that the reserve token was transferred from the recipient
        _assertReserveTokenBalance(0);

        // Assert that the receipt token token was minted to the recipient
        _assertReceiptTokenBalance(recipient, actualAmount, false);

        // Assert that the recipient has a CDPOS position
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(positionIds.length, 1, "positionIds.length");
        assertEq(positionIds[0], 0, "positionIds[0]");

        // Assert that the last yield conversion rate is set
        assertEq(
            yieldDepositFacility.positionLastYieldConversionRate(actualPositionId),
            lastYieldConversionRate,
            "positionLastYieldConversionRate"
        );
    }
}
