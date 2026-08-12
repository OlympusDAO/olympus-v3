// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";

// Contracts
import {Actions, Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockConstructorTest is BurnerLoansConfigTimelockTest {
    // constructor
    // given BurnerLoans address is zero
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_constructor_givenBurnerLoansIsZero_reverts() public {
        vm.expectRevert(IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ZeroAddress.selector);
        new BurnerLoansConfigTimelock(kernel, IBurnerLoansConfig(address(0)));
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
        new BurnerLoansConfigTimelock(kernel, IBurnerLoansConfig(address(usds)));
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
        new BurnerLoansConfigTimelock(kernel, IBurnerLoansConfig(address(invalidBurnerLoans)));
    }

    // constructor
    // given BurnerLoansConfig does not support IEnabler
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_givenBurnerLoansConfigDoesNotSupportEnabler_reverts() public {
        MockNonEnablerBurnerLoansConfig invalidConfig = new MockNonEnablerBurnerLoansConfig(kernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidBurnerLoans.selector,
                address(invalidConfig)
            )
        );
        new BurnerLoansConfigTimelock(kernel, IBurnerLoansConfig(address(invalidConfig)));
    }

    // constructor
    // given BurnerLoansConfig belongs to a different Kernel
    //  when BurnerLoansConfigTimelock is deployed
    //   then it reverts
    function test_constructor_givenBurnerLoansConfigHasDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockBurnerLoansPolicy foreignFacility = new MockBurnerLoansPolicy(
            otherKernel,
            address(ohm)
        );
        otherKernel.executeAction(Actions.ActivatePolicy, address(foreignFacility));
        BurnerLoansConfig foreignConfig = new BurnerLoansConfig(otherKernel, IERC20(address(ohm)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_KernelMismatch.selector,
                address(otherKernel)
            )
        );
        new BurnerLoansConfigTimelock(kernel, foreignConfig);
    }

    // constructor
    // given BurnerLoansConfig is inactive on the same Kernel
    //  when BurnerLoansConfigTimelock is deployed
    //   then it binds the deployment-time Config
    function test_constructor_givenBurnerLoansConfigIsInactive_bindsConfig() public {
        BurnerLoansConfig inactiveConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)));

        BurnerLoansConfigTimelock timelock = new BurnerLoansConfigTimelock(kernel, inactiveConfig);

        assertEq(address(timelock.burnerLoans()), address(inactiveConfig), "config");
    }

    // constructor
    // given constructor parameters are valid
    //  when the deployed timelock is inspected
    //   then immutable dependencies and defaults are set
    function test_constructor_givenValidParams_setsImmutableDependencies() public view {
        assertEq(address(configTimelock.burnerLoans()), address(burnerLoansConfig), "config");
        assertEq(configTimelock.MIN_TIMELOCK_DELAY(), 1 days, "minimum delay");
        assertEq(configTimelock.MAX_TIMELOCK_DELAY(), 30 days, "maximum delay");
        assertEq(configTimelock.EXECUTION_WINDOW(), 3 days, "execution window");
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

contract MockNonEnablerBurnerLoansConfig is Policy, IERC165 {
    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansConfig).interfaceId;
    }
}
