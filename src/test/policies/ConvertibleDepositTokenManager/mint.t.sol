// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {CDTokenManagerTest} from "./CDTokenManagerTest.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract MintCDTokenManagerTest is CDTokenManagerTest {
    event Mint(address indexed account, address indexed cdToken, uint256 amount, uint256 shares);

    // given the CD token manager is disabled
    //  [X] it reverts
    // given the caller does not have the deposit_manager role
    //  [X] it reverts
    // given the CD token does not exist
    //  [X] it reverts
    // given the caller has not approved the CD token manager to spend their underlying token
    //  [X] it reverts
    // given the caller has insufficient underlying token
    //  [X] it reverts
    // [X] it mints the amount of CD tokens to the caller
    // [X] it updates the amount of deposited funds
    // [X] it updates the amount of CD tokens in circulation
    // [X] it transfers the underlying token from the caller to the CD token manager
    // [X] it deposits the underlying token into the vault
    // [X] it emits a Mint event

    function test_givenDisabled_reverts() public givenDisabled {
        // Expect
        _expectRevertDisabled();

        // Call function
        vm.prank(facility);
        cdTokenManager.mint(cdToken, 100e18);
    }

    function test_givenNotCDTokenManagerRole_reverts(address caller_) public {
        vm.assume(caller_ != facility);

        // Expect
        _expectRevertNotCDTokenManagerRole();

        // Call function
        vm.prank(caller_);
        cdTokenManager.mint(cdToken, 100e18);
    }

    function test_givenNotCDToken_reverts() public {
        // Expect
        _expectRevertNotCDToken();

        // Call function
        vm.prank(facility);
        cdTokenManager.mint(IConvertibleDepositERC20(address(reserveToken)), 100e18);
    }

    function test_givenSpendingNotApproved_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasReserveToken(100e18)
        givenFacilityHasApprovedReserveTokenSpending(100e18 - 1)
    {
        // Expect
        _expectMissingApproval();

        // Call function
        vm.prank(facility);
        cdTokenManager.mint(cdToken, 100e18);
    }

    function test_givenInsufficientReserveToken_reverts()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasReserveToken(100e18 - 1)
        givenFacilityHasApprovedReserveTokenSpending(100e18)
    {
        // Expect
        _expectRevertInsufficientReserveToken();

        // Call function
        vm.prank(facility);
        cdTokenManager.mint(cdToken, 100e18);
    }

    function test_success()
        public
        givenCDTokenCreated(iVault, 6)
        givenFacilityHasReserveToken(100e18)
        givenFacilityHasApprovedReserveTokenSpending(100e18)
    {
        uint256 expectedDepositedShares = vault.previewDeposit(100e18);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Mint(facility, address(cdToken), 100e18, expectedDepositedShares);

        // Call function
        vm.prank(facility);
        cdTokenManager.mint(cdToken, 100e18);

        // Assert
        _assertCDTokenBalance(cdToken, 100e18);
        _assertTokenBalance(reserveToken, 100e18, 100e18, 0);
        _assertCDTokenSupply(cdToken, 100e18);
        _assertDepositedShares(iVault, expectedDepositedShares);
        _assertVaultShares(iVault, expectedDepositedShares);
    }
}
