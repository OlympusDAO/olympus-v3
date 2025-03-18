// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract PreviewSweepYieldCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when there are no deposits
    //  when the vault has assets
    //   [X] it returns zero
    //  [X] it returns zero
    // when there are deposits
    //  when there have been reclaimed deposits
    //   [X] the forfeited amount is included in the yield
    //  [X] it returns the difference between the total deposits and the total assets in the vault

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.previewSweepYield(iReserveTokenTwo);
    }

    function test_noDeposits() public {
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, 0, "yieldReserve");
        assertEq(yieldSReserve, 0, "yieldSReserve");
    }

    function test_noDeposits_withAssets_donated() public {
        // Donate assets into the vault
        reserveToken.mint(address(vault), 10e18);

        // Call function
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, 0, "yieldReserve");
        assertEq(yieldSReserve, 0, "yieldSReserve");
    }

    function test_noDeposits_withAssets()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(vault), 10e18)
    {
        // Deposit into the vault
        vm.prank(recipient);
        vault.deposit(10e18, address(recipient));

        // Call function
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, 0, "yieldReserve");
        assertEq(yieldSReserve, 0, "yieldSReserve");
    }

    function test_withDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        // Call function
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, INITIAL_VAULT_BALANCE, "yieldReserve");
        assertEq(yieldSReserve, vault.previewWithdraw(INITIAL_VAULT_BALANCE), "yieldSReserve");
    }

    function test_withReclaimedDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        // Recipient has reclaimed all of their deposit, leaving behind a forfeited amount
        // The forfeited amount is included in the yield
        vm.prank(recipient);
        CDEPO.reclaim(iReserveToken, 10e18);

        uint256 reclaimedAmount = CDEPO.previewReclaim(iReserveToken, 10e18);
        uint256 forfeitedAmount = 10e18 - reclaimedAmount;

        // Call function
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, INITIAL_VAULT_BALANCE + forfeitedAmount, "yieldReserve");
        assertEq(
            yieldSReserve,
            vault.previewWithdraw(INITIAL_VAULT_BALANCE + forfeitedAmount),
            "yieldSReserve"
        );
    }

    function test_withReclaimedDeposits_fuzz(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        // Start from 2 as it will revert due to 0 shares if amount is 1
        uint256 amount = bound(amount_, 2, 10e18);

        // Recipient has reclaimed their deposit, leaving behind a forfeited amount
        // The forfeited amount is included in the yield
        vm.prank(recipient);
        CDEPO.reclaim(iReserveToken, amount);

        uint256 reclaimedAmount = CDEPO.previewReclaim(iReserveToken, amount);
        uint256 forfeitedAmount = amount - reclaimedAmount;

        // Call function
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.previewSweepYield(iReserveToken);

        // Assert values
        assertEq(yieldReserve, INITIAL_VAULT_BALANCE + forfeitedAmount, "yieldReserve");
        assertEq(
            yieldSReserve,
            vault.previewWithdraw(INITIAL_VAULT_BALANCE + forfeitedAmount),
            "yieldSReserve"
        );
    }
}
