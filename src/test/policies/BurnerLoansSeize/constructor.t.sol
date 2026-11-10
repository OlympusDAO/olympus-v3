// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

contract BurnerLoansSeizeConstructorTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-CONSTRUCTOR-I01.
    function test_whenCoreZero_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansSeize(_kernel, IBurnerLoansCore(address(0)));
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I02.
    function test_whenCoreEOA_reverts(address candidate_, address deployer_) public {
        vm.assume(candidate_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansSeize(_kernel, IBurnerLoansCore(candidate_));
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I03, BLLIQ-CONSTRUCTOR-I04.
    function test_givenMissingCoreInterface_whenDeployed_reverts(
        bool enabler_,
        address deployer_
    ) public {
        bytes4 id = enabler_ ? type(IEnabler).interfaceId : type(IBurnerLoansCore).interfaceId;
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", id),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansSeize(_kernel, _core);
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I05.
    function test_givenRevertingERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"deadbeef"
        );
        _expectInvalidCore(deployer_);
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I06.
    function test_givenMalformedERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"01"
        );
        _expectInvalidCore(deployer_);
    }

    function _expectInvalidCore(address deployer_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansSeize(_kernel, _core);
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I07.
    function test_givenDifferentKernel_whenDeployed_reverts(address deployer_) public {
        Kernel other = new Kernel();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(other),
                address(_kernel)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansSeize(other, _core);
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I08, BLLIQ-CONSTRUCTOR-I09, BLLIQ-CONSTRUCTOR-I10, BLLIQ-CONSTRUCTOR-I11.
    function test_whenBoundToCore_thenDeploymentIndependentOfLifecycle(
        address deployer_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansSeize deployed = new BurnerLoansSeize(_kernel, _core);
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
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-CONSTRUCTOR-I08, BLLIQ-CONSTRUCTOR-I09, BLLIQ-CONSTRUCTOR-I10, BLLIQ-CONSTRUCTOR-I11.
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

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
