// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract DepositRedemptionVaultSetClaimDefaultRewardPercentageTest is DepositRedemptionVaultTest {
    event ClaimDefaultRewardPercentageSet(uint16 percent);

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        redemptionVault.setClaimDefaultRewardPercentage(100e2);
    }

    // given the caller is not the admin or manager
    //  [X] it reverts

    function test_givenCallerIsNotAdminOrManager_reverts(
        address caller_
    ) public givenLocallyActive {
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorized();

        // Call function
        vm.prank(caller_);
        redemptionVault.setClaimDefaultRewardPercentage(100e2);
    }

    // given the percentage is greater than 100e2
    //  [X] it reverts

    function test_whenPercentageIsGreaterThan100e2_reverts(
        uint16 percent_
    ) public givenLocallyActive {
        percent_ = uint16(bound(percent_, 100e2 + 1, type(uint16).max));

        // Expect revert
        _expectRevertOutOfBounds(percent_);

        // Call function
        vm.prank(admin);
        redemptionVault.setClaimDefaultRewardPercentage(percent_);
    }

    // [X] it sets the reward percentage
    // [X] it emits a ClaimDefaultRewardPercentageSet event

    function test_success(bool isAdmin_, uint16 percent_) public givenLocallyActive {
        percent_ = uint16(bound(percent_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit ClaimDefaultRewardPercentageSet(percent_);

        // Call function
        vm.prank(caller);
        redemptionVault.setClaimDefaultRewardPercentage(percent_);

        // Assert
        assertEq(
            redemptionVault.getClaimDefaultRewardPercentage(),
            percent_,
            "claim default reward percentage mismatch"
        );
    }
}
