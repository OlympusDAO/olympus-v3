// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {BackingOracleTest} from "src/test/policies/BackingOracle/fixtures/BackingOracleTest.sol";

abstract contract BackingOracleConfigTimelockTest is BackingOracleTest {
    BackingOracleConfigTimelock internal _timelock;

    function setUp() public virtual override {
        super.setUp();
        _timelock = new BackingOracleConfigTimelock(_kernel, IBackingOracle(address(_oracle)));
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(_timelock));
        // The target may be paused during queue activation, avoiding a startup cycle.
        vm.prank(_ADMIN);
        _timelock.enable("");
    }

    function _queue(uint256 value_) internal returns (uint64) {
        vm.prank(_PROPOSER);
        return _timelock.queueSetBacking(value_);
    }

    function _expectTimelockInactive() internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "BackingOracleTimelock_PolicyNotActive(address)",
                address(_timelock)
            )
        );
    }

    modifier givenTimelockInactive() {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _;
    }

    function _expectTargetUnavailable() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_oracle)
            )
        );
    }

    function _stateHash(uint256 backing_) internal view returns (bytes32) {
        return keccak256(abi.encode(address(_timelock), backing_));
    }

    function _backingKey() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(_oracle),
                    keccak256(abi.encode(IBackingOracle.setBacking.selector))
                )
            );
    }

    function _pendingIntentHash(uint64 id_) internal view returns (bytes32) {
        (bytes32 key, bytes32 expectedState) = _timelock.getQueuedConfigState(id_, 0, 0);
        return
            keccak256(
                abi.encode(
                    _timelock.getQueuedAction(id_),
                    _timelock.getQueuedConfigDestination(id_, 0),
                    _timelock.getQueuedConfigStateCount(id_, 0),
                    key,
                    expectedState,
                    _timelock.pendingActionId(_backingKey()),
                    _timelock.nextActionId(),
                    _oracle.backing(),
                    _oracle.configOperator()
                )
            );
    }
}
