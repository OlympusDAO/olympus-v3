// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

contract CreateYDFTest is YieldDepositFacilityTest {
    // given the contract is inactive
    //  [X] it reverts
    // when the caller is not the admin
    //  [X] it reverts
    // [X] it creates a new CD token

    function test_contractDisabled_reverts() public {
        // Create a new token and vault
        MockERC20 newReserveToken = new MockERC20("New Reserve Token", "NRT", 18);
        MockERC4626 newVault = new MockERC4626(newReserveToken, "New Vault", "NVLT");

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Call function
        vm.prank(admin);
        yieldDepositFacility.create(IERC4626(address(newVault)), PERIOD_MONTHS, 90e2);
    }

    function test_callerIsNotAdmin_reverts() public givenLocallyActive {
        // Create a new token and vault
        MockERC20 newReserveToken = new MockERC20("New Reserve Token", "NRT", 18);
        MockERC4626 newVault = new MockERC4626(newReserveToken, "New Vault", "NVLT");

        // Expect revert
        _expectRoleRevert(bytes32("admin"));

        // Call function
        yieldDepositFacility.create(IERC4626(address(newVault)), PERIOD_MONTHS, 90e2);
    }

    function test_success() public givenLocallyActive {
        // Create a new token and vault
        MockERC20 newReserveToken = new MockERC20("New Reserve Token", "NRT", 18);
        MockERC4626 newVault = new MockERC4626(newReserveToken, "New Vault", "NVLT");

        // Call function
        vm.prank(admin);
        IConvertibleDepositERC20 newCdToken = yieldDepositFacility.create(
            IERC4626(address(newVault)),
            PERIOD_MONTHS,
            90e2
        );

        // Assert the new CD token was created
        assertEq(
            convertibleDepository.isConvertibleDepositToken(address(newCdToken)),
            true,
            "isConvertibleDepositToken"
        );
    }
}
