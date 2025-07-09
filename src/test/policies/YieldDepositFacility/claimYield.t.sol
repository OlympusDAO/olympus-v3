// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract YieldDepositFacilityClaimYieldTest is YieldDepositFacilityTest {
    event YieldClaimed(address indexed asset, address indexed depositor, uint256 yield);

    uint256 public DEPOSIT_AMOUNT = 9e18;
    uint256 public POSITION_ID = 0;

    // given the contract is disabled
    //  [X] it reverts

    function test_whenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Attempt to harvest
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);
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

        // Attempt to harvest non-existent position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);
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

        // Attempt to harvest position not created by YDF
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);
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

        // Attempt to harvest
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds, positionTimestampHints);
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

        // Attempt to harvest convertible position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);
    }

    // given the position is not the owner of the position
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

        // Attempt to harvest as non-owner
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipientTwo);
        yieldDepositFacility.claimYield(positionIds);
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

        // Attempt to harvest positions with different receipt tokens
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = POSITION_ID;
        positionIds[1] = positionId;
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);
    }

    // given the owner has never claimed yield
    //  [X] it returns the yield since minting
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the DepositManager module

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
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = 1155000000000000000 + 1;
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

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

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }

    // given the owner has claimed yield
    //  [X] it returns the yield since the last claim
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the DepositManager module

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
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = 1211204379562043795 + 1;
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = 437956204379562030;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

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

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }

    // given the position has expired
    //  given a rate snapshot is not available for the expiry timestamp
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

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds, positionTimestampHints);
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

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds, positionTimestampHints);
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
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount = 9000000000000000000
        // Last shares = 9000000000000000000 * 1e18 / 1100000000000000001 = 8181818181818181810
        // End conversion rate = 1155000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181810 * 1155000000000000000 / 1e18 = 9449999999999999990
        // Yield = current shares value - receipt tokens
        // = 9449999999999999990 - 9000000000000000000 = 449999999999999990
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = 1155000000000000000 + 1;
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

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

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds, positionTimestampHints);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
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
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds, positionTimestampHints);
    }

    //  [X] it returns the yield up to the conversion rate before expiry
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the DepositManager module

    function test_onExpiry()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // This will take the current rate as the end rate
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount
        // Last shares = 9000000000000000000 * 1e18 / 1100000000000000001 = 8181818181818181810
        // End conversion rate = 1210000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181810 * 1210000000000000000 / 1e18 = 9899999999999999990
        // Yield = current shares value - receipt tokens
        // = 9899999999999999990 - 9000000000000000000 = 899999999999999990
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 currentConversionRate = 1210000000000000000 + 1;
        uint256 expectedYield = 899999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }

    /// forge-config: default.isolate = true
    function test_whenExpired_givenRateSnapshotOnExpiry()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Move beyond the end of the deposit period
        vm.warp(YIELD_EXPIRY + 1);

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
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 rateSnapshotConversionRate = 1155000000000000000 + 1;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Start gas snapshot
        vm.startSnapshotGas("claimYield");

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Stop gas snapshot
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            rateSnapshotConversionRate
        );
    }

    function test_whenExpired_givenRateSnapshotOnExpiry_zeroYield()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Move beyond the end of the deposit period
        vm.warp(YIELD_EXPIRY + 1);

        uint256 rateSnapshotConversionRate = 1100000000000000001;

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, 0);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(recipient, POSITION_ID, 0, 0, 0, 0, rateSnapshotConversionRate);
    }

    function test_whenExpired_givenRateSnapshotOnExpiry_roundingError()
        public
        givenLocallyActive
        givenYieldFee(1000)
    {
        // Mint a yield deposit position
        uint256 positionId;
        uint256 actualAmount;
        {
            // Mint the deposit token
            reserveTokenTwo.mint(recipient, 1e18);

            // Approve the deposit token spending
            vm.startPrank(recipient);
            reserveTokenTwo.approve(address(depositManager), 1e18);
            vm.stopPrank();

            // Deposit the deposit token
            vm.prank(recipient);
            (positionId, , actualAmount) = yieldDepositFacility.createPosition(
                IYieldDepositFacility.CreatePositionParams({
                    asset: iReserveTokenTwo,
                    periodMonths: PERIOD_MONTHS,
                    amount: 1e18,
                    wrapPosition: false,
                    wrapReceipt: false
                })
            );
        }

        // Mint a CD deposit
        {
            // Mint the deposit token
            reserveTokenTwo.mint(recipient, 1e18);

            // Approve the deposit token spending
            vm.startPrank(recipient);
            reserveTokenTwo.approve(address(depositManager), 1e18);
            vm.stopPrank();

            // Deposit the deposit token
            vm.prank(recipient);
            cdFacility.deposit(iReserveTokenTwo, PERIOD_MONTHS, 1e18, false);
        }

        // Accrue yield to the vault
        {
            reserveTokenTwo.mint(address(iVaultTwo), 1e18);
        }

        // End the deposit period and take a rate snapshot
        {
            vm.warp(YIELD_EXPIRY);
            _takeRateSnapshot();
        }

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Calculate expected yield and fee
        // As the expiry is in the past, this will take the last rate snapshot
        // Last conversion rate = 1000000000000000000 + 1
        // Deposit amount = 1000000000000000000
        // Last shares = 999999999999999999 (at the time of deposit)
        // End conversion rate = 1500000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 999999999999999999 * 1500000000000000000 / 1e18 = 1499999999999999998
        // Yield = current shares value - receipt tokens
        // = 1499999999999999998 - 1000000000000000000 = 499999999999999998
        uint256 expectedYield = 499999999999999998;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveTokenTwo), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert caller received yield minus fee
        assertEq(
            reserveTokenTwo.balanceOf(recipient),
            recipientReserveTokenBalanceBefore + expectedYield - expectedFee,
            "Caller received incorrect yield"
        );

        // Assert treasury received fee
        assertEq(
            reserveTokenTwo.balanceOf(address(treasury)),
            treasuryReserveBalanceBefore + expectedFee,
            "Treasury received incorrect fee"
        );
    }

    function test_whenExpired_givenRateSnapshotOnExpiry_fuzz(
        uint256 yieldAmount_
    ) public givenLocallyActive givenYieldFee(1000) {
        yieldAmount_ = bound(yieldAmount_, 1, 10e18);

        // Mint a yield deposit position
        uint256 positionId;
        uint256 actualAmount;
        {
            // Mint the deposit token
            reserveTokenTwo.mint(recipient, 1e18);

            // Approve the deposit token spending
            vm.startPrank(recipient);
            reserveTokenTwo.approve(address(depositManager), 1e18);
            vm.stopPrank();

            // Deposit the deposit token
            vm.prank(recipient);
            (positionId, , actualAmount) = yieldDepositFacility.createPosition(
                IYieldDepositFacility.CreatePositionParams({
                    asset: iReserveTokenTwo,
                    periodMonths: PERIOD_MONTHS,
                    amount: 1e18,
                    wrapPosition: false,
                    wrapReceipt: false
                })
            );
        }

        // Mint a CD deposit
        {
            // Mint the deposit token
            reserveTokenTwo.mint(recipient, 1e18);

            // Approve the deposit token spending
            vm.startPrank(recipient);
            reserveTokenTwo.approve(address(depositManager), 1e18);
            vm.stopPrank();

            // Deposit the deposit token
            vm.prank(recipient);
            cdFacility.deposit(iReserveTokenTwo, PERIOD_MONTHS, 1e18, false);
        }

        // Accrue yield to the vault
        {
            reserveTokenTwo.mint(address(iVaultTwo), yieldAmount_);
        }

        // End the deposit period and take a rate snapshot
        {
            vm.warp(YIELD_EXPIRY);
            _takeRateSnapshot();
        }

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Should not revert due to insolvency
    }

    function test_whenExpired_givenRateSnapshotOnExpiry(
        uint48 elapsed_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Move beyond the end of the deposit period
        elapsed_ = uint48(bound(elapsed_, 1, 1 days));
        vm.warp(YIELD_EXPIRY + elapsed_);

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
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 rateSnapshotConversionRate = 1155000000000000000 + 1;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            rateSnapshotConversionRate
        );
    }

    // given the yield fee is 0
    //  [X] it returns the yield
    //  [X] it updates the last yield conversion rate
    //  [X] it transfers the yield to the caller
    //  [X] it does not transfer the yield fee to the treasury
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the DepositManager module

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

        // Calculate expected yield and
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount = 9000000000000000000
        // Last shares = 9000000000000000000 * 1e18 / 1100000000000000001 = 8181818181818181810
        // End conversion rate = 1155000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181810 * 1155000000000000000 / 1e18 = 9449999999999999990
        // Yield = current shares value - receipt tokens
        // = 9449999999999999990 - 9000000000000000000 = 449999999999999990
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 lastShares = (DEPOSIT_AMOUNT * 1e18) / lastConversionRate;
        uint256 currentConversionRate = 1155000000000000000 + 1;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 0;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

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

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, expectedYield - expectedFee);

        // Claim yield
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }
}
