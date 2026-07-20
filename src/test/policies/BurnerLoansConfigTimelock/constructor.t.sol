// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockConstructorTest is BurnerLoansConfigTimelockTest {
    // constructor
    // given BurnerLoans address is zero
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_constructor_givenBurnerLoansIsZero_reverts() public {
        vm.expectRevert(IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ZeroAddress.selector);
        new BurnerLoansConfigTimelock(kernel, IBurnerLoansConfig(address(0)), address(burnerLoans));
    }

    // constructor
    // given BurnerLoans address does not implement ERC165
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_constructor_givenBurnerLoansDoesNotImplementErc165_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidBurnerLoans.selector,
                address(usds)
            )
        );
        new BurnerLoansConfigTimelock(
            kernel,
            IBurnerLoansConfig(address(usds)),
            address(burnerLoans)
        );
    }

    // constructor
    // given BurnerLoans address implements ERC165 but not IBurnerLoans
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_constructor_givenBurnerLoansDoesNotSupportInterface_reverts() public {
        MockInvalidBurnerLoans invalidBurnerLoans = new MockInvalidBurnerLoans();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidBurnerLoans.selector,
                address(invalidBurnerLoans)
            )
        );
        new BurnerLoansConfigTimelock(
            kernel,
            IBurnerLoansConfig(address(invalidBurnerLoans)),
            address(burnerLoans)
        );
    }

    // constructor
    // given constructor parameters are valid
    //  when the deployed timelock is inspected
    //   then immutable dependencies and defaults are set
    function test_constructor_givenValidParams_setsImmutableDependencies() public view {
        assertEq(address(configTimelock.burnerLoans()), address(burnerLoansConfig), "config");
        assertEq(configTimelock.FACILITY(), address(burnerLoans), "facility");
        assertEq(
            configTimelock.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "grace period"
        );
        assertEq(configTimelock.timelockDelay(), configTimelock.MIN_TIMELOCK_DELAY(), "delay");
    }
}

contract MockInvalidBurnerLoans is IERC165 {
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return interfaceId_ == type(IERC165).interfaceId;
    }
}
