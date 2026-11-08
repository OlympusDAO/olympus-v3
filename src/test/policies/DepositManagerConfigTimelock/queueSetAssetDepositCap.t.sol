// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract DepositManagerConfigTimelockQueueSetAssetDepositCapTest is
    DepositManagerConfigTimelockTest
{
    // Scenarios: DMCT-QUEUE-CAP-D04.
    function test_givenManagerStatusGetterReverts_whenQueued_reverts() public {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeCall(IEnabler.isEnabled, ()),
            hex"deadbeef"
        );
        _assertQueueRejected(
            DEPOSIT_MANAGER_ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, 100e18)),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-D05.
    function test_givenManagerStatusMalformed_whenQueued_reverts() public {
        vm.mockCall(address(depositManager), abi.encodeCall(IEnabler.isEnabled, ()), hex"01");
        _assertQueueRejected(
            DEPOSIT_MANAGER_ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, 100e18)),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-L01.
    function test_givenTimelockIsDisabled_queueReverts() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    // Scenarios: DMCT-QUEUE-CAP-L02.
    function test_givenDepositManagerIsDisabled_queueReverts() public {
        vm.prank(EMERGENCY);
        depositManager.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    // Scenarios: DMCT-QUEUE-CAP-L03.
    function test_givenTimelockPolicyIsInactive_queueReverts() public {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    // Scenarios: DMCT-QUEUE-CAP-L04.
    function test_givenDepositManagerPolicyIsInactive_queueReverts() public {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    // Scenarios: DMCT-QUEUE-CAP-D01.
    function test_givenConfigOperatorChanged_queueReverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    // Scenarios: DMCT-QUEUE-CAP-A01.
    function test_givenAdminOnly_whenCapQueued(address caller_, uint256 cap_) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _capQueueSucceeds(caller_, cap_);
    }

    // Scenarios: DMCT-QUEUE-CAP-A01.
    function test_givenManagerOnly_whenCapQueued(address caller_, uint256 cap_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _capQueueSucceeds(caller_, cap_);
    }

    // Scenarios: DMCT-QUEUE-CAP-A01.
    function test_givenBothRoles_whenCapQueued(address caller_, uint256 cap_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _capQueueSucceeds(caller_, cap_);
    }

    // Scenarios: DMCT-QUEUE-CAP-I01.
    function test_whenCapAssetZero_reverts() public {
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (IERC20(address(0)), 1)),
            abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-N01.
    function test_whenCapEqualsCurrentMinimum(uint256 minimum_) public {
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, minimum_);
        uint64 id = _queueDepositCap(iAsset, minimum_);
        assertEq(_configTimelock.getQueuedActionLength(id), 1, "inclusive cap boundary queues");
    }

    // Scenarios: DMCT-QUEUE-CAP-N02.
    function test_whenCapBelowCurrentMinimum_reverts(uint256 minimum_, uint256 cap_) public {
        uint256 minimum = bound(minimum_, 1, type(uint256).max);
        uint256 cap = bound(cap_, 0, minimum - 1);
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, minimum);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, cap)),
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                minimum,
                cap
            )
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-N03.
    function test_whenCapZero() public {
        _capQueueSucceeds(ADMIN, 0);
    }

    // Scenarios: DMCT-QUEUE-CAP-N03.
    function test_whenCapOne() public {
        _capQueueSucceeds(ADMIN, 1);
    }

    // Scenarios: DMCT-QUEUE-CAP-N03, DMCT-QUEUE-CAP-P03.
    function test_whenCapUnchanged() public {
        _capQueueSucceeds(ADMIN, type(uint256).max);
    }

    // Scenarios: DMCT-QUEUE-CAP-P02.
    function test_givenPendingCap_whenCapQueuedAgain_reverts() public {
        uint64 owner = _queueDepositCap(iAsset, 1);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, 2)),
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _limitsKey(iAsset),
                owner
            )
        );
        _assertPending(owner);
    }

    // Scenarios: DMCT-QUEUE-CAP-L05.
    function test_givenPausedThenReEnabled_whenCapQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _capQueueSucceeds(ADMIN, 1);
    }

    // Scenarios: DMCT-QUEUE-CAP-L05.
    function test_givenPoliciesReactivated_whenCapQueued() public {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _capQueueSucceeds(ADMIN, 1);
    }

    // Scenarios: DMCT-QUEUE-CAP-I03.
    function test_givenPaused_whenUnauthorisedAndAssetZero_reverts(address caller_) public {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (IERC20(address(0)), 0)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-N04.
    function test_whenQueueExpiryIsMaximum() public {
        vm.warp(
            uint256(type(uint48).max) -
                _configTimelock.timelockDelay() -
                _configTimelock.EXECUTION_WINDOW()
        );
        uint64 id = _queueDepositCap(iAsset, 1);
        assertEq(
            _configTimelock.getQueuedAction(id).expiresAt,
            type(uint48).max,
            "maximum expiry accepted"
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-N05.
    function test_whenQueueExpiryOverflows_reverts() public {
        vm.warp(
            uint256(type(uint48).max) -
                _configTimelock.timelockDelay() -
                _configTimelock.EXECUTION_WINDOW() +
                1
        );
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, 1)),
            stdError.arithmeticError
        );
    }

    // Scenarios: DMCT-QUEUE-CAP-P01.
    function test_whenCapQueued_emitsExactEvents() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(1))
        );
        uint64 id = _configTimelock.nextActionId();
        uint48 ready = SafeCast.toUint48(vm.getBlockTimestamp()) + _configTimelock.timelockDelay();
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            id,
            0,
            _limitsKey(iAsset),
            0,
            address(depositManager),
            keccak256(abi.encode(true, type(uint256).max, uint256(0), address(_configTimelock)))
        );
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            id,
            address(depositManager),
            IDepositManager.setAssetDepositCap.selector,
            0,
            keccak256(actions[0].payload)
        );
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            id,
            ADMIN,
            keccak256(abi.encode(actions)),
            ready,
            ready + _configTimelock.EXECUTION_WINDOW()
        );
        _capQueueSucceeds(ADMIN, 1);
    }

    function _capQueueSucceeds(address caller_, uint256 cap_) private {
        uint64 id = _configTimelock.nextActionId();
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetDepositCap, (iAsset, cap_)),
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, cap_)
        );
        (bytes32 key, bytes32 stateHash) = _configTimelock.getQueuedConfigState(id, 0, 0);
        assertEq(key, _limitsKey(iAsset), "destination-scoped asset limits key");
        IDepositManager.AssetConfiguration memory config = depositManager.getAssetConfiguration(
            iAsset
        );
        assertEq(
            stateHash,
            keccak256(
                abi.encode(true, config.depositCap, config.minimumDeposit, address(_configTimelock))
            ),
            "exact limits prestate"
        );
        assertEq(_configTimelock.getQueuedConfigStateCount(id, 0), 1, "one guard");
    }
}
