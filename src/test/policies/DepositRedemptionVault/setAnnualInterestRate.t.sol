// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract DepositRedemptionVaultSetAnnualInterestRateTest is DepositRedemptionVaultTest {
    event AnnualInterestRateSet(address indexed asset, uint16 rate);

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        redemptionVault.setAnnualInterestRate(iReserveToken, ANNUAL_INTEREST_RATE);
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
        redemptionVault.setAnnualInterestRate(iReserveToken, ANNUAL_INTEREST_RATE);
    }

    // when the rate is greater than 100e2
    //  [X] it reverts

    function test_whenRateIsGreaterThan100e2_reverts(uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 100e2 + 1, type(uint16).max));

        // Expect revert
        _expectRevertOutOfBounds(rate_);

        // Call function
        vm.prank(admin);
        redemptionVault.setAnnualInterestRate(iReserveToken, rate_);
    }

    // given the asset is not supported
    //  [X] it sets the annual interest rate for the asset
    //  [X] it emits a InterestRateSet event

    function test_givenAssetIsNotSupported(bool isAdmin_, uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit AnnualInterestRateSet(address(asset), rate_);

        // Call function
        vm.prank(caller);
        redemptionVault.setAnnualInterestRate(IERC20(address(asset)), rate_);

        // Assert
        assertEq(
            redemptionVault.getAnnualInterestRate(IERC20(address(asset))),
            rate_,
            "annual interest rate mismatch"
        );
    }

    // [X] it sets the annual interest rate for the asset
    // [X] it emits a InterestRateSet event

    function test_givenAssetIsSupported(bool isAdmin_, uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit AnnualInterestRateSet(address(iReserveToken), rate_);

        // Call function
        vm.prank(caller);
        redemptionVault.setAnnualInterestRate(iReserveToken, rate_);

        // Assert
        assertEq(
            redemptionVault.getAnnualInterestRate(iReserveToken),
            rate_,
            "annual interest rate mismatch"
        );
    }
}
