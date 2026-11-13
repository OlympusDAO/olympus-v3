// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {BackingOracleTest} from "src/test/policies/BackingOracle/fixtures/BackingOracleTest.sol";

contract BackingOracleTimelockConstructorTest is BackingOracleTest {
    error MetadataUnavailable();

    // Scenarios: BO-CONSTRUCTOR-01.
    function test_whenConstructedBeforeReadiness(bool active_, bool enabled_) public {
        if (enabled_) {
            vm.prank(_ADMIN);
            _oracle.enable(abi.encode(100e18));
        }
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(MetadataUnavailable.selector)
        );
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSignature("configOperator()"),
            abi.encodeWithSelector(MetadataUnavailable.selector)
        );
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_oracle)),
            abi.encodeWithSelector(MetadataUnavailable.selector)
        );
        BackingOracleConfigTimelock queue = new BackingOracleConfigTimelock(
            _kernel,
            IBackingOracle(address(_oracle))
        );
        assertEq(address(queue.backingOracle()), address(_oracle), "immutable oracle");
        assertEq(address(queue.kernel()), address(_kernel), "queue uses the supplied Kernel");
        assertEq(
            address(_oracle.kernel()),
            address(queue.kernel()),
            "oracle and queue share Kernel"
        );
        assertFalse(queue.isEnabled(), "starts disabled without probing readiness");
        assertEq(queue.timelockDelay(), 1 days, "default delay");
    }

    function _rejectMissingInterface(bytes4 id_) private {
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSignature("supportsInterface(bytes4)", id_),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBackingOracleConfigTimelock.BackingOracleTimelock_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        new BackingOracleConfigTimelock(_kernel, IBackingOracle(address(_oracle)));
        vm.clearMockedCalls();
    }

    // Scenarios: BO-CONSTRUCTOR-02.
    function test_whenEachConsumedInterfaceMissing_reverts() public {
        _rejectMissingInterface(type(IBackingOracle).interfaceId);
        _rejectMissingInterface(type(IConfigOperator).interfaceId);
        _rejectMissingInterface(type(IEnabler).interfaceId);
    }

    // Scenarios: BO-CONSTRUCTOR-03.
    function test_whenForeignKernel_reverts() public {
        Kernel other = new Kernel();
        BackingOracle foreign = new BackingOracle(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(foreign),
                address(_kernel),
                address(other)
            )
        );
        new BackingOracleConfigTimelock(_kernel, IBackingOracle(address(foreign)));
    }

    // Scenarios: BO-CONSTRUCTOR-04.
    function test_whenMalformedKernel_reverts() public {
        vm.mockCall(address(_oracle), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_oracle)
            )
        );
        new BackingOracleConfigTimelock(_kernel, IBackingOracle(address(_oracle)));
    }

    // Scenarios: BO-TIMELOCK-CONSTRUCTOR-02.
    function test_whenZeroKernel_reverts() public {
        vm.expectRevert(
            IBackingOracleConfigTimelock.BackingOracleTimelock_ZeroKernelAddress.selector
        );
        new BackingOracleConfigTimelock(Kernel(address(0)), IBackingOracle(address(_oracle)));
    }

    function _rejectAddress(address target_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBackingOracleConfigTimelock.BackingOracleTimelock_InvalidBackingOracle.selector,
                target_
            )
        );
        new BackingOracleConfigTimelock(_kernel, IBackingOracle(target_));
    }

    // Scenarios: BO-TIMELOCK-CONSTRUCTOR-01.
    function test_whenOracleAddressBoundarySeeds_reverts() public {
        _rejectAddress(address(0));
        _rejectAddress(address(1));
        _rejectAddress(address(type(uint160).max));
    }
}
