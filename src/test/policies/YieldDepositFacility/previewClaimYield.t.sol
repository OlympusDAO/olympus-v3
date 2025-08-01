// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract YieldDepositFacilityPreviewClaimYieldTest is YieldDepositFacilityTest {
    uint256 public DEPOSIT_AMOUNT = 9e18;
    uint256 public POSITION_ID = 0;

    // given the contract is disabled
    //  [X] it reverts

    function test_whenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Attempt to preview harvest
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewClaimYield(recipient, positionIds);
    }

    // given the position does not exist
    //  [X] it reverts

    function test_whenPositionDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_InvalidPositionId.selector,
                POSITION_ID
            )
        );

        // Attempt to preview harvest non-existent position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewClaimYield(recipient, positionIds);
    }

    // given the position was not created by the YDF
    //  [X] it reverts

    function test_givenPositionNotCreatedByYDF_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
        givenAddressHasConvertibleDepositPosition(recipient, 1e18, 2e18)
    {
        // Expect revert
        _expectRevertUnsupported(POSITION_ID);

        // Attempt to preview harvest non-existent position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewClaimYield(recipient, positionIds);
    }

    // given the position is convertible
    //  [X] it reverts

    function test_whenConvertible_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenAddressHasReserveToken(recipient, 1e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 1e18)
    {
        uint256 positionId = _createConvertibleDepositPosition(recipient, 1e18, 2e18);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_Unsupported.selector, positionId)
        );

        // Attempt to preview harvest convertible position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;
        yieldDepositFacility.previewClaimYield(recipient, positionIds);
    }

    // given the provided recipient is not the owner of the position
    //  [X] it reverts

    function test_whenNotOwner_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_NotOwner.selector, POSITION_ID)
        );

        // Attempt to preview harvest as non-owner
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewClaimYield(recipientTwo, positionIds);
    }

    // given any position has a different receipt token
    //  [X] it reverts

    function test_whenDifferentReceiptToken_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Create a yield position for the second receipt token
        _mintToken(iReserveTokenTwo, recipient, 1e18);
        _approveTokenSpending(iReserveTokenTwo, recipient, address(depositManager), 1e18);
        vm.prank(recipient);
        (uint256 positionId, , ) = yieldDepositFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveTokenTwo,
                periodMonths: PERIOD_MONTHS,
                amount: 1e18,
                wrapPosition: false,
                wrapReceipt: false
            })
        );

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InvalidArgs.selector,
                "multiple tokens"
            )
        );

        // Attempt to preview harvest positions with different receipt tokens
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = POSITION_ID;
        positionIds[1] = positionId;
        yieldDepositFacility.previewClaimYield(recipient, positionIds);
    }

    // given the owner has never claimed yield
    //  [X] it returns the yield since minting, with a fee deduction

    function test_whenNeverClaimed()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000) // 10%
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount = 9000000000000000000
        // Last shares = 9000000000000000000 * 1e18 / 1100000000000000001 = 8181818181818181810
        // End conversion rate = 1155000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181810 * 1155000000000000000 / 1e18 = 9449999999999999990
        // Yield = current shares value - receipt tokens
        // = 9449999999999999990 - 9000000000000000000 = 449999999999999990
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(
            previewedYield,
            expectedYield - expectedFee,
            "Previewed yield does not match expected"
        );
        assertEq(
            address(previewedAsset),
            address(reserveToken),
            "Previewed asset does not match expected"
        );
    }

    // given the owner has claimed yield
    //  [X] it returns the yield since the last claim, with a fee deduction

    function test_whenClaimed()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenHarvest(recipient, POSITION_ID)
        givenWarpForward(1 days)
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // last conversion rate = 1155000000000000000 + 1
        // current conversion rate = 1211204379562043795
        // deposit amount = 9000000000000000000
        // deposit shares = 7792207792207792201 (at the time of last claim)
        // Yield/share = 1211204379562043795 - 1155000000000000001 = 56204379562043794 (in terms of assets per share)
        // Actual yield = yield/share * shares
        // Actual yield = 56204379562043794 * 7792207792207792201 / 1e18 = 437956204379562030
        uint256 expectedYield = 437956204379562030;
        uint256 expectedFee = (expectedYield * 1000) / 10000;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(
            previewedYield,
            expectedYield - expectedFee,
            "Previewed yield does not match expected"
        );
        assertEq(
            address(previewedAsset),
            address(reserveToken),
            "Previewed asset does not match expected"
        );
    }

    // given the position has expired
    //   given a timestamp hint is provided
    //    given the timestamp hint is not before the expiry
    //     [X] it reverts

    // given the yield fee is 0
    //  [X] it returns the yield without any fee deduction

    function test_whenZeroFee()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(0)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount = 9000000000000000000
        // Last shares = 9000000000000000000 * 1e18 / 1100000000000000001 = 8181818181818181810
        // End conversion rate = 1155000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181810 * 1155000000000000000 / 1e18 = 9449999999999999990
        // Yield = current shares value - receipt tokens
        // = 9449999999999999990 - 9000000000000000000 = 449999999999999990
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 0;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(
            previewedYield,
            expectedYield - expectedFee,
            "Previewed yield does not match expected"
        );
        assertEq(
            address(previewedAsset),
            address(reserveToken),
            "Previewed asset does not match expected"
        );
    }
}
