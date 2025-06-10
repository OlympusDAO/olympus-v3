// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {CDTokenManagerTest} from "./CDTokenManagerTest.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract WithdrawCDTokenManagerTest is CDTokenManagerTest {
    event Withdraw(
        address indexed account,
        address indexed cdToken,
        uint256 amount,
        uint256 shares
    );

    // given the CD token manager is disabled
    //  [X] it reverts
    // given the caller does not have the deposit_manager role
    //  [X] it reverts
    // given the CD token does not exist
    //  [X] it reverts
    // given the caller has no deposited shares
    //  [X] it reverts
    // given the caller has insufficient deposited shares
    //  [X] it reverts
    // given the withdrawal amount is zero
    //  [X] it reverts
    // given the withdrawal amount would leave the CD token manager insolvent
    //  [X] it reverts
    // [X] it transfers the underlying token from the CD token manager to the caller
    // [X] it updates the amount of deposited funds
    // [X] it does not update the amount of CD tokens in circulation
    // [X] it emits a Withdraw event

    function test_givenDisabled_reverts() public givenDisabled {
        // Expect
        _expectRevertDisabled();

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, 100e18);
    }

    function test_givenNotCDTokenManagerRole_reverts(address caller_) public {
        vm.assume(caller_ != facility);

        // Expect
        _expectRevertNotCDTokenManagerRole();

        // Call function
        vm.prank(caller_);
        cdTokenManager.withdraw(cdToken, 100e18);
    }

    function test_givenNotCDToken_reverts() public {
        // Expect
        _expectRevertNotCDToken();

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(IConvertibleDepositERC20(address(reserveToken)), 100e18);
    }

    function test_givenNoDepositedShares_reverts() public givenCDTokenCreated(iVault, 6) {
        // Expect
        _expectRevertArithmeticError();

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, 100e18);
    }

    function test_givenInsufficientDepositedShares_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18)
    {
        // Expect
        _expectRevertArithmeticError();

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, 101e18);
    }

    function test_givenWithdrawalAmountIsZero_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18)
    {
        // Expect
        _expectRevertZeroAmount();

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, 0);
    }

    function test_insolvent_reverts(
        uint256 withdrawShares_
    ) public givenCDTokenCreated(iVault, 6) givenFacilityHasCDToken(100e18) {
        // Add yield to the vault (otherwise deposited == required)
        reserveToken.mint(address(vault), 20e18);

        // Determine the shares required to remain solvent
        uint256 sharesDeposited = vault.balanceOf(address(cdTokenManager));
        uint256 sharesRequired = vault.previewWithdraw(100e18);

        // Bound the quantity of shares to withdraw
        // Should result in there not being enough shares remaining to obtain the quantity of underlying tokens == CD token supply
        withdrawShares_ = bound(
            withdrawShares_,
            sharesDeposited - sharesRequired + 1,
            sharesDeposited
        );

        // Expect
        _expectRevertInsolvent(cdToken, sharesRequired, sharesDeposited - withdrawShares_);

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, vault.previewRedeem(withdrawShares_));
    }

    function test_success(
        uint256 withdrawShares_
    ) public givenCDTokenCreated(iVault, 6) givenFacilityHasCDToken(100e18) {
        // Add yield to the vault (otherwise deposited == required)
        reserveToken.mint(address(vault), 20e18);

        // Determine the shares required to remain solvent
        uint256 sharesDeposited = vault.balanceOf(address(cdTokenManager));
        uint256 sharesRequired = vault.previewWithdraw(100e18);

        // Bound the quantity of shares to withdraw
        // Should result in there being enough shares remaining to obtain the quantity of underlying tokens == CD token supply
        withdrawShares_ = bound(withdrawShares_, 1, sharesDeposited - sharesRequired);
        uint256 withdrawAmount = vault.previewRedeem(withdrawShares_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Withdraw(facility, address(cdToken), withdrawAmount, withdrawShares_);

        // Call function
        vm.prank(facility);
        cdTokenManager.withdraw(cdToken, withdrawAmount);

        // Assert
        _assertCDTokenBalance(cdToken, 100e18);
        _assertTokenBalance(reserveToken, 0, 0, withdrawAmount);
        _assertCDTokenSupply(cdToken, 100e18);
        _assertDepositedShares(iVault, sharesDeposited - withdrawShares_);
        _assertVaultShares(iVault, sharesDeposited - withdrawShares_);
    }
}
