// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigConstructorTest is BurnerLoansTest {
    // constructor
    // given facility is zero
    //  when BurnerLoansConfig is deployed
    //   then it reverts
    function test_givenFacilityIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoansConfig(kernel, IERC20(address(ohm)), depositManager, address(0));
    }

    // constructor
    // given facility is a compatible but inactive policy
    //  when BurnerLoansConfig is deployed
    //   then it binds the trusted deployment-time facility
    function test_givenFacilityIsInactive_bindsFacility() public {
        MockBurnerLoansPolicy inactiveFacility = new MockBurnerLoansPolicy(kernel);

        BurnerLoansConfig config = new BurnerLoansConfig(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            address(inactiveFacility)
        );

        assertEq(config.facility(), address(inactiveFacility), "facility");
    }

    // constructor
    // given facility reports a different Kernel
    //  when BurnerLoansConfig is deployed
    //   then it reverts
    function test_givenFacilityUsesDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockBurnerLoansPolicy foreignFacility = new MockBurnerLoansPolicy(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(foreignFacility)
            )
        );
        new BurnerLoansConfig(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            address(foreignFacility)
        );
    }

    // constructor
    // given facility is active on the same Kernel
    //  when BurnerLoansConfig is deployed
    //   then it binds the facility
    function test_givenFacilityIsActive_bindsFacility() public view {
        assertEq(burnerLoansConfig.facility(), address(burnerLoans), "facility");
    }
}
