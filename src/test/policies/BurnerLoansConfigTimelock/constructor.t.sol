// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";

contract BurnerLoansConfigTimelockConstructorTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-CONSTRUCTOR-D01.
    function test_givenMissingIBurnerLoansConfig_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansConfig).interfaceId
            ),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-D02.
    function test_givenMissingIEnabler_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IEnabler).interfaceId),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-I03.
    function test_givenMissingIConfigOperator_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IConfigOperator).interfaceId),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-I01.
    function test_givenZeroConfig_whenConstructed_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(0)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I02.
    function test_givenEoaConfig_whenConstructed_reverts(
        address deployer_,
        address candidate_
    ) public {
        vm.assume(candidate_.code.length == 0 && candidate_ != address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                candidate_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(candidate_));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I04.
    function test_givenInterfaceProbeReverts_whenConstructed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(_config)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-I05.
    function test_givenMalformedInterfaceProbe_whenConstructed_reverts(address deployer_) public {
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"01"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, IBurnerLoansConfig(address(_config)));
    }

    // Scenarios: BLCT-CONSTRUCTOR-D03.
    function test_givenForeignConfigKernel_whenConstructed_reverts(address deployer_) public {
        Kernel other = new Kernel();
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_config),
                address(_kernel),
                address(other)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-P01.
    function test_givenKernelGetterReverts_whenConstructed_reverts(address deployer_) public {
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_config)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansConfigTimelock(_kernel, _config);
    }

    // Scenarios: BLCT-CONSTRUCTOR-P02.
    function test_givenConfigActiveTrue_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, true, true);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P03.
    function test_givenConfigActiveTrue_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, true, false);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P04.
    function test_givenConfigActiveFalse_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, false, true);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }

    // Scenarios: BLCT-CONSTRUCTOR-P05.
    function test_givenConfigActiveFalse_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults(
        address deployer_
    ) public {
        _setState(_config, false, false);
        vm.prank(deployer_);
        BurnerLoansConfigTimelock fresh = new BurnerLoansConfigTimelock(_kernel, _config);
        assertEq(address(fresh.kernel()), address(_kernel), "Immutable Kernel");
        assertEq(address(fresh.burnerLoans()), address(_config), "Immutable Config");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Window");
        assertEq(fresh.nextActionId(), 1, "First ID");
    }
}
