// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueSetAssetMinimumDepositTest is
    DepositManagerConfigTimelockTest
{
    // Scenarios: DMCT-QUEUE-MINIMUM-A01.
    function test_givenAdminOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-A01.
    function test_givenManagerOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-A01.
    function test_givenBothRoles_whenTypedActionQueued(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-A02.
    function test_whenTypedActionCallerUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertQueueRejected(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L01.
    function test_givenTimelockPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L02.
    function test_givenManagerPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(depositManager));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L03.
    function test_givenTimelockInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(_configTimelock), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L04.
    function test_givenManagerInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(depositManager), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-D01.
    function test_givenOperatorRotated_whenTypedActionQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L05.
    function test_givenReEnabled_whenTypedActionQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-L05.
    function test_givenReactivated_whenTypedActionQueued() public {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, uint256(1))),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-N01.
    function test_whenMinimumEqualsCap(uint256 cap_) public {
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, cap_);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, cap_)),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, cap_)
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-N02.
    function test_whenMinimumAboveCap_reverts(uint256 cap_, uint256 minimum_) public {
        uint256 cap = bound(cap_, 0, type(uint256).max - 1);
        uint256 minimum = bound(minimum_, cap + 1, type(uint256).max);
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, cap);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, minimum)),
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                minimum,
                cap
            )
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-I01.
    function test_whenMinimumAssetUnconfigured_reverts(address asset_) public {
        vm.assume(asset_ != address(iAsset));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (IERC20(asset_), 1)),
            abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-N03, DMCT-QUEUE-MINIMUM-P02.
    function test_whenMinimumZeroUnchanged() public {
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, 0)),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(0))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-N03.
    function test_whenMinimumOne() public {
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetMinimumDeposit, (iAsset, 1)),
            IDepositManager.setAssetMinimumDeposit.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    // Scenarios: DMCT-QUEUE-MINIMUM-D02.
    function test_givenQueuedMinimum_whenCapChanges_reverts() public {
        uint64 id = _queueMinimumDeposit(iAsset, 1);
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 2);
        _warpReady();
        _expectStale(id, 0, keccak256(abi.encode(true, uint256(2), uint256(0))));
        _configTimelock.executeQueuedAction(id);
        _assertPending(id);
    }
}
