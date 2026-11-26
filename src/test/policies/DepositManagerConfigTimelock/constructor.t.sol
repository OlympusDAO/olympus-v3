// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

contract DepositManagerConfigTimelockConstructorTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-CONSTRUCTOR-I01.
    function test_whenDepositManagerIsZero_reverts() public {
        vm.expectRevert(
            IDepositManagerConfigTimelock.DepositManagerConfigTimelock_ZeroAddress.selector
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(address(0)));
    }

    // Scenarios: DMCT-CONSTRUCTOR-I02.
    function test_whenDepositManagerDoesNotSupportRequiredInterfaces_reverts() public {
        address invalidTarget = makeAddr("invalidTarget");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                invalidTarget
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(invalidTarget));
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenDepositManagerOnlySupportsV1_reverts() public {
        _missingInterface(type(IDepositManagerV1_1).interfaceId);
    }

    // Scenarios: DMCT-CONSTRUCTOR-I04.
    function test_givenDepositManagerUsesDifferentKernel_reverts() public {
        Kernel foreignKernel = new Kernel();
        ReceiptTokenManager foreignTokenManager = new ReceiptTokenManager();
        DepositManager foreignDepositManager = new DepositManager(
            address(foreignKernel),
            address(foreignTokenManager)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(foreignDepositManager),
                address(kernel),
                address(foreignKernel)
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(address(foreignDepositManager)));
    }

    // Scenarios: DMCT-CONSTRUCTOR-P02.
    function test_givenValidParameters_setsImmutableConfiguration() public view {
        assertEq(
            address(_configTimelock.depositManager()),
            address(depositManager),
            "DepositManager target mismatch"
        );
        assertEq(_configTimelock.MIN_TIMELOCK_DELAY(), 1 days, "minimum delay mismatch");
        assertEq(_configTimelock.MAX_TIMELOCK_DELAY(), 30 days, "maximum delay mismatch");
        assertEq(_configTimelock.EXECUTION_WINDOW(), 3 days, "execution window mismatch");
        assertEq(_configTimelock.timelockDelay(), 1 days, "initial delay mismatch");
        assertEq(_configTimelock.gracePeriod(), 7 days, "grace period mismatch");
    }

    // Scenarios: DMCT-CONSTRUCTOR-P01.
    function test_whenAnyDeployerConstructs(address caller_) public {
        vm.prank(caller_);
        DepositManagerConfigTimelock subject = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        assertEq(address(subject.kernel()), address(kernel), "constructor Kernel binding");
        assertEq(
            address(subject.depositManager()),
            address(depositManager),
            "constructor target binding"
        );
        assertFalse(subject.isEnabled(), "fresh subject disabled");
        assertFalse(subject.isActive(), "constructor does not activate");
        assertEq(subject.lastTransitionAt(), 0, "never transitioned");
        assertEq(subject.nextActionId(), 1, "first queue ID");
        assertEq(subject.gracePeriod(), 7 days, "default grace");
        assertEq(subject.timelockDelay(), 1 days, "initial delay");
        assertEq(subject.maxConfigKeysPerBatch(), 15, "batch key cap");
    }

    // Scenarios: DMCT-CONSTRUCTOR-L01.
    function test_givenTargetPausedInactive_whenConstructed() public {
        _pausePolicy(address(depositManager));
        _setPolicyActive(address(depositManager), false);
        DepositManagerConfigTimelock subject = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        assertEq(
            address(subject.depositManager()),
            address(depositManager),
            "deployment does not require dependency readiness"
        );
        assertFalse(subject.isEnabled(), "fresh subject disabled");
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenManagerInterfaceMissing_reverts() public {
        _missingInterface(type(IDepositManager).interfaceId);
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenManagerV11InterfaceMissing_reverts() public {
        _missingInterface(type(IDepositManagerV1_1).interfaceId);
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenAssetV11InterfaceMissing_reverts() public {
        _missingInterface(type(IAssetManagerV1_1).interfaceId);
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenOperatorInterfaceMissing_reverts() public {
        _missingInterface(type(IConfigOperator).interfaceId);
    }

    // Scenarios: DMCT-CONSTRUCTOR-I03.
    function test_whenEnablerInterfaceMissing_reverts() public {
        _missingInterface(type(IEnabler).interfaceId);
    }

    function _missingInterface(bytes4 id_) private {
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("supportsInterface(bytes4)", id_),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(address(depositManager)));
    }

    // Scenarios: DMCT-CONSTRUCTOR-L02.
    function test_givenRuntimeReadinessGettersRevert_whenConstructed(address deployer_) public {
        vm.mockCallRevert(address(depositManager), abi.encodeWithSignature("isEnabled()"), hex"ff");
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("configOperator()"),
            hex"ff"
        );
        vm.mockCallRevert(
            address(kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(depositManager)),
            hex"ff"
        );
        vm.prank(deployer_);
        DepositManagerConfigTimelock fresh = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );
        assertEq(
            address(fresh.depositManager()),
            address(depositManager),
            "Compatible target bound without readiness reads"
        );
        assertFalse(fresh.isEnabled(), "Construction leaves queue disabled");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
