// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {MockBurnerLoansYieldClaimerTaskTarget} from "./MockBurnerLoansYieldClaimerTaskTarget.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";

contract BurnerLoansYieldClaimerTaskConstructorTest is BurnerLoansYieldClaimerTaskTest {
    uint32 internal constant _DEFAULT_ATTEMPT_THRESHOLD = 250_000;
    uint32 internal constant _DEFAULT_CLEANUP_RESERVE = 100_000;

    // Scenarios: BLYC-CONSTRUCTOR-I01.
    function test_givenBurnerLoansIsZero_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidCore.selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(0), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D01.
    function test_givenCoreInterfaceUnsupported_reverts(address deployer_) public {
        target.setSupportsCore(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidCore.selector,
                address(target)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(target), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D02.
    function test_givenBurnerLoansDoesNotSupportLifecycle_reverts(address deployer_) public {
        target.setSupportsLifecycle(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidCore.selector,
                address(target)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(target), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D05.
    function test_givenBurnerLoansUsesDifferentKernel_reverts(address deployer_) public {
        Kernel otherKernel = new Kernel();
        MockBurnerLoansYieldClaimerTaskTarget otherTarget = new MockBurnerLoansYieldClaimerTaskTarget(
                otherKernel
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(otherTarget),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(otherTarget), _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CONSTRUCTOR-P02.
    function test_givenExecutionGasLimitIsZero_reverts(address deployer_) public {
        vm.expectRevert(
            IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(target), 0);
    }

    // Scenarios: BLYC-CONSTRUCTOR-P01, BLYC-CONSTRUCTOR-P03, BLYC-CONSTRUCTOR-L01, BLYC-CONSTRUCTOR-L02, BLYC-CONSTRUCTOR-L03.
    function test_givenValidConfiguration_whenDeployed(
        address deployer_,
        uint32 gasLimit_,
        bool targetActive_,
        bool targetEnabled_
    ) public {
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        _setTargetLifecycle(targetActive_, targetEnabled_);

        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(LoanParameters._REENABLE_GRACE_PERIOD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimerTask.ExecutionGasLimitSet(gasLimit_);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimerTask.MinimumGasToAttemptSet(_DEFAULT_ATTEMPT_THRESHOLD);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansYieldClaimerTask.GasReserveSet(_DEFAULT_CLEANUP_RESERVE);

        vm.prank(deployer_);
        BurnerLoansYieldClaimerTask deployed = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            gasLimit_
        );

        assertEq(deployed.core(), address(target), "Permanent Core binding");
        assertEq(deployed.core(), address(target), "Burner Loans target");
        assertEq(deployed.executionGasLimit(), gasLimit_, "execution gas limit");
        assertEq(
            deployed.minimumGasToAttempt(),
            _DEFAULT_ATTEMPT_THRESHOLD,
            "default attempt threshold"
        );
        assertEq(deployed.gasReserve(), _DEFAULT_CLEANUP_RESERVE, "default cleanup reserve");
        assertEq(deployed.nextAssetIndex(), 0, "cursor starts at zero");
        assertEq(deployed.gracePeriod(), LoanParameters._REENABLE_GRACE_PERIOD, "grace period");
        assertEq(deployed.lastTransitionAt(), 0, "transition timestamp starts at zero");
        assertFalse(deployed.isEnabled(), "starts disabled");
    }

    // Scenarios: BLYC-CONSTRUCTOR-P03.
    function test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit() public {
        BurnerLoansYieldClaimerTask minimum = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            1
        );
        BurnerLoansYieldClaimerTask maximum = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            type(uint32).max
        );

        assertEq(minimum.executionGasLimit(), 1, "minimum execution limit stored");
        assertEq(maximum.executionGasLimit(), type(uint32).max, "maximum execution limit stored");
    }

    // Scenarios: BLYC-CONSTRUCTOR-I02.
    function test_givenBurnerLoansIsEoa_reverts(address deployer_, address target_) public {
        vm.assume(target_ != address(0));
        vm.assume(target_.code.length == 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidCore.selector,
                target_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, target_, _EXECUTION_GAS_LIMIT);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D03.
    function test_givenRevertingERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(target),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"abcd"
        );
        _invalidCoreDeployment(deployer_);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D04.
    function test_givenMalformedERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(address(target), abi.encodeWithSignature("supportsInterface(bytes4)"), hex"01");
        _invalidCoreDeployment(deployer_);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D05.
    function test_givenMalformedKernel_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(target),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _invalidCoreMetadataDeployment(deployer_);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D05.
    function test_givenRevertingKernel_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(address(target), abi.encodeWithSignature("kernel()"), hex"abcd");
        _invalidCoreMetadataDeployment(deployer_);
    }

    function _invalidCoreDeployment(address deployer_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_InvalidCore.selector,
                address(target)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(target), 1);
    }

    function _invalidCoreMetadataDeployment(address deployer_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(target)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansYieldClaimerTask(kernel, address(target), 1);
    }

    // Scenarios: BLYC-CONSTRUCTOR-D04.
    function test_givenNoncanonicalERC165Boolean_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(target),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            abi.encode(uint256(2))
        );
        _invalidCoreDeployment(deployer_);
    }
}
