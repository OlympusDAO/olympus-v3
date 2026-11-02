// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigConstructorTest is BurnerLoansConfigTest {
    function _assertDeployment(BurnerLoansConfig config_, bytes32 before_) internal view {
        assertEq(config_.core(), address(_core), "Permanent Core binding");
        assertEq(config_.ohm(), address(_ohm), "Permanent principal token");
        assertEq(address(config_.kernel()), address(_kernel), "Exact Kernel binding");
        assertEq(config_.gracePeriod(), 7 days, "Initial grace period");
        assertFalse(config_.isEnabled(), "Starts disabled");
        assertEq(config_.lastTransitionAt(), 0, "No initial transition");
        assertEq(config_.configOperator(), address(0), "No delegated authority");
        assertEq(_stateDigest(), before_, "Deployment leaves existing state unchanged");
        assertEq(_core.configOperator(), address(_config), "New Config is not selected implicitly");
    }

    // Scenarios: BLCC-I01.
    function test_whenCoreIsZero_reverts(address deployer_) public {
        address candidate = address(0);
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                candidate
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(candidate));
    }

    // Scenarios: BLCC-I02.
    function test_whenCoreIsEOA_reverts(address deployer_) public {
        address candidate = makeAddr("noCode");
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                candidate
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(candidate));
    }

    // Scenarios: BLCC-I03.
    function test_givenCoreMissingCoreInterface_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            abi.encode(false)
        );
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-I04.
    function test_givenCoreMissingVersionInterface_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IVersioned).interfaceId),
            abi.encode(false)
        );
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-I05.
    function test_givenRevertingERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IERC165).interfaceId),
            hex"deadbeef"
        );
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-I06.
    function test_givenMalformedERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IERC165).interfaceId),
            hex"01"
        );
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-I07.
    function test_givenWrongKernel_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(0xBAD)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-T01.
    function test_givenRevertingOhm_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("ohm()"), hex"deadbeef");
        vm.prank(deployer_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
        new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
    }

    // Scenarios: BLCC-T02.
    function test_givenMalformedCoreKernel_whenDeployed_reverts() public {
        bytes memory getter = abi.encodeWithSignature("kernel()");
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 65_536];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_core), getter, new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(_core)
                )
            );
            new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        }
    }

    // Scenarios: BLCC-T03.
    function test_givenMalformedCoreOhm_whenDeployed_reverts() public {
        bytes memory getter = abi.encodeWithSignature("ohm()");
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 65_536];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(_core), getter, new bytes(lengths[i]));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                    address(_core)
                )
            );
            new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        }
    }

    // Scenarios: BLCC-L01.
    function test_givenCoreActiveEnabled_whenDeployed(address deployer_) public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansConfig config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _assertDeployment(config, beforeState);
    }

    // Scenarios: BLCC-L02.
    function test_givenCoreActiveDisabled_whenDeployed(address deployer_) public {
        _core.disable("");
        bytes32 beforeState = _stateDigest();
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansConfig config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _assertDeployment(config, beforeState);
    }

    // Scenarios: BLCC-L03.
    function test_givenCoreInactiveEnabled_whenDeployed(address deployer_) public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        bytes32 beforeState = _stateDigest();
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansConfig config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _assertDeployment(config, beforeState);
    }

    // Scenarios: BLCC-L04.
    function test_givenCoreInactiveDisabled_whenDeployed(address deployer_) public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("inventory()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("payout()"), hex"deadbeef");

        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        bytes32 beforeState = _stateDigest();
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansConfig config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _assertDeployment(config, beforeState);
    }
}
