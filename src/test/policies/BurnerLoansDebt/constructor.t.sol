// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansDebtConstructorTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-CONSTRUCTOR-I01.
    function test_whenCoreZero_reverts() public {
        _expectInvalidCore(address(0));
        new BurnerLoansDebt(_kernel, IBurnerLoansCore(address(0)));
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I02.
    function test_whenCoreEOA_reverts(address candidate_) public {
        vm.assume(candidate_.code.length == 0);
        _expectInvalidCore(candidate_);
        new BurnerLoansDebt(_kernel, IBurnerLoansCore(candidate_));
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I03, BLDEBT-CONSTRUCTOR-I04.
    function test_givenMissingCoreInterface_whenDeployed_reverts(bool enabler_) public {
        bytes4 id = enabler_ ? type(IEnabler).interfaceId : type(IBurnerLoansCore).interfaceId;
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", id),
            abi.encode(false)
        );
        _expectInvalidCore(address(_core));
        new BurnerLoansDebt(_kernel, _core);
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I05, BLDEBT-CONSTRUCTOR-I06.
    function test_givenBrokenERC165_whenDeployed_reverts(bool malformed_) public {
        bytes memory query = abi.encodeWithSignature(
            "supportsInterface(bytes4)",
            type(IBurnerLoansCore).interfaceId
        );
        if (malformed_) vm.mockCall(address(_core), query, hex"01");
        else vm.mockCallRevert(address(_core), query, hex"deadbeef");
        _expectInvalidCore(address(_core));
        new BurnerLoansDebt(_kernel, _core);
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I07.
    function test_givenDifferentKernel_whenDeployed_reverts() public {
        Kernel other = new Kernel();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(other),
                address(_kernel)
            )
        );
        new BurnerLoansDebt(other, _core);
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I08, BLDEBT-CONSTRUCTOR-I09, BLDEBT-CONSTRUCTOR-I10, BLDEBT-CONSTRUCTOR-I11.
    function test_whenBoundToCore_thenDeploymentIndependentOfLifecycle(
        address deployer_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        vm.prank(deployer_);
        BurnerLoansDebt deployed = new BurnerLoansDebt(_kernel, _core);
        assertEq(deployed.core(), address(_core), "Immutable Core binding");
        assertEq(address(deployed.kernel()), address(_kernel), "Kernel binding");
        assertFalse(deployed.isEnabled(), "New action disabled");
        assertFalse(_kernel.isPolicyActive(deployed), "Constructor cannot activate action");
        assertEq(deployed.lastTransitionAt(), 0, "No prior transition");
        assertEq(deployed.gracePeriod(), 7 days, "Default grace");
        assertFalse(
            _roles.hasRole(address(deployed), _SETTLEMENT_ROLE),
            "No implicit settlement role"
        );
    }

    function _expectInvalidCore(address core_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                core_
            )
        );
    }

    // Scenarios: BLDEBT-CONSTRUCTOR-I08, BLDEBT-CONSTRUCTOR-I09, BLDEBT-CONSTRUCTOR-I10, BLDEBT-CONSTRUCTOR-I11.
    function test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenBoundToCore_thenDeploymentIndependentOfLifecycle(
                    address(0xbeef),
                    active != 0,
                    enabled != 0
                );
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore Core lifecycle between constructor seeds"
                );
            }
        }
    }
}

// forge-lint: disable-end(calls-loop)
