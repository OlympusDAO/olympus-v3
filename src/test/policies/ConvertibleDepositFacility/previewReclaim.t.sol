// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract PreviewReclaimCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts
    // when the amount of CD tokens to reclaim is 0
    //  [X] it reverts
    // when the reclaimed amount is 0
    //  [X] it reverts
    // [X] it returns the total amount of deposit token that would be reclaimed
    // [X] it returns the address that will spend the convertible deposit tokens

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        facility.previewReclaim(cdToken, 1e18);
    }

    function test_amountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        facility.previewReclaim(cdToken, 0);
    }

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // Will round down to 0 after the reclaim rate is applied
        uint256 amount = 1;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepository.CDEPO_InvalidArgs.selector,
                "reclaimed amount"
            )
        );

        // Call function
        facility.previewReclaim(cdToken, amount);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, 9e18)
        givenReserveTokenSpendingIsApproved(recipient, address(convertibleDepository), 9e18)
        mintConvertibleDepositToken(recipient, 9e18)
    {
        // 3+ so that the reclaimed amount is not 0
        uint256 amount = bound(amount_, 3, 9e18);

        // Calculate the amount that will be reclaimed
        uint256 expectedReclaimed = (amount * convertibleDepository.reclaimRate(address(cdToken))) /
            100e2;

        // Call function
        (uint256 reclaimed, address spender) = facility.previewReclaim(cdToken, amount);

        // Assertion that the reclaimed amount is the sum of the amounts adjsuted by the reclaim rate
        assertEq(reclaimed, expectedReclaimed, "reclaimed");

        // Assertion that the spender is the convertible depository
        assertEq(spender, address(convertibleDepository), "spender");
    }
}
