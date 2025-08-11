// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract YieldDepositFacilityClaimYieldTest is YieldDepositFacilityTest {
    event YieldClaimed(address indexed asset, address indexed depositor, uint256 yield);

    uint256 internal constant DEPOSIT_AMOUNT = 9e18;
    uint256 internal constant POSITION_ID = 0;

    function _convertAssetsToShares(uint256 amount_) internal view returns (uint256) {
        return iVault.convertToShares(amount_);
    }

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
        givenWarpForward(1) // Requires gap between snapshots
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
        // Yield fee = 449999999999999990 * 1000 / 10000 = 44999999999999999
        // Claimed yield = 449999999999999990 - 44999999999999999 = 404999999999999991
        uint256 currentConversionRate = 1155000000000000000;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 44999999999999999;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertApproxEqAbs(
            previewedYield,
            expectedYield - expectedFee,
            1,
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
            currentConversionRate,
            uint48(block.timestamp)
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
        givenWarpForward(1) // Requires gap between snapshots
        givenHarvest(recipient, POSITION_ID)
        givenWarpForward(1 days)
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // Last conversion rate = 1155000000000000000 + 1
        // Deposit amount = 9000000000000000000
        // Last shares = 9000000000000000000 * 1e18 / 1155000000000000001 = 7792207792207792201
        // End conversion rate = 1211204379562043795
        // Current shares value = last shares * end rate / 1e18
        // = 7792207792207792201 * 1211204379562043795 / 1e18 = 9437956204379562030
        // Yield = current shares value - receipt tokens
        // = 9437956204379562030 - 9000000000000000000 = 437956204379562030
        // Yield fee = 437956204379562030 * 1000 / 10000 = 43795620437956203
        // Claimed yield = 437956204379562030 - 43795620437956203 = 394160583941605827
        uint256 currentConversionRate = 1211204379562043795;
        uint256 expectedYield = 437956204379562030;
        uint256 expectedFee = 43795620437956203;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertApproxEqAbs(
            previewedYield,
            expectedYield - expectedFee,
            1,
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
            currentConversionRate,
            uint48(block.timestamp)
        );
    }

    // given the position has expired
    //  given a rate snapshot is not available for the expiry timestamp
    //   given a timestamp hint is provided

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
        // Deposit amount = 8999999999999999999
        // Last shares = 8999999999999999999 * 1e18 / 1100000000000000001 = 8181818181818181809
        // End conversion rate = 1210000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181809 * 1210000000000000000 / 1e18 = 9899999999999999988
        // Yield = current shares value - receipt tokens
        // = 9899999999999999988 - 8999999999999999999 = 899999999999999989
        // Yield fee = 899999999999999989 * 1000 / 10000 = 89999999999999998
        // Claimed yield = 899999999999999989 - 89999999999999998 = 809999999999999991
        uint256 currentConversionRate = 1210000000000000000;
        uint256 expectedYield = 899999999999999989;
        uint256 expectedFee = 89999999999999998;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

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
            currentConversionRate,
            YIELD_EXPIRY // Matches givenRateSnapshotTaken() call
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
        assertEq(
            _previousDepositActualAmount,
            8999999999999999999,
            "Previous deposit amount mismatch"
        );

        // Move beyond the end of the deposit period
        vm.warp(YIELD_EXPIRY + 1);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        // Last conversion rate = 1100000000000000000 + 1
        // Deposit amount = 8999999999999999999
        // Last shares = 8999999999999999999 * 1e18 / 1100000000000000001 = 8181818181818181809
        // End conversion rate = 1155000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 8181818181818181809 * 1155000000000000000 / 1e18 = 9449999999999999989
        // Yield = current shares value - receipt tokens
        // = 9449999999999999989 - 8999999999999999999 = 449999999999999990
        // Yield fee = 449999999999999990 * 1000 / 10000 = 44999999999999999
        // Claimed yield = 449999999999999990 - 44999999999999999 = 404999999999999991
        uint256 rateSnapshotConversionRate = 1155000000000000000;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 44999999999999999;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

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
            rateSnapshotConversionRate,
            YIELD_EXPIRY // Matches givenRateSnapshotTaken() call
        );
    }

    function test_whenExpired_givenRateSnapshotOnExpiry_zeroYield()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken // block: 1000000
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
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            0,
            0,
            0,
            0,
            rateSnapshotConversionRate,
            1000000 // Matches givenRateSnapshotTaken() call
        );
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
        // Last shares = 1000000000000000000 * 1e18 / 1000000000000000001 = 999999999999999999
        // End conversion rate = 1500000000000000000
        // Current shares value = last shares * end rate / 1e18
        // = 999999999999999999 * 1500000000000000000 / 1e18 = 1499999999999999998
        // Yield = current shares value - receipt tokens
        // = 1499999999999999998 - 1000000000000000000 = 499999999999999998
        // Yield fee = 499999999999999998 * 1000 / 10000 = 49999999999999999
        // Claimed yield = 499999999999999998 - 49999999999999999 = 449999999999999999
        uint256 expectedYield = 499999999999999998;
        uint256 expectedFee = 49999999999999999;

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
        // Yield fee = 449999999999999990 * 1000 / 10000 = 44999999999999999
        // Claimed yield = 449999999999999990 - 44999999999999999 = 404999999999999991
        uint256 rateSnapshotConversionRate = 1155000000000000000;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 44999999999999999;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

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
            rateSnapshotConversionRate,
            YIELD_EXPIRY // Matches givenRateSnapshotTaken() call
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
        givenWarpForward(1) // Requires gap between snapshots
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
        uint256 currentConversionRate = 1155000000000000000;
        uint256 expectedYield = 449999999999999990;
        uint256 expectedFee = 0;
        uint256 expectedYieldShares = _convertAssetsToShares(expectedYield);

        // Revise expectedYield based on the shares
        expectedYield = iVault.previewRedeem(expectedYieldShares);

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewClaimYield(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertApproxEqAbs(
            previewedYield,
            expectedYield - expectedFee,
            1,
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
            currentConversionRate,
            uint48(block.timestamp)
        );
    }

    // given yield is claimed multiple times in the same block
    //  [X] the second claim should return 0 yield
    //  [X] the second claim should emit event with 0 yield
    //  [X] the second claim should not transfer any tokens

    function test_whenClaimedMultipleTimesInSameBlock()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000) // 10%
        givenWarpForward(1) // Requires gap between snapshots
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Claim yield the first time
        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Store balances after first claim
        uint256 balanceAfterFirstClaim = reserveToken.balanceOf(recipient);
        uint256 treasuryBalanceAfterFirstClaim = reserveToken.balanceOf(address(treasury));

        // Second claim in the same block should return 0 yield
        vm.expectEmit(true, true, true, true);
        emit YieldClaimed(address(reserveToken), recipient, 0);

        vm.prank(recipient);
        yieldDepositFacility.claimYield(positionIds);

        // Assert balances unchanged after second claim
        assertEq(
            reserveToken.balanceOf(recipient),
            balanceAfterFirstClaim,
            "Recipient balance should not change on second claim"
        );
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            treasuryBalanceAfterFirstClaim,
            "Treasury balance should not change on second claim"
        );
    }
}
