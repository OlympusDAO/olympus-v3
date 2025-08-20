// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract DepositRedemptionVaultSetMaxBorrowPercentageTest is DepositRedemptionVaultTest {
    event MaxBorrowPercentageSet(address indexed asset, address indexed facility, uint16 percent);

    // ===== TESTS ===== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(cdFacility), 100e2);
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
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(cdFacility), 100e2);
    }

    // when the rate is greater than 100e2
    //  [X] it reverts

    function test_whenRateIsGreaterThan100e2_reverts(uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 100e2 + 1, type(uint16).max));

        // Expect revert
        _expectRevertOutOfBounds(rate_);

        // Call function
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(cdFacility), rate_);
    }

    // when the asset is the zero address
    //  [X] it reverts

    function test_whenAssetIsZeroAddress_reverts(uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));

        // Expect revert
        _expectRevertZeroAddress();

        // Call function
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(IERC20(address(0)), address(cdFacility), rate_);
    }

    // when the facility is the zero address
    //  [X] it reverts

    function test_whenFacilityIsZeroAddress_reverts(uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));

        // Expect revert
        _expectRevertZeroAddress();

        // Call function
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(0), rate_);
    }

    // given the asset is not supported
    //  [X] it sets the max borrow percentage for the asset
    //  [X] it emits a MaxBorrowPercentageSet event

    function test_givenAssetIsNotSupported(bool isAdmin_, uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit MaxBorrowPercentageSet(address(asset), address(cdFacility), rate_);

        // Call function
        vm.prank(caller);
        redemptionVault.setMaxBorrowPercentage(IERC20(address(asset)), address(cdFacility), rate_);

        // Assert
        assertEq(
            redemptionVault.getMaxBorrowPercentage(IERC20(address(asset)), address(cdFacility)),
            rate_,
            "max borrow percentage mismatch"
        );
    }

    // given the facility is not authorized
    //  [X] it sets the max borrow percentage for the asset
    //  [X] it emits a MaxBorrowPercentageSet event

    function test_givenFacilityIsNotAuthorized(
        bool isAdmin_,
        uint16 rate_
    ) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        address facility = address(0xDDDD);

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit MaxBorrowPercentageSet(address(iReserveToken), address(facility), rate_);

        // Call function
        vm.prank(caller);
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(facility), rate_);

        // Assert
        assertEq(
            redemptionVault.getMaxBorrowPercentage(iReserveToken, address(facility)),
            rate_,
            "max borrow percentage mismatch"
        );
    }

    // [X] it sets the max borrow percentage for the asset
    // [X] it emits a MaxBorrowPercentageSet event

    function test_givenAssetIsSupported(bool isAdmin_, uint16 rate_) public givenLocallyActive {
        rate_ = uint16(bound(rate_, 0, 100e2));
        address caller = isAdmin_ ? admin : manager;

        // Expect emit
        vm.expectEmit(true, true, true, true);
        emit MaxBorrowPercentageSet(address(iReserveToken), address(cdFacility), rate_);

        // Call function
        vm.prank(caller);
        redemptionVault.setMaxBorrowPercentage(iReserveToken, address(cdFacility), rate_);

        // Assert
        assertEq(
            redemptionVault.getMaxBorrowPercentage(iReserveToken, address(cdFacility)),
            rate_,
            "max borrow percentage mismatch"
        );
    }
}
