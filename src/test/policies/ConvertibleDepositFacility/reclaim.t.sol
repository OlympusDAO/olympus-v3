// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract ReclaimCDFTest is ConvertibleDepositFacilityTest {
    event ReclaimedDeposit(address indexed user, uint256 reclaimedAmount, uint256 forfeitedAmount);

    // given the contract is inactive
    //  [X] it reverts
    // when the amount of CD tokens to reclaim is 0
    //  [X] it reverts
    // when the reclaimed amount is 0
    //  [X] it reverts
    // given the caller has not approved CDEPO to spend the total amount of CD tokens
    //  [X] it reverts
    // [X] it transfers the reclaimed reserve tokens to the caller
    // [X] it returns the reclaimed amount
    // [X] it emits a ReclaimedDeposit event
    // [X] the OHM mint approval is not changed

    function test_contractInactive_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        facility.reclaim(1e18);
    }

    function test_amountToReclaimIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(0);
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
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "allowance")
        );

        // Call function
        vm.prank(recipient);
        facility.reclaim(RESERVE_TOKEN_AMOUNT);
    }

    function test_reclaimedAmountIsZero_reverts()
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
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
        vm.prank(recipient);
        facility.reclaim(amount);
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
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 expectedReclaimedAmount = (RESERVE_TOKEN_AMOUNT *
            convertibleDepository.reclaimRate(address(iReserveToken))) / 100e2;
        uint256 expectedForfeitedAmount = RESERVE_TOKEN_AMOUNT - expectedReclaimedAmount;

        uint256 beforeMintApproval = minter.mintApproval(address(facility));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimedDeposit(recipient, expectedReclaimedAmount, expectedForfeitedAmount);

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(RESERVE_TOKEN_AMOUNT);

        // Assertion that the reclaimed amount is the sum of the amounts adjusted by the reclaim rate
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(_getCDToken().balanceOf(recipient), 0, "_getCDToken().balanceOf(recipient)");

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // No dangling mint approval
        assertEq(
            minter.mintApproval(address(facility)),
            beforeMintApproval,
            "minter.mintApproval(address(facility))"
        );

        // Deposit token is transferred to the recipient
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
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Vault shares are not transferred to the TRSRY
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }

    function test_success_fuzz(
        uint256 amount_
    )
        public
        givenLocallyActive
        givenAddressHasReserveToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenReserveTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
        mintConvertibleDepositToken(recipient, RESERVE_TOKEN_AMOUNT)
        givenConvertibleDepositTokenSpendingIsApproved(
            recipient,
            address(convertibleDepository),
            RESERVE_TOKEN_AMOUNT
        )
    {
        uint256 amountOne = bound(amount_, 3, RESERVE_TOKEN_AMOUNT);

        // Calculate the amount that will be reclaimed
        uint256 expectedReclaimedAmount = (amountOne *
            convertibleDepository.reclaimRate(address(iReserveToken))) / 100e2;
        uint256 expectedForfeitedAmount = amountOne - expectedReclaimedAmount;

        uint256 beforeMintApproval = minter.mintApproval(address(facility));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReclaimedDeposit(recipient, expectedReclaimedAmount, expectedForfeitedAmount);

        // Call function
        vm.prank(recipient);
        uint256 reclaimed = facility.reclaim(amountOne);

        // Assert reclaimed amount
        assertEq(reclaimed, expectedReclaimedAmount, "reclaimed");

        // Assert convertible deposit tokens are transferred from the recipient
        assertEq(
            _getCDToken().balanceOf(recipient),
            RESERVE_TOKEN_AMOUNT - amountOne,
            "_getCDToken().balanceOf(recipient)"
        );

        // Assert OHM not minted to the recipient
        assertEq(ohm.balanceOf(recipient), 0, "ohm.balanceOf(recipient)");

        // Assert the remaining mint approval
        assertEq(minter.mintApproval(address(facility)), beforeMintApproval, "mintApproval");

        // Deposit token is transferred to the recipient
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
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedReclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );

        // Vault shares are not transferred to the TRSRY
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }
}
