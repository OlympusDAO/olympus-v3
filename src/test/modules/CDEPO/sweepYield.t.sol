// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {Module} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract SweepYieldCDEPOTest is CDEPOTest {
    event YieldSwept(address receiver, uint256 reserveAmount, uint256 sReserveAmount);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the recipient_ address is the zero address
    //  [X] it reverts
    // when there are no deposits
    //  [X] it does not transfer any yield
    //  [X] it returns zero
    //  [X] it does not emit any events
    // when there are deposits
    //  when it is called again without any additional yield
    //   [X] it returns zero
    //  when deposit tokens have been reclaimed
    //   [X] the yield includes the forfeited amount
    //  [X] it withdraws the underlying asset from the vault
    //  [X] it transfers the underlying asset to the recipient_ address
    //  [X] it emits a `YieldSwept` event

    function test_callerNotPermissioned_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, recipient)
        );

        // Call function
        vm.prank(recipient);
        CDEPO.sweepYield(recipient);
    }

    function test_recipientZeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "recipient"));

        // Call function
        vm.prank(godmode);
        CDEPO.sweepYield(address(0));
    }

    function test_noDeposits() public {
        // Call function
        vm.prank(godmode);
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.sweepYield(recipient);

        // Assert values
        assertEq(yieldReserve, 0, "yieldReserve");
        assertEq(yieldSReserve, 0, "yieldSReserve");
    }

    function test_withDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        address yieldRecipient = address(0xB);

        uint256 expectedSReserveYield = vault.previewWithdraw(INITIAL_VAULT_BALANCE);
        uint256 sReserveBalanceBefore = vault.balanceOf(address(CDEPO));

        // Emit event
        vm.expectEmit(true, true, true, true);
        emit YieldSwept(yieldRecipient, INITIAL_VAULT_BALANCE, expectedSReserveYield);

        // Call function
        vm.prank(godmode);
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.sweepYield(yieldRecipient);

        // Assert values
        assertEq(yieldReserve, INITIAL_VAULT_BALANCE, "yieldReserve");
        assertEq(yieldSReserve, expectedSReserveYield, "yieldSReserve");

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

    function test_sweepYieldAgain()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        address yieldRecipient = address(0xB);

        uint256 expectedSReserveYield = vault.previewWithdraw(INITIAL_VAULT_BALANCE);
        uint256 sReserveBalanceBefore = vault.balanceOf(address(CDEPO));

        // Call function
        vm.prank(godmode);
        CDEPO.sweepYield(yieldRecipient);

        // Call function again
        vm.prank(godmode);
        (uint256 yieldReserve2, uint256 yieldSReserve2) = CDEPO.sweepYield(yieldRecipient);

        // Assert values
        assertEq(yieldReserve2, 0, "yieldReserve2");
        assertEq(yieldSReserve2, 0, "yieldSReserve2");

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

    function test_withReclaimedDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        // Recipient has reclaimed all of their deposit, leaving behind a forfeited amount
        // The forfeited amount is included in the yield
        vm.prank(recipient);
        CDEPO.reclaim(10e18);

        uint256 reclaimedAmount = CDEPO.previewReclaim(10e18);
        uint256 forfeitedAmount = 10e18 - reclaimedAmount;

        address yieldRecipient = address(0xB);

        uint256 expectedSReserveYield = vault.previewWithdraw(
            INITIAL_VAULT_BALANCE + forfeitedAmount
        );
        uint256 sReserveBalanceBefore = vault.balanceOf(address(CDEPO));

        // Emit event
        vm.expectEmit(true, true, true, true);
        emit YieldSwept(
            yieldRecipient,
            INITIAL_VAULT_BALANCE + forfeitedAmount,
            expectedSReserveYield
        );

        // Call function
        vm.prank(godmode);
        (uint256 yieldReserve, uint256 yieldSReserve) = CDEPO.sweepYield(yieldRecipient);

        // Assert values
        assertEq(yieldReserve, INITIAL_VAULT_BALANCE + forfeitedAmount, "yieldReserve");
        assertEq(yieldSReserve, expectedSReserveYield, "yieldSReserve");

        // Assert balances
        assertEq(
            reserveToken.balanceOf(recipient),
            reclaimedAmount,
            "reserveToken.balanceOf(recipient)"
        );
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
}
