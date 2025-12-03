// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "src/test/policies/ConvertibleDepositFacility/ConvertibleDepositFacilityTest.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ConvertibleDepositFacilityClaimYieldTest is ConvertibleDepositFacilityTest {
    event ClaimedYield(address indexed asset, uint256 amount);

    // ========== TESTS ========== //
    // given the facility is disabled
    //  [X] it returns 0

    function test_givenDisabled()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenVaultAccruesYield(iVault, 1e18)
        givenLocallyInactive
    {
        // Determine the expected yield
        uint256 expectedYield = depositManager.maxClaimYield(iReserveToken, address(facility));
        assertTrue(expectedYield > 0, "expectedYield");

        // Call function
        uint256 yield = facility.claimYield(iReserveToken);

        // Assert returned yield
        assertEq(yield, 0, "yield");

        // Assert treasury balance
        assertEq(iReserveToken.balanceOf(address(treasury)), 0, "treasury balance");
    }

    // given the asset is not supported
    //  [X] it returns 0

    function test_whenAssetNotSupported() public givenLocallyActive {
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);

        // Call function
        uint256 yield = facility.claimYield(IERC20(address(newAsset)));

        // Assert
        assertEq(yield, 0, "yield");
    }

    // given the yield is 0
    //  [X] it returns 0

    function test_givenYieldIsZero()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
    {
        // Call function
        uint256 yield = facility.claimYield(iReserveToken);

        // Assert
        assertEq(yield, 0, "yield");
    }

    // [X] it transfers the yield to the treasury
    // [X] it emits the ClaimedYield event
    // [X] it returns the yield

    function test_success()
        public
        givenLocallyActive
        givenAddressHasConvertibleDepositToken(
            recipient,
            iReserveToken,
            PERIOD_MONTHS,
            RESERVE_TOKEN_AMOUNT
        )
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Determine the expected yield
        uint256 expectedYield = depositManager.maxClaimYield(iReserveToken, address(facility));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ClaimedYield(address(iReserveToken), expectedYield);

        // Call function
        uint256 yield = facility.claimYield(iReserveToken);

        // Assert returned yield
        assertEq(yield, expectedYield, "yield");

        // Assert treasury balance
        assertEq(iReserveToken.balanceOf(address(treasury)), expectedYield, "treasury balance");
    }
}
