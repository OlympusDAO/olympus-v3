// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {CDTokenManagerTest} from "./CDTokenManagerTest.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract BurnCDTokenManagerTest is CDTokenManagerTest {
    event Burn(address indexed account, address indexed cdToken, uint256 amount, uint256 shares);

    // given the CD token manager is disabled
    //  [X] it reverts
    // given the caller does not have the deposit_manager role
    //  [X] it reverts
    // given the CD token does not exist
    //  [X] it reverts
    // given the caller has not approved the CD token manager to spend their CD tokens
    //  [X] it reverts
    // given the caller has insufficient CD tokens
    //  [X] it reverts
    // [X] it burns the CD tokens
    // [X] it transfers the underlying token from the CD token manager to the caller
    // [X] it updates the amount of deposited funds
    // [X] it updates the amount of CD tokens in circulation
    // [X] it emits a Burn event

    function test_givenDisabled_reverts() public givenDisabled {
        // Expect
        _expectRevertDisabled();

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(cdToken, 100e18);
    }

    function test_givenNotCDTokenManagerRole_reverts(address caller_) public {
        vm.assume(caller_ != facility);

        // Expect
        _expectRevertNotCDTokenManagerRole();

        // Call function
        vm.prank(caller_);
        cdTokenManager.burn(cdToken, 100e18);
    }

    function test_givenNotCDToken_reverts() public {
        // Expect
        _expectRevertNotCDToken();

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(IConvertibleDepositERC20(address(reserveToken)), 100e18);
    }

    function test_givenSpendingNotApproved_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18)
    {
        // Expect
        _expectMissingApproval();

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(cdToken, 100e18);
    }

    function test_givenInsufficientCDToken_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18 - 1)
        givenFacilityHasApprovedCDTokenSpending(100e18)
    {
        // Expect
        _expectRevertInsufficientCDToken();

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(cdToken, 100e18);
    }

    function test_success()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18)
        givenFacilityHasApprovedCDTokenSpending(100e18)
    {
        uint256 expectedWithdrawnShares = vault.previewWithdraw(100e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Burn(facility, address(cdToken), 100e18, expectedWithdrawnShares);

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(cdToken, 100e18);

        // Assert
        _assertCDTokenBalance(cdToken, 0);
        _assertTokenBalance(reserveToken, 100e18, 0, 100e18);
        _assertCDTokenSupply(cdToken, 0);
        _assertDepositedShares(iVault, 0);
        _assertVaultShares(iVault, 0);
    }

    function test_success_fuzz(
        uint256 burnAmount_
    )
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasCDToken(100e18)
        givenFacilityHasApprovedCDTokenSpending(100e18)
    {
        burnAmount_ = bound(burnAmount_, 1e18, 100e18);

        uint256 beforeShares = cdTokenManager.getDepositedShares(facility, iVault);
        uint256 expectedWithdrawnShares = vault.previewWithdraw(burnAmount_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Burn(facility, address(cdToken), burnAmount_, expectedWithdrawnShares);

        // Call function
        vm.prank(facility);
        cdTokenManager.burn(cdToken, burnAmount_);

        // Assert
        _assertCDTokenBalance(cdToken, 100e18 - burnAmount_);
        _assertTokenBalance(reserveToken, 0, 0, burnAmount_);
        _assertCDTokenSupply(cdToken, 100e18 - burnAmount_);
        _assertDepositedShares(iVault, beforeShares - expectedWithdrawnShares);
        _assertVaultShares(iVault, beforeShares - expectedWithdrawnShares);
    }
}
