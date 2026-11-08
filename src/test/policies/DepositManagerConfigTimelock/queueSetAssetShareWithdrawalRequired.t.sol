// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

contract DepositManagerConfigTimelockQueueSetAssetShareWithdrawalRequiredTest is
    DepositManagerConfigTimelockTest
{
    uint8 internal constant _TOKEN_DECIMALS = 18;

    // Scenarios: DMCT-A03, DMCT-QUEUE-WITHDRAWAL-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        _assertQueueRejected(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    function test_givenAdmin_whenCallingDepositManagerDirectly() public {
        vm.prank(ADMIN);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "direct admin requirement mismatch"
        );
    }

    function test_givenAdmin_whenRequirementIsQueued_executesAfterDelay() public {
        vm.prank(ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "admin-queued requirement mismatch"
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-I01.
    function test_givenUnconfiguredAsset_reverts(address asset_, bool required_) public {
        vm.assume(asset_ != address(iAsset));

        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(asset_), required_);
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-I02.
    function test_givenIdleAsset_whenRequiredIsTrue_reverts() public {
        MockERC20 idleAsset = new MockERC20("Idle", "IDLE", _TOKEN_DECIMALS);
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(idleAsset)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(idleAsset)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(address(idleAsset)), true);
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-I03.
    function test_givenAsyncRedeemVault_whenRequiredIsFalse_reverts() public {
        MockERC20 asyncAsset = new MockERC20("Async", "ASYNC", _TOKEN_DECIMALS);
        MockERC7540ExternalShareVault asyncVault = new MockERC7540ExternalShareVault(
            asyncAsset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(asyncAsset)),
            IERC4626(address(asyncVault)),
            type(uint256).max,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(asyncAsset),
                address(asyncVault)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(address(asyncAsset)), false);
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-P01.
    function test_whenRequirementIsQueued_executesAfterDelay(
        bool required_,
        address executor_
    ) public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, required_);

        assertFalse(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "requirement changed before execution"
        );
        _warpReady();
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            required_,
            "executed requirement mismatch"
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-P02.
    function test_givenPendingRequirement_whenSameAssetIsQueuedAgain_reverts() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 owner = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);

        _expectPendingKey(
            _scopedKey(
                keccak256(abi.encode(keccak256("DEPOSIT_MANAGER_ASSET_SHARE_WITHDRAWAL"), iAsset))
            ),
            owner
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, false);

        assertEq(_configTimelock.nextActionId(), owner + 1, "failed queue consumed action ID");
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-D02.
    function test_givenQueuedRequirement_whenRequirementChanges_executionRevertsAsStale() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);

        vm.prank(address(_configTimelock));
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
        _warpReady();

        _expectStale(actionId, 0, keccak256(abi.encode(true, true, address(_configTimelock))));
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-P03.
    function test_givenPendingRequirement_whenAssetPeriodChangeIsQueued_succeeds() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 requirementActionId = _configTimelock.queueSetAssetShareWithdrawalRequired(
            iAsset,
            true
        );
        uint64 periodActionId = _queueDisablePeriod();

        assertEq(
            periodActionId,
            requirementActionId + 1,
            "independent setting should use a separate key"
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-P04.
    function test_givenSecondAsset_requirementKeysAreIndependent() public {
        MockERC20 secondAsset = new MockERC20("Second", "SECOND", _TOKEN_DECIMALS);
        MockERC4626 secondVault = new MockERC4626(secondAsset, "Second Vault", "svSECOND");
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 first = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 second = _configTimelock.queueSetAssetShareWithdrawalRequired(
            IERC20(address(secondAsset)),
            true
        );

        assertEq(second, first + 1, "different assets should have independent keys");
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-A01.
    function test_givenAdminOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN);
        _grantRole(ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, true)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-A01.
    function test_givenManagerOnly_whenTypedActionQueued(address caller_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, true)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-A01.
    function test_givenBothRoles_whenTypedActionQueued(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        _assertTypedQueue(
            caller_,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, true)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L01.
    function test_givenTimelockPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(_configTimelock));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L02.
    function test_givenManagerPaused_whenTypedActionQueued_reverts() public {
        _pausePolicy(address(depositManager));
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L03.
    function test_givenTimelockInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(_configTimelock), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L04.
    function test_givenManagerInactive_whenTypedActionQueued_reverts() public {
        _setPolicyActive(address(depositManager), false);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-D01.
    function test_givenOperatorRotated_whenTypedActionQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _assertQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L05.
    function test_givenReEnabled_whenTypedActionQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, true)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-L05.
    function test_givenReactivated_whenTypedActionQueued() public {
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        _setPolicyActive(address(depositManager), true);
        _setPolicyActive(address(_configTimelock), true);
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, true)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, true)
        );
    }

    // Scenarios: DMCT-QUEUE-WITHDRAWAL-P05.
    function test_whenRequirementFalseUnchangedQueued() public {
        _assertTypedQueue(
            ADMIN,
            abi.encodeCall(_configTimelock.queueSetAssetShareWithdrawalRequired, (iAsset, false)),
            IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
            abi.encode(iAsset, false)
        );
    }
}

// forge-lint: disable-end(unused-return)
