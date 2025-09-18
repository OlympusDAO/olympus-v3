// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";

import {Actions} from "src/Kernel.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

contract ConvertibleDepositFacilityExecuteTest is ConvertibleDepositFacilityTest {
    event ClaimedYield(address indexed asset, uint256 amount);

    // ========== TESTS ========== //

    // given the caller does not have the heart role
    //  [X] it reverts

    function test_givenCallerDoesNotHaveHeartRole_reverts(address caller_) public {
        vm.assume(caller_ != HEART);

        // Expect revert
        _expectRoleRevert("heart");

        // Call function
        vm.prank(caller_);
        facility.execute();
    }

    // given the facility is disabled
    //  [X] it does nothing

    function test_givenDisabled()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenVaultAccruesYield(iVault, 1e18)
        givenVaultAccruesYield(iVaultTwo, 1e18)
        givenLocallyInactive
    {
        // Call function
        vm.prank(HEART);
        facility.execute();

        // Assert treasury balance
        assertEq(iReserveToken.balanceOf(address(treasury)), 0, "treasury balance: reserve token");
        assertEq(
            iReserveTokenTwo.balanceOf(address(treasury)),
            0,
            "treasury balance: reserve token two"
        );
    }

    // given there are no supported assets
    //  [X] it does nothing

    function test_givenNoSupportedAssets() public {
        // Create a new facility
        facility = new ConvertibleDepositFacility(address(kernel), address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(facility));

        // Enable the facility
        vm.prank(admin);
        facility.enable("");

        // Call function
        vm.prank(HEART);
        facility.execute();

        // Assert treasury balance
        assertEq(iReserveToken.balanceOf(address(treasury)), 0, "treasury balance: reserve token");
        assertEq(
            iReserveTokenTwo.balanceOf(address(treasury)),
            0,
            "treasury balance: reserve token two"
        );
    }

    // given an asset has no yield
    //  [X] it does nothing

    function test_givenAssetHasNoYield()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Call function
        vm.prank(HEART);
        facility.execute();

        // Assert treasury balance
        assertEq(iReserveToken.balanceOf(address(treasury)), 0, "treasury balance: reserve token");
        assertEq(
            iReserveTokenTwo.balanceOf(address(treasury)),
            0,
            "treasury balance: reserve token two"
        );
    }

    // [X] it transfers the token yields to the treasury
    // [X] it emits ClaimedYield events

    function test_success()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveTokenTwo,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenVaultAccruesYield(iVault, 1e18)
        givenVaultAccruesYield(iVaultTwo, 1e18)
    {
        // Determine the expected yields
        uint256 expectedYield = depositManager.maxClaimYield(iReserveToken, address(facility));
        uint256 expectedYieldTwo = depositManager.maxClaimYield(
            iReserveTokenTwo,
            address(facility)
        );

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit ClaimedYield(address(iReserveToken), expectedYield);
        vm.expectEmit(true, true, true, true);
        emit ClaimedYield(address(iReserveTokenTwo), expectedYieldTwo);

        // Call function
        vm.prank(HEART);
        facility.execute();

        // Assert treasury balance
        assertEq(
            iReserveToken.balanceOf(address(treasury)),
            expectedYield,
            "treasury balance: reserve token"
        );
        assertEq(
            iReserveTokenTwo.balanceOf(address(treasury)),
            expectedYieldTwo,
            "treasury balance: reserve token two"
        );
    }
}
