// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
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

    // when timestamp hints are provided
    //  when the number of hints is not the same as the number of positions
    //   [X] it reverts

    function test_withTimestampHints_incorrectLength_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InvalidArgs.selector,
                "array length mismatch"
            )
        );

        // Prepare inputs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        uint48[] memory positionTimestampHints = new uint48[](2);
        positionTimestampHints[0] = 1;
        positionTimestampHints[1] = 2;

        // Attempt to preview harvest
        yieldDepositFacility.previewClaimYield(recipient, positionIds, positionTimestampHints);
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
        // Last conversion rate = 1100000000000000000
        // Current conversion rate = 1155000000000000000
        // Deposit amount = 9000000000000000000
        // Deposit shares = 8181818181818181818 (at the time of deposit)
        // Yield/share = 1155000000000000000-1100000000000000000 = 55000000000000000 (in terms of assets per share)
        // Actual yield = yield/share * shares
        // Actual yield = 55000000000000000 * 8181818181818181818 / 1e18 = 449999999999999999.99
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * lastShares) / 1e18;
        assertEq(expectedYield, 449999999999999999, "Expected yield");
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
        // last conversion rate = 1155000000000000000
        // current conversion rate = 1211204379562043795
        // deposit amount = 9000000000000000000
        // deposit shares = 7792207792207792207 (at the time of last claim)
        // Yield/share = 1211204379562043795 - 1155000000000000000 = 56204379562043795 (in terms of assets per share)
        // Actual yield = yield/share * shares
        // Actual yield = 56204379562043795 * 7792207792207792207 / 1e18 = 437956204379562038
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * lastShares) / 1e18;
        assertEq(expectedYield, 437956204379562038, "Expected yield");
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

    function test_withTimestampHints_whenExpired_timestampHintAfterExpiry_reverts(
        uint48 timestampHint_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Timestamp hint after expiry
        timestampHint_ = uint48(bound(timestampHint_, YIELD_EXPIRY + 1, harvestTimestamp));

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = timestampHint_;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_InvalidArgs.selector, "timestamp hint")
        );

        // Preview harvest yield
        yieldDepositFacility.previewClaimYield(recipient, positionIds, positionTimestampHints);
    }

    //    given the rounded timestamp hint does not have a rate snapshot
    //     [X] it reverts

    function test_withTimestampHints_whenExpired_noRateSnapshot_reverts(
        uint48 before_,
        uint48 timestampHint_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Last snapshot up to 2 days before expiry
        before_ = uint48(bound(before_, 8 hours, 2 days));
        uint48 snapshotTimestampRounded = _getRoundedTimestamp(YIELD_EXPIRY - before_);

        // Timestamp hint does not overlap with the rounded snapshot timestamp
        timestampHint_ = uint48(
            bound(timestampHint_, snapshotTimestampRounded + 8 hours, YIELD_EXPIRY)
        );

        // Move to before the end of the deposit period
        vm.warp(YIELD_EXPIRY - before_);

        // Take a rate snapshot
        _takeRateSnapshot();

        // Accrue yield (which would change the rate snapshot)
        _accrueYield(iVault, 1e18);

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = timestampHint_;

        uint48 timestampHintRounded = _getRoundedTimestamp(timestampHint_);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoSnapshotAvailable.selector,
                address(iVault),
                timestampHintRounded
            )
        );

        // Preview harvest yield
        yieldDepositFacility.previewClaimYield(recipient, positionIds, positionTimestampHints);
    }

    //    [X] it returns the yield for the conversion rate at the rounded timestamp hint

    function test_withTimestampHints_whenExpired_givenRateSnapshotBeforeExpiry(
        uint48 before_,
        uint48 elapsed_,
        uint48 timestampHint_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        // Last snapshot up to 2 days before expiry
        // Needs to be at least 8 hours to avoid issues with the timestamp hint > expiry
        before_ = uint48(bound(before_, 8 hours, 2 days));
        uint48 beforeRounded = _getRoundedTimestamp(YIELD_EXPIRY - before_);
        // Time of harvest up to 1 day after expiry
        elapsed_ = uint48(bound(elapsed_, 1, 1 days));
        // Timestamp hint from rounded before timestamp until just before the next rounded timestamp
        timestampHint_ = uint48(bound(timestampHint_, beforeRounded, beforeRounded + 8 hours - 1));

        // Move to before the end of the deposit period
        vm.warp(YIELD_EXPIRY - before_);

        // Take a rate snapshot
        _takeRateSnapshot();
        uint256 rateSnapshotConversionRate = vault.convertToAssets(1e18);

        // Accrue yield (which would change the rate snapshot)
        _accrueYield(iVault, 1e18);

        // Warp to beyond expiry
        vm.warp(YIELD_EXPIRY + elapsed_);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = timestampHint_;

        // Calculate expected yield and fee
        // As the expiry is in the past, this will take the last rate snapshot
        // Last conversion rate = 1100000000000000000
        // Rate snapshot conversion rate = 1155000000000000000
        // Deposit amount = 9000000000000000000
        // Deposit shares = 8181818181818181818 (at the time of deposit)
        // Yield/share = 1155000000000000000-1100000000000000000 = 55000000000000000 (in terms of assets per share)
        // Actual yield = yield/share * shares
        // Actual yield = 55000000000000000 * 8181818181818181818 / 1e18 = 449999999999999999.99
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = ((rateSnapshotConversionRate - lastConversionRate) * lastShares) /
            1e18;
        assertEq(expectedYield, 449999999999999999, "Expected yield");
        uint256 expectedFee = (expectedYield * 1000) / 10000;

        // Preview claim yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds,
            positionTimestampHints
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

    //   [X] it reverts

    function test_withTimestampHints_whenExpired_noTimestampHint_reverts(
        uint48 before_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Last snapshot up to 2 days before expiry
        before_ = uint48(bound(before_, 8 hours, 2 days));

        // Move to before the end of the deposit period
        vm.warp(YIELD_EXPIRY - before_);

        // Take a rate snapshot
        _takeRateSnapshot();

        // Accrue yield (which would change the rate snapshot)
        _accrueYield(iVault, 1e18);

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = 0;

        uint48 roundedExpiry = _getRoundedTimestamp(YIELD_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoSnapshotAvailable.selector,
                address(iVault),
                roundedExpiry
            )
        );

        // Harvest yield
        yieldDepositFacility.previewClaimYield(recipient, positionIds, positionTimestampHints);
    }

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
        // Last conversion rate = 1100000000000000000
        // Current conversion rate = 1155000000000000000
        // Deposit amount = 9000000000000000000
        // Deposit shares = 8181818181818181818 (at the time of deposit)
        // Yield/share = 1155000000000000000-1100000000000000000 = 55000000000000000 (in terms of assets per share)
        // Actual yield = yield/share * shares
        // Actual yield = 55000000000000000 * 8181818181818181818 / 1e18 = 449999999999999999.99
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * lastShares) / 1e18;
        assertEq(expectedYield, 449999999999999999, "Expected yield");
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
