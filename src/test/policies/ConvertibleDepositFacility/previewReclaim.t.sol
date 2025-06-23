// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

contract ConvertibleDepositFacilityPreviewReclaimTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts

    function test_contractInactive_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        facility.previewReclaim(iReserveToken, PERIOD_MONTHS, 1e18);
    }

    // when the amount of receipt tokens to reclaim is 0
    //  [X] it reverts

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        facility.previewReclaim(iReserveToken, PERIOD_MONTHS, 0);
    }

    // when the reclaimed amount is 0
    //  [X] it reverts

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        _expectRevertRedemptionVaultZeroAmount();

        // Call function
        facility.previewReclaim(iReserveToken, PERIOD_MONTHS, amount);
    }

    // [X] it returns the total amount of deposit token that would be reclaimed
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(depositManager), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // 3+ so that the reclaimed amount is not 0
        uint256 amount = bound(amount_, 3, 9e18);

        // Calculate the amount that will be reclaimed
        uint256 expectedReclaimed = (amount *
            depositManager.getDepositReclaimRate(iReserveToken, PERIOD_MONTHS)) / 100e2;

        // Call function
        uint256 reclaimed = facility.previewReclaim(iReserveToken, PERIOD_MONTHS, amount);

        // Assertion that the reclaimed amount is the sum of the amounts adjsuted by the reclaim rate
        assertEq(reclaimed, expectedReclaimed, "reclaimed");
    }
}
