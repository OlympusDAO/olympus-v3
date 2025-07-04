// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract SweepAllYieldCDEPOTest is CDEPOTest {
    event YieldSwept(
        address indexed inputToken,
        address indexed receiver,
        uint256 reserveAmount,
        uint256 sReserveAmount
    );

    // when there are no tokens
    //  [ ] it does nothing
    // when there is one token
    //  [X] it sweeps the yield
    // when there are multiple tokens
    //  [X] it sweeps the yield for each token

    function test_singleToken()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        address yieldRecipient = address(0xB);

        uint256 expectedSReserveYield = vault.previewWithdraw(INITIAL_VAULT_BALANCE);
        uint256 sReserveBalanceBefore = vault.balanceOf(address(CDEPO));

        // Emit event
        vm.expectEmit(true, true, true, true);
        emit YieldSwept(
            address(iReserveTokenVault),
            yieldRecipient,
            INITIAL_VAULT_BALANCE,
            expectedSReserveYield
        );

        // Call function
        vm.prank(godmode);
        CDEPO.sweepAllYield(yieldRecipient);

        // Assert balances
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
        assertEq(
            reserveToken.balanceOf(yieldRecipient),
            0,
            "reserveToken.balanceOf(yieldRecipient)"
        );
        assertEq(
            vault.balanceOf(yieldRecipient),
            expectedSReserveYield,
            "vault.balanceOf(yieldRecipient)"
        );
        assertEq(reserveToken.balanceOf(godmode), 0, "reserveToken.balanceOf(godmode)");
        assertEq(vault.balanceOf(godmode), 0, "vault.balanceOf(godmode)");
        assertEq(
            reserveToken.balanceOf(address(CDEPO)),
            0,
            "reserveToken.balanceOf(address(CDEPO))"
        );
        assertEq(
            vault.balanceOf(address(CDEPO)),
            sReserveBalanceBefore - expectedSReserveYield,
            "vault.balanceOf(address(CDEPO))"
        );
    }

    function test_multipleTokens()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        address yieldRecipient = address(0xB);

        // Create the CD token
        vm.prank(godmode);
        IConvertibleDepositERC20 cdTokenTwo = CDEPO.create(
            iReserveTokenTwoVault,
            PERIOD_MONTHS,
            99e2
        );

        // Deposit the second token
        uint256 tokenTwoDeposit = 10e18;
        reserveTokenTwo.mint(recipient, tokenTwoDeposit);
        vm.startPrank(recipient);
        iReserveTokenTwo.approve(address(CDEPO), tokenTwoDeposit);
        CDEPO.mint(cdTokenTwo, tokenTwoDeposit);
        vm.stopPrank();

        // Reclaim the second token, so there is yield to sweep
        vm.startPrank(recipient);
        cdTokenTwo.approve(address(CDEPO), tokenTwoDeposit);
        CDEPO.reclaim(cdTokenTwo, tokenTwoDeposit);
        vm.stopPrank();

        uint256 expectedSReserveYield = vault.previewWithdraw(INITIAL_VAULT_BALANCE);
        uint256 expectedTokenTwoYield = (tokenTwoDeposit * 1e2) / 100e2;
        uint256 expectedTokenTwoSReserveYield = iReserveTokenTwoVault.previewWithdraw(
            expectedTokenTwoYield
        );

        // Call function
        vm.prank(godmode);
        CDEPO.sweepAllYield(yieldRecipient);

        // Receiver will have the yield for both tokens
        assertEq(
            vault.balanceOf(yieldRecipient),
            expectedSReserveYield,
            "vault.balanceOf(yieldRecipient)"
        );
        assertEq(
            iReserveTokenTwoVault.balanceOf(yieldRecipient),
            expectedTokenTwoSReserveYield,
            "tokenTwoVault.balanceOf(yieldRecipient)"
        );
    }
}
