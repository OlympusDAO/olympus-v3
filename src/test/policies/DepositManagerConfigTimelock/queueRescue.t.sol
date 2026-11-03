// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {stdStorage, StdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockRescueTest} from "./fixtures/DepositManagerConfigTimelockRescueTest.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Actions, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7575Vault} from "src/test/mocks/MockERC7575Vault.sol";

contract DepositManagerConfigTimelockQueueRescueTest is DepositManagerConfigTimelockRescueTest {
    using stdStorage for StdStorage;

    // Scenarios: DMCT-RESCUE-A01, DMCT-RESCUE-P01, DMCT-RESCUE-P02.
    function test_givenAdminOnly_whenRescueQueued(
        address caller_,
        uint256 balance_,
        bool paused_
    ) public {
        vm.assume(caller_ != DEPOSIT_MANAGER_ADMIN && caller_ != address(_configTimelock));
        _grantRole(ADMIN_ROLE, caller_);
        if (paused_) _pausePolicy(address(depositManager));
        _rescueToken.mint(address(depositManager), balance_);
        bytes32 beforeState = _targetState();
        uint64 id = _queueRescue(caller_, address(_rescueToken));
        _assertRescueQueued(id, caller_, address(_rescueToken), balance_);
        assertEq(_targetState(), beforeState, "queue preserves all managed accounting");
        assertFalse(
            roles.hasRole(address(_configTimelock), ADMIN_ROLE),
            "timelock has no ADMIN grant"
        );
        assertFalse(
            roles.hasRole(address(_configTimelock), DEPOSIT_MANAGER_ADMIN_ROLE),
            "timelock has no manager grant"
        );
    }

    // Scenarios: DMCT-RESCUE-A01, DMCT-RESCUE-P02.
    function test_givenManagerOnly_whenRescueQueued(
        address caller_,
        uint256 balance_,
        bool paused_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE) && caller_ != address(_configTimelock));
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        if (paused_) _pausePolicy(address(depositManager));
        _rescueToken.mint(address(depositManager), balance_);
        _assertRescueQueued(
            _queueRescue(caller_, address(_rescueToken)),
            caller_,
            address(_rescueToken),
            balance_
        );
    }

    // Scenarios: DMCT-RESCUE-A01, DMCT-RESCUE-P02.
    function test_givenBothProposerRoles_whenRescueQueued(
        address caller_,
        uint256 balance_,
        bool paused_
    ) public {
        vm.assume(caller_ != address(_configTimelock));
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        if (paused_) _pausePolicy(address(depositManager));
        _rescueToken.mint(address(depositManager), balance_);
        _assertRescueQueued(
            _queueRescue(caller_, address(_rescueToken)),
            caller_,
            address(_rescueToken),
            balance_
        );
    }

    // Scenarios: DMCT-RESCUE-P01.
    function test_whenRescueTokenBalanceIsZero() public {
        _assertRescueQueued(
            _queueRescue(ADMIN, address(_rescueToken)),
            ADMIN,
            address(_rescueToken),
            0
        );
    }

    // Scenarios: DMCT-RESCUE-P01.
    function test_whenRescueTokenBalanceIsOne() public {
        _rescueToken.mint(address(depositManager), 1);
        _assertRescueQueued(
            _queueRescue(ADMIN, address(_rescueToken)),
            ADMIN,
            address(_rescueToken),
            1
        );
    }

    // Scenarios: DMCT-RESCUE-P01.
    function test_whenRescueTokenBalanceIsMaximum() public {
        _rescueToken.mint(address(depositManager), type(uint256).max);
        _assertRescueQueued(
            _queueRescue(ADMIN, address(_rescueToken)),
            ADMIN,
            address(_rescueToken),
            type(uint256).max
        );
    }

    // Scenarios: DMCT-RESCUE-A02.
    function test_whenRescueProposerUnauthorized_reverts(address caller_, bool paused_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE));
        if (paused_) _pausePolicy(address(depositManager));
        _assertRescueQueueRejected(
            caller_,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-A05, DMCT-RESCUE-L05, DMCT-RESCUE-L10.
    function test_givenManagerOnly_givenDepositManagerDisabled_whenRescueQueuedAndExecuted(
        address executor_
    ) public {
        _pausePolicy(address(depositManager));
        _rescueToken.mint(address(depositManager), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                DEPOSIT_MANAGER_ADMIN
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _rescueManager.rescue(address(_rescueToken));
        uint64 id = _queueRescue(DEPOSIT_MANAGER_ADMIN, address(_rescueToken));
        _assertRescueQueued(id, DEPOSIT_MANAGER_ADMIN, address(_rescueToken), 1);
        _warpReady();
        _assertRescueExecuted(id, address(_rescueToken), 1, executor_);
        assertFalse(depositManager.isEnabled(), "rescue preserves disabled manager state");
    }

    // Scenarios: DMCT-RESCUE-I03.
    function test_givenConfiguredUnderlying_whenRescueQueued_reverts() public {
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(asset))),
            address(asset),
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(asset)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-A03.
    function test_givenAnotherConfigOperator_whenRescueQueued_reverts(bool paused_) public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        if (paused_) _pausePolicy(address(depositManager));
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-A04.
    function test_givenNoConfigOperator_whenRescueQueued_reverts(bool paused_) public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(0));
        if (paused_) _pausePolicy(address(depositManager));
        _assertRescueQueueRejected(
            DEPOSIT_MANAGER_ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-L01.
    function test_givenTimelockInactiveAndDisabled_whenRescueQueued_revertsActivityFirst(
        address caller_
    ) public {
        vm.assume(
            !roles.hasRole(caller_, ADMIN_ROLE) &&
                !roles.hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        _assertRescueQueueRejected(
            caller_,
            abi.encodeCall(_rescueQueue.queueRescue, (address(0))),
            address(0),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-L02.
    function test_givenTimelockInactiveAndEnabled_whenRescueQueued_reverts() public {
        _setPolicyActive(address(_configTimelock), false);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-L03.
    function test_givenTimelockDisabled_whenUnauthorizedCallerQueuesZeroToken_revertsPauseFirst(
        address caller_
    ) public {
        vm.assume(
            !roles.hasRole(caller_, ADMIN_ROLE) &&
                !roles.hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        _pausePolicy(address(_configTimelock));
        _assertRescueQueueRejected(
            caller_,
            abi.encodeCall(_rescueQueue.queueRescue, (address(0))),
            address(0),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-L04.
    function test_givenDepositManagerInactive_whenRescueQueued_reverts(bool paused_) public {
        if (paused_) _pausePolicy(address(depositManager));
        _setPolicyActive(address(depositManager), false);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-L06.
    function test_givenTimelockReEnabled_whenRescueQueued() public {
        _pausePolicy(address(_configTimelock));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertRescueQueued(
            _queueRescue(ADMIN, address(_rescueToken)),
            ADMIN,
            address(_rescueToken),
            0
        );
    }

    // Scenarios: DMCT-RESCUE-L07.
    function test_givenDepositManagerInactive_whenUnauthorizedCallerQueuesZeroToken_revertsAuthorityFirst(
        address caller_
    ) public {
        vm.assume(
            !roles.hasRole(caller_, ADMIN_ROLE) &&
                !roles.hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        _setPolicyActive(address(depositManager), false);
        _assertRescueQueueRejected(
            caller_,
            abi.encodeCall(_rescueQueue.queueRescue, (address(0))),
            address(0),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-D01.
    function test_givenPausedManagerWithForeignKernel_whenRescueQueued_revertsMismatch() public {
        _pausePolicy(address(depositManager));
        address foreignKernel = address(new Kernel());
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(foreignKernel)
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(depositManager),
                address(kernel),
                foreignKernel
            )
        );
    }

    // Scenarios: DMCT-RESCUE-D02.
    function test_givenManagerKernelGetterReverts_whenRescueQueued_reverts() public {
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            hex"deadbeef"
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-D02.
    function test_givenManagerKernelGetterMalformed_whenRescueQueued_reverts() public {
        vm.mockCall(address(depositManager), abi.encodeWithSignature("kernel()"), hex"01");
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-I01.
    function test_givenVaultCustody_whenZeroTokenQueued_reverts() public {
        _assertIneligibleToken(address(0));
    }

    // Scenarios: DMCT-RESCUE-I01.
    function test_givenIdleCustody_whenZeroTokenQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_otherToken)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        _assertIneligibleToken(address(0));
    }

    // Scenarios: DMCT-RESCUE-I01.
    function test_givenNoConfiguredAssets_whenZeroTokenQueued_reverts() public {
        DepositManager emptyManager = new DepositManager(
            address(kernel),
            address(new ReceiptTokenManager())
        );
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(emptyManager));
        emptyManager.enable("");
        DepositManagerConfigTimelock emptyQueue = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(emptyManager))
        );
        kernel.executeAction(Actions.ActivatePolicy, address(emptyQueue));
        emptyManager.setConfigOperator(address(emptyQueue));
        emptyQueue.enable("");
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(0)
            )
        );
        vm.prank(ADMIN);
        IDepositManagerConfigTimelock(address(emptyQueue)).queueRescue(address(0));
        assertEq(
            emptyQueue.nextActionId(),
            1,
            "zero-token rejection consumes no ID on empty manager"
        );
    }

    // Scenarios: DMCT-RESCUE-I02.
    function test_whenNoCodeTokenQueued_reverts(address token_) public {
        vm.assume(token_ != address(0) && token_.code.length == 0);
        _assertIneligibleToken(token_);
    }

    // Scenarios: DMCT-RESCUE-I03.
    function test_givenIdleUnderlying_whenRescueQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_otherToken)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        _assertIneligibleToken(address(_otherToken));
    }

    // Scenarios: DMCT-RESCUE-I04.
    function test_givenConfiguredVault_whenRescueQueued_reverts() public {
        _assertIneligibleToken(address(vault));
    }

    // Scenarios: DMCT-RESCUE-I05.
    function test_givenStoredExternalShare_whenRescueQueued_reverts() public {
        MockERC7575Vault externalVault = _addExternalShareVault();
        _assertIneligibleToken(externalVault.share());
    }

    // Scenarios: DMCT-RESCUE-I05.
    function test_givenVaultReportedShareChanges_whenStoredShareQueued_reverts() public {
        MockERC7575Vault externalVault = _addExternalShareVault();
        address storedShare = externalVault.share();
        externalVault.setReportedShare(address(_rescueToken));
        _assertIneligibleToken(storedShare);
    }

    // Scenarios: DMCT-RESCUE-I05.
    function test_givenVaultShareGetterReverts_whenStoredShareQueued_reverts() public {
        MockERC7575Vault externalVault = _addExternalShareVault();
        address storedShare = externalVault.share();
        externalVault.setShareQueryReverts(true);
        _assertIneligibleToken(storedShare);
    }

    // Scenarios: DMCT-RESCUE-I06.
    function test_givenDisabledEmptyRoute_whenUnderlyingQueued_reverts() public {
        _addDisabledExternalShareRoute();
        _assertIneligibleToken(address(_otherToken));
    }

    // Scenarios: DMCT-RESCUE-I06.
    function test_givenDisabledEmptyRoute_whenVaultQueued_reverts() public {
        MockERC7575Vault externalVault = _addDisabledExternalShareRoute();
        _assertIneligibleToken(address(externalVault));
    }

    // Scenarios: DMCT-RESCUE-I06.
    function test_givenDisabledEmptyRoute_whenShareQueued_reverts() public {
        MockERC7575Vault externalVault = _addDisabledExternalShareRoute();
        _assertIneligibleToken(externalVault.share());
    }

    // Scenarios: DMCT-RESCUE-T03.
    function test_givenPreviewBalanceReadFails_whenQueued_revertsExactTokenError() public {
        MockERC20 brokenToken = new MockERC20("Broken read", "BROKEN", 18);
        vm.mockCallRevert(
            address(brokenToken),
            abi.encodeCall(brokenToken.balanceOf, (address(depositManager))),
            abi.encodeWithSelector(RescueBalanceReadFailed.selector)
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(brokenToken))),
            address(brokenToken),
            abi.encodeWithSelector(RescueBalanceReadFailed.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-D06.
    function test_givenTreasuryMissing_whenQueued_revertsMatchingPreview(uint256 amount_) public {
        _rescueToken.mint(address(depositManager), amount_);
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("TRSRY")),
            abi.encode(address(0))
        );
        bytes memory error_ = abi.encodeWithSelector(
            Policy.Policy_ModuleDoesNotExist.selector,
            toKeycode("TRSRY")
        );
        vm.expectRevert(error_);
        _rescueManager.previewRescue(address(_rescueToken));
        vm.expectRevert(error_);
        vm.prank(ADMIN);
        _rescueManager.rescue(address(_rescueToken));
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            error_
        );
    }

    // Scenarios: DMCT-RESCUE-N06.
    function test_givenPendingRescue_whenExecutingBeforeMaturity_reverts(
        address executor_,
        uint48 elapsed_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id);
        vm.warp(uint256(action.queuedAt) + bound(elapsed_, 0, _configTimelock.timelockDelay() - 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                id,
                action.executableAt
            )
        );
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id);
        _assertPending(id);
    }

    function _assertIneligibleToken(address token_) private {
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (token_)),
            token_,
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                token_
            )
        );
    }

    // Scenarios: DMCT-RESCUE-A02.
    function test_whenZeroProposerQueuesRescue_reverts() public {
        _assertRescueQueueRejected(
            address(0),
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-A02.
    function test_givenEmergencyOnly_whenRescueQueued_reverts() public {
        _assertRescueQueueRejected(
            EMERGENCY,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-A02.
    function test_givenDepositOperatorOnly_whenRescueQueued_reverts() public {
        _assertRescueQueueRejected(
            DEPOSIT_OPERATOR,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-D06.
    function test_givenTreasuryMissing_whenZeroBalanceQueued_reverts() public {
        test_givenTreasuryMissing_whenQueued_revertsMatchingPreview(0);
    }

    // Scenarios: DMCT-RESCUE-D06.
    function test_givenTreasuryMissing_whenPositiveBalanceQueued_reverts() public {
        test_givenTreasuryMissing_whenQueued_revertsMatchingPreview(1);
    }

    // Scenarios: DMCT-RESCUE-P02.
    function test_whenRescueQueued_emitsExactCommitmentAndQueueEvents() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _rescueBatch(address(_rescueToken));
        uint64 id = _configTimelock.nextActionId();
        uint48 ready = uint48(vm.getBlockTimestamp()) + _configTimelock.timelockDelay();
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            id,
            0,
            _rescueKey(address(_rescueToken)),
            0,
            address(depositManager),
            keccak256(abi.encode(true))
        );
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            id,
            address(depositManager),
            IDepositManagerV1_1.rescue.selector,
            0,
            keccak256(abi.encode(address(_rescueToken)))
        );
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            id,
            ADMIN,
            keccak256(abi.encode(actions)),
            ready,
            ready + 3 days
        );
        _assertRescueQueued(
            _queueRescue(ADMIN, address(_rescueToken)),
            ADMIN,
            address(_rescueToken),
            0
        );
    }

    // Scenarios: DMCT-RESCUE-P03.
    function test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees(
        address caller_,
        bool admin_,
        bool paused_
    ) public {
        vm.assume(caller_ != address(_configTimelock));
        _grantRole(admin_ ? ADMIN_ROLE : DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        if (paused_) _pausePolicy(address(depositManager));
        uint256 snapshot = vm.snapshotState();
        uint64 typedId = _queueRescue(caller_, address(_rescueToken));
        ITimelockBatchQueue.QueuedAction memory typedAction = _configTimelock.getQueuedAction(
            typedId
        );
        assertTrue(vm.revertToState(snapshot), "restore identical pre-queue state");
        vm.prank(caller_);
        uint64 batchId = _configTimelock.queueBatch(_rescueBatch(address(_rescueToken)));
        _assertRescueQueued(batchId, caller_, address(_rescueToken), 0);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(batchId))),
            keccak256(abi.encode(typedAction)),
            "typed and singleton batch have identical metadata under equal state"
        );
    }

    // Scenarios: DMCT-RESCUE-P04.
    function test_givenPendingRescue_whenTypedOrBatchDuplicateQueued_reverts() public {
        uint64 owner = _queueRescue(ADMIN, address(_rescueToken));
        bytes memory error_ = abi.encodeWithSelector(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
            _rescueKey(address(_rescueToken)),
            owner
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            error_
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (_rescueBatch(address(_rescueToken)))),
            address(_rescueToken),
            error_
        );
        _assertPending(owner);
    }

    // Scenarios: DMCT-RESCUE-P05.
    function test_givenPendingRescue_whenAnotherTokenQueued_thenKeysAreIndependent() public {
        uint64 first = _queueRescue(ADMIN, address(_rescueToken));
        uint64 second = _queueRescue(DEPOSIT_MANAGER_ADMIN, address(_otherToken));
        _assertRescueQueued(second, DEPOSIT_MANAGER_ADMIN, address(_otherToken), 0);
        _assertPending(first);
        assertEq(
            _configTimelock.pendingActionId(_rescueKey(address(_rescueToken))),
            first,
            "first token keeps its key"
        );
    }

    // Scenarios: DMCT-RESCUE-P06.
    function test_givenRescuePending_whenDepositCapQueued_thenDomainsAreIndependent() public {
        uint64 rescueId = _queueRescue(ADMIN, address(_rescueToken));
        uint64 configId = _queueDepositCap(iAsset, 1);
        _assertPending(rescueId);
        _assertPending(configId);
    }

    // Scenarios: DMCT-RESCUE-P06.
    function test_givenRescuePending_whenMinimumDepositQueued_thenDomainsAreIndependent() public {
        uint64 rescueId = _queueRescue(ADMIN, address(_rescueToken));
        uint64 configId = _queueMinimumDeposit(iAsset, 1);
        _assertPending(rescueId);
        _assertPending(configId);
    }

    // Scenarios: DMCT-RESCUE-P06.
    function test_givenRescuePending_whenWithdrawalModeQueued_thenDomainsAreIndependent() public {
        uint64 rescueId = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 configId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
        _assertPending(rescueId);
        _assertPending(configId);
    }

    // Scenarios: DMCT-RESCUE-P06.
    function test_givenRescuePending_whenPeriodDisableQueued_thenDomainsAreIndependent() public {
        uint64 rescueId = _queueRescue(ADMIN, address(_rescueToken));
        uint64 configId = _queueDisablePeriod();
        _assertPending(rescueId);
        _assertPending(configId);
    }

    // Scenarios: DMCT-RESCUE-I07.
    function test_whenRescueBatchTargetWrong_reverts(address target_) public {
        vm.assume(target_ != address(depositManager));
        ITimelockBatchQueue.BatchAction[] memory actions = _rescueBatch(address(_rescueToken));
        actions[0].target = target_;
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (actions)),
            address(_rescueToken),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                target_,
                IDepositManagerV1_1.rescue.selector
            )
        );
    }

    // Scenarios: DMCT-RESCUE-I08.
    function test_whenRescuePayloadTooShort_reverts(uint8 length_) public {
        _assertInvalidRescuePayload(new bytes(bound(length_, 0, 31)));
    }

    // Scenarios: DMCT-RESCUE-I08.
    function test_whenRescuePayloadTooLong_reverts(uint16 length_) public {
        _assertInvalidRescuePayload(new bytes(bound(length_, 33, 512)));
    }

    // Scenarios: DMCT-RESCUE-I08.
    function test_whenRescuePayloadLengthBoundaries_revert() public {
        _assertInvalidRescuePayload(new bytes(0));
        _assertInvalidRescuePayload(new bytes(1));
        _assertInvalidRescuePayload(new bytes(31));
        _assertInvalidRescuePayload(new bytes(33));
        _assertInvalidRescuePayload(new bytes(512));
    }

    // Scenarios: DMCT-RESCUE-I09.
    function test_whenRescuePayloadAddressIsNoncanonical_reverts(uint256 addressWord_) public {
        _assertInvalidRescuePayload(
            abi.encode(bound(addressWord_, uint256(type(uint160).max) + 1, type(uint256).max))
        );
    }

    // Scenarios: DMCT-RESCUE-I09.
    function test_whenRescuePayloadAddressAtInvalidBounds_reverts() public {
        _assertInvalidRescuePayload(abi.encode(uint256(type(uint160).max) + 1));
        _assertInvalidRescuePayload(abi.encode(type(uint256).max));
    }

    // Scenarios: DMCT-RESCUE-I10.
    function test_whenBatchSelectorUnsupported_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _rescueBatch(address(_rescueToken));
        actions[0].selector = bytes4(type(uint32).max);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (actions)),
            address(_rescueToken),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(depositManager),
                bytes4(type(uint32).max)
            )
        );
    }

    // Scenarios: DMCT-RESCUE-L08.
    function test_givenManagerPaused_whenRescueOnlyBatchQueued(uint8 length_) public {
        _assertPausedRescueBatch(bound(length_, 1, 15));
    }

    // Scenarios: DMCT-RESCUE-L08.
    function test_givenManagerPaused_whenRescueBatchSizeBoundariesQueued() public {
        _assertPausedRescueBatch(1);
        _assertPausedRescueBatch(15);
    }

    // Scenarios: DMCT-RESCUE-L09.
    function test_givenManagerPaused_whenMixedBatchQueued_revertsAtomically(
        bool rescueFirst_
    ) public {
        _pausePolicy(address(depositManager));
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch(rescueFirst_);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (actions)),
            address(_rescueToken),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-L09.
    function test_givenManagerPaused_whenBothMixedBatchOrdersQueued_revert() public {
        _pausePolicy(address(depositManager));
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (_mixedBatch(true))),
            address(_rescueToken),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (_mixedBatch(false))),
            address(_rescueToken),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: DMCT-RESCUE-P07.
    function test_givenManagerEnabled_whenMixedBatchQueued(bool rescueFirst_) public {
        bytes32 beforeState = _targetState();
        uint64 next = _configTimelock.nextActionId();
        vm.prank(ADMIN);
        uint64 id = _configTimelock.queueBatch(_mixedBatch(rescueFirst_));
        assertEq(id, next, "mixed batch returns next ID");
        assertEq(
            _configTimelock.getQueuedActionLength(id),
            2,
            "mixed batch retains both sub-actions"
        );
        assertEq(
            _configTimelock.pendingActionId(_rescueKey(address(_rescueToken))),
            id,
            "mixed batch owns rescue key"
        );
        assertEq(
            _configTimelock.pendingActionId(_limitsKey(iAsset)),
            id,
            "mixed batch owns independent limits key"
        );
        assertEq(
            _targetState(),
            beforeState,
            "mixed queue does not apply configuration or custody effects"
        );
    }

    // Scenarios: DMCT-RESCUE-N01.
    function test_givenLastAvailableActionId_whenRescueQueued() public {
        _setNextId(type(uint64).max - 1);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        assertEq(id, type(uint64).max - 1, "last representable rescue ID");
        _assertRescueQueued(id, ADMIN, address(_rescueToken), 0);
    }

    // Scenarios: DMCT-RESCUE-N02.
    function test_givenExhaustedActionCounter_whenRescueQueued_revertsWithoutPartialState() public {
        _setNextId(type(uint64).max);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            stdError.arithmeticError
        );
    }

    // Scenarios: DMCT-RESCUE-N03.
    function test_givenMaximumExpiry_whenRescueQueued(uint48 delay_) public {
        _assertMaximumExpiry(bound(delay_, 1 days, 30 days));
    }

    // Scenarios: DMCT-RESCUE-N03.
    function test_givenMinimumAndMaximumDelay_whenMaximumExpiryQueued() public {
        _assertMaximumExpiry(1 days);
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(1);
        _assertMaximumExpiry(30 days);
    }

    // Scenarios: DMCT-RESCUE-N04.
    function test_whenRescueExpiryAdditionOverflows_reverts(uint48 delay_) public {
        uint256 delay = bound(delay_, 1 days, 30 days);
        _setDelay(delay);
        vm.warp(uint256(type(uint48).max) - delay - 3 days + 1);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            stdError.arithmeticError
        );
    }

    // Scenarios: DMCT-RESCUE-N05.
    function test_whenRescueMaturityAdditionOverflows_reverts(uint48 delay_) public {
        uint256 delay = bound(delay_, 1 days, 30 days);
        _setDelay(delay);
        vm.warp(uint256(type(uint48).max) - delay + 1);
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_rescueQueue.queueRescue, (address(_rescueToken))),
            address(_rescueToken),
            stdError.arithmeticError
        );
    }

    // Scenarios: DMCT-RESCUE-N06.
    function test_whenRescueExecutedAtQueueTime_reverts() public {
        test_givenPendingRescue_whenExecutingBeforeMaturity_reverts(address(0), 0);
    }

    // Scenarios: DMCT-RESCUE-N06.
    function test_whenRescueExecutedOneSecondBeforeMaturity_reverts() public {
        test_givenPendingRescue_whenExecutingBeforeMaturity_reverts(
            address(0),
            uint48(_configTimelock.timelockDelay() - 1)
        );
    }

    // Scenarios: DMCT-RESCUE-N07.
    function test_givenMatureRescue_whenExecutedWithinWindow(
        address executor_,
        uint48 elapsed_
    ) public {
        _assertExecutionAtWindowOffset(executor_, bound(elapsed_, 0, 3 days));
    }

    // Scenarios: DMCT-RESCUE-N07.
    function test_whenRescueExecutedAtExactWindowBoundaries() public {
        _assertExecutionAtWindowOffset(address(0), 0);
        _assertExecutionAtWindowOffset(ADMIN, 1);
        _assertExecutionAtWindowOffset(DEPOSIT_MANAGER_ADMIN, 3 days - 1);
        _assertExecutionAtWindowOffset(EMERGENCY, 3 days);
    }

    // Scenarios: DMCT-RESCUE-N08.
    function test_givenExpiredRescue_whenExecuted_reverts(address executor_, uint48 now_) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        uint48 expiry = _configTimelock.getQueuedAction(id).expiresAt;
        vm.warp(bound(now_, uint256(expiry) + 1, type(uint48).max));
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                expiry
            )
        );
    }

    // Scenarios: DMCT-RESCUE-N08.
    function test_whenRescueExecutedOneSecondAfterExpiry_reverts() public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        uint48 expiry = _configTimelock.getQueuedAction(id).expiresAt;
        vm.warp(uint256(expiry) + 1);
        _assertExecutionRejected(
            id,
            address(0),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                expiry
            )
        );
    }

    // Scenarios: DMCT-RESCUE-N08.
    function test_whenRescueExecutedAtMaximumTimestamp_reverts() public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        uint48 expiry = _configTimelock.getQueuedAction(id).expiresAt;
        vm.warp(type(uint48).max);
        _assertExecutionRejected(
            id,
            address(0),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                expiry
            )
        );
    }

    // Scenarios: DMCT-RESCUE-P08.
    function test_givenAdditionalReceipts_whenRescueExecuted_matchesFreshPreviewAndEvents(
        address executor_
    ) public {
        _rescueToken.mint(address(depositManager), 1);
        assertEq(_rescueManager.previewRescue(address(_rescueToken)), 1, "queue-time quote");
        uint64 id = _queueRescue(DEPOSIT_MANAGER_ADMIN, address(_rescueToken));
        _rescueToken.mint(address(depositManager), 2);
        assertEq(
            _rescueManager.previewRescue(address(_rescueToken)),
            3,
            "fresh quote includes new receipts"
        );
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        vm.expectEmit(true, false, false, true, address(depositManager));
        emit IDepositManager.TokenRescued(address(_rescueToken), 3);
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            id,
            address(depositManager),
            IDepositManagerV1_1.rescue.selector,
            0
        );
        vm.expectEmit(true, true, false, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(id, executor_);
        _assertRescueExecuted(id, address(_rescueToken), 3, executor_);
    }

    // Scenarios: DMCT-RESCUE-P09.
    function test_givenZeroBalanceQueued_whenReceiptArrives_thenFullLiveBalanceRescued(
        address executor_,
        uint256 amount_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        uint256 amount = bound(amount_, 1, type(uint256).max);
        _rescueToken.mint(address(depositManager), amount);
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertRescueExecuted(id, address(_rescueToken), amount, executor_);
    }

    // Scenarios: DMCT-RESCUE-P10.
    function test_givenAdminRescuedFirst_whenQueuedRescueExecuted_thenZeroBalanceTerminates(
        address executor_
    ) public {
        _rescueToken.mint(address(depositManager), 1);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        _rescueManager.rescue(address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        vm.recordLogs();
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 subActionEvents;
        uint256 terminalEvents;
        for (uint256 i; i < logs.length; ++i) {
            assertFalse(
                logs[i].emitter == address(depositManager) &&
                    logs[i].topics[0] == keccak256("TokenRescued(address,uint256)"),
                "zero execution emits no rescue event"
            );
            assertFalse(
                logs[i].emitter == address(_rescueToken),
                "zero execution makes no token transfer"
            );
            if (
                logs[i].emitter == address(_configTimelock) &&
                logs[i].topics[0] ==
                keccak256("TimelockSubActionExecuted(uint64,address,bytes4,uint256)")
            ) ++subActionEvents;
            if (
                logs[i].emitter == address(_configTimelock) &&
                logs[i].topics[0] == keccak256("TimelockActionExecuted(uint64,address)")
            ) ++terminalEvents;
        }
        assertEq(subActionEvents, 1, "zero execution emits one sub-action terminal event");
        assertEq(terminalEvents, 1, "zero execution emits one batch terminal event");
        assertEq(
            _rescueToken.balanceOf(address(trsry)),
            1,
            "only prior admin rescue paid Treasury"
        );
    }

    // Scenarios: DMCT-RESCUE-P11.
    function test_givenTreasuryUpgraded_whenRescueExecuted_thenOnlyCurrentTreasuryPaid(
        address executor_
    ) public {
        _rescueToken.mint(address(depositManager), 3);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        OlympusTreasury replacement = new OlympusTreasury(kernel);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        bytes32 beforeState = _targetState();
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        assertEq(
            _rescueManager.previewRescue(address(_rescueToken)),
            3,
            "Treasury upgrade preserves quote"
        );
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id);
        assertEq(
            _rescueToken.balanceOf(address(replacement)),
            3,
            "new Treasury receives live payout"
        );
        assertEq(_rescueToken.balanceOf(address(trsry)), 0, "old Treasury receives nothing");
        assertEq(
            _rescueToken.balanceOf(address(depositManager)),
            0,
            "rescue empties stray token custody"
        );
        _assertReleased(id, 0, _rescueKey(address(_rescueToken)));
        assertTrue(
            _configTimelock.getQueuedAction(id).executed,
            "upgraded Treasury execution terminal flag"
        );
        assertEq(
            _targetState(),
            beforeState,
            "Treasury migration does not affect managed positions"
        );
    }

    // Scenarios: DMCT-RESCUE-L10.
    function test_givenDepositManagerPausedAfterQueue_whenRescueExecuted(address executor_) public {
        _rescueToken.mint(address(depositManager), 1);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        _pausePolicy(address(depositManager));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertRescueExecuted(id, address(_rescueToken), 1, executor_);
        assertFalse(depositManager.isEnabled(), "execution preserves manager pause");
    }

    // Scenarios: DMCT-RESCUE-L10, DMCT-RESCUE-P07.
    function test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens(
        address executor_,
        bool pausedAtQueue_
    ) public {
        if (pausedAtQueue_) _pausePolicy(address(depositManager));
        _rescueToken.mint(address(depositManager), 1);
        _otherToken.mint(address(depositManager), 2);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManagerV1_1.rescue.selector,
            abi.encode(address(_rescueToken))
        );
        actions[1] = _singleAction(
            IDepositManagerV1_1.rescue.selector,
            abi.encode(address(_otherToken))
        );
        vm.prank(ADMIN);
        uint64 id = _configTimelock.queueBatch(actions);
        if (!pausedAtQueue_) _pausePolicy(address(depositManager));
        bytes32 beforeState = _targetState();
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id);
        assertEq(_rescueToken.balanceOf(address(trsry)), 1, "first full balance reaches Treasury");
        assertEq(_otherToken.balanceOf(address(trsry)), 2, "second full balance reaches Treasury");
        assertEq(_rescueToken.balanceOf(address(depositManager)), 0, "first token swept once");
        assertEq(_otherToken.balanceOf(address(depositManager)), 0, "second token swept once");
        _assertReleased(id, 0, _rescueKey(address(_rescueToken)));
        _assertReleased(id, 1, _rescueKey(address(_otherToken)));
        assertTrue(_configTimelock.getQueuedAction(id).executed, "rescue-only batch is terminal");
        assertEq(_targetState(), beforeState, "rescue-only execution preserves managed positions");
        assertFalse(depositManager.isEnabled(), "rescue-only execution preserves manager pause");
    }

    // Scenarios: DMCT-RESCUE-P07.
    function test_givenMixedBatch_whenManagerPausedAtExecution_revertsAtomically(
        address executor_,
        bool rescueFirst_
    ) public {
        _rescueToken.mint(address(depositManager), 1);
        vm.prank(ADMIN);
        uint64 id = _configTimelock.queueBatch(_mixedBatch(rescueFirst_));
        _pausePolicy(address(depositManager));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
        assertEq(
            _configTimelock.pendingActionId(_rescueKey(address(_rescueToken))),
            id,
            "rescue key retained"
        );
        assertEq(
            _configTimelock.pendingActionId(_limitsKey(iAsset)),
            id,
            "configuration key retained"
        );
    }

    // Scenarios: DMCT-RESCUE-L10, DMCT-RESCUE-P07.
    function test_givenBatchPauseHistorySeeds_whenExecuting() public {
        uint256 snapshot = vm.snapshotState();
        test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens(address(0), false);
        assertTrue(vm.revertToState(snapshot), "restore rescue-only pre-queue pause seed");
        test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens(
            DEPOSIT_MANAGER_ADMIN,
            true
        );
        assertTrue(vm.revertToState(snapshot), "restore rescue-first mixed seed");
        test_givenMixedBatch_whenManagerPausedAtExecution_revertsAtomically(address(0), true);
        assertTrue(vm.revertToState(snapshot), "restore configuration-first mixed seed");
        test_givenMixedBatch_whenManagerPausedAtExecution_revertsAtomically(
            DEPOSIT_MANAGER_ADMIN,
            false
        );
    }

    // Scenarios: DMCT-RESCUE-L11.
    function test_givenTimelockPausedAfterQueue_whenExecutionRetriedAfterReEnable(
        address executor_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _pausePolicy(address(_configTimelock));
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
    }

    // Scenarios: DMCT-RESCUE-L12.
    function test_givenTimelockInactive_whenExecutionRetriedAfterActivation(
        address executor_,
        bool paused_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        if (paused_) _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        _setPolicyActive(address(_configTimelock), true);
        if (paused_) {
            vm.prank(DEPOSIT_MANAGER_ADMIN);
            _configTimelock.reEnable();
        }
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
    }

    // Scenarios: DMCT-RESCUE-L13.
    function test_givenDepositManagerInactive_whenExecutionRetriedAfterActivation(
        address executor_,
        bool paused_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        if (paused_) _pausePolicy(address(depositManager));
        _setPolicyActive(address(depositManager), false);
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
        _setPolicyActive(address(depositManager), true);
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
        assertEq(
            depositManager.isEnabled(),
            !paused_,
            "reactivation preserves manager local enablement"
        );
    }

    // Scenarios: DMCT-RESCUE-D03.
    function test_givenManagerKernelDrift_whenRescueExecuted_revertsAndRetainsPending(
        address executor_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        address foreignKernel = address(new Kernel());
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(foreignKernel)
        );
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(depositManager),
                address(kernel),
                foreignKernel
            )
        );
        vm.clearMockedCalls();
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
    }

    // Scenarios: DMCT-RESCUE-D04.
    function test_givenManagerControllerRotated_whenExecutionRetriedAfterRestoration(
        address executor_,
        bool cleared_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(cleared_ ? address(0) : CONFIG_OPERATOR);
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(_configTimelock));
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
    }

    // Scenarios: DMCT-RESCUE-A06.
    function test_givenProposerRoleRevoked_whenUnrelatedExecutorRescues() public {
        _rescueToken.mint(address(depositManager), 1);
        uint64 id = _queueRescue(DEPOSIT_MANAGER_ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        rolesAdmin.revokeRole(DEPOSIT_MANAGER_ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN);
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertRescueExecuted(id, address(_rescueToken), 1, address(0xBEEF));
    }

    // Scenarios: DMCT-RESCUE-D05.
    function test_givenQueuedTokenOnboardedAsUnderlying_whenRescueExecuted_reverts(
        address executor_
    ) public {
        _rescueToken.mint(address(depositManager), 3);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_rescueToken)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        _assertEligibilityDrift(id, address(_rescueToken), executor_);
    }

    // Scenarios: DMCT-RESCUE-D05.
    function test_givenQueuedTokenOnboardedAsVault_whenRescueExecuted_reverts(
        address executor_
    ) public {
        MockERC4626 newVault = new MockERC4626(_otherToken, "Rescue vault", "RV");
        _otherToken.mint(address(this), 3);
        _otherToken.approve(address(newVault), 3);
        newVault.deposit(3, address(depositManager));
        uint64 id = _queueRescue(ADMIN, address(newVault));
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_otherToken)),
            IERC4626(address(newVault)),
            type(uint256).max,
            0
        );
        _assertEligibilityDrift(id, address(newVault), executor_);
    }

    // Scenarios: DMCT-RESCUE-D05.
    function test_givenQueuedTokenOnboardedAsStoredShare_whenRescueExecuted_reverts(
        address executor_
    ) public {
        MockERC7575Vault newVault = new MockERC7575Vault(_otherToken, true);
        address share = newVault.share();
        _otherToken.mint(address(this), 3);
        _otherToken.approve(address(newVault), 3);
        newVault.deposit(3, address(depositManager));
        uint64 id = _queueRescue(ADMIN, share);
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_otherToken)),
            IERC4626(address(newVault)),
            type(uint256).max,
            0
        );
        _assertEligibilityDrift(id, share, executor_);
    }

    // Scenarios: DMCT-RESCUE-T01, DMCT-RESCUE-T02.
    function test_givenTransferFails_whenRestoredBeforeExpiry_thenRescueRetries(
        address executor_
    ) public {
        _rescueToken.mint(address(depositManager), 3);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        vm.mockCallRevert(
            address(_rescueToken),
            abi.encodeCall(_rescueToken.transfer, (address(trsry), 3)),
            abi.encodeWithSelector(RescueTransferFailed.selector)
        );
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(RescueTransferFailed.selector)
        );
        vm.clearMockedCalls();
        _assertRescueExecuted(id, address(_rescueToken), 3, executor_);
    }

    // Scenarios: DMCT-RESCUE-T01.
    function test_givenBalanceReadFailsAfterQueue_whenRescueExecuted_reverts(
        address executor_
    ) public {
        MockERC20 token = new MockERC20("Broken balance", "BROKEN", 18);
        token.mint(address(depositManager), 3);
        uint64 id = _queueRescue(ADMIN, address(token));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        vm.mockCallRevert(
            address(token),
            abi.encodeCall(token.balanceOf, (address(depositManager))),
            abi.encodeWithSelector(RescueBalanceReadFailed.selector)
        );
        _assertExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(RescueBalanceReadFailed.selector)
        );
        vm.clearMockedCalls();
        assertEq(
            token.balanceOf(address(depositManager)),
            3,
            "failed balance read preserves custody"
        );
        assertEq(
            token.balanceOf(address(trsry)),
            0,
            "failed balance read makes no Treasury payment"
        );
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_givenPendingRescue_whenEmergencyHolderCancels(
        address caller_,
        uint48 now_,
        bool paused_
    ) public {
        _grantRole(EMERGENCY_ROLE, caller_);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(bound(now_, vm.getBlockTimestamp(), type(uint48).max));
        if (paused_) _pausePolicy(address(_configTimelock));
        _assertCancellation(id, caller_);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledBeforeMaturity() public {
        _cancelAtOffset(0, false);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledDuringWindowWhilePaused() public {
        _cancelAtOffset(1 days, true);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledAfterExpiry() public {
        _cancelAtOffset(4 days + 1, false);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledBeforeMaturityWhilePaused() public {
        _cancelAtOffset(0, true);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledDuringWindowWhileEnabled() public {
        _cancelAtOffset(1 days, false);
    }

    // Scenarios: DMCT-RESCUE-P12.
    function test_whenRescueCancelledAfterExpiryWhilePaused() public {
        _cancelAtOffset(4 days + 1, true);
    }

    // Scenarios: DMCT-RESCUE-P13.
    function test_givenManagerReadinessChanged_whenRescueCancelled(
        bool inactive_,
        bool paused_,
        bool rotated_
    ) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        if (rotated_) {
            vm.prank(ADMIN);
            depositManager.setConfigOperator(CONFIG_OPERATOR);
        }
        if (paused_) _pausePolicy(address(depositManager));
        if (inactive_) _setPolicyActive(address(depositManager), false);
        _assertCancellation(id, EMERGENCY);
    }

    // Scenarios: DMCT-RESCUE-P13.
    function test_givenManagerInactivePausedAndControllerRotated_whenRescueCancelled() public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _pausePolicy(address(depositManager));
        _setPolicyActive(address(depositManager), false);
        _assertCancellation(id, EMERGENCY);
    }

    // Scenarios: DMCT-RESCUE-A07.
    function test_whenRescueCancelledByUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, EMERGENCY_ROLE));
        _assertCancellationUnauthorized(caller_);
    }

    // Scenarios: DMCT-RESCUE-A07.
    function test_whenRescueCancelledByAdminOnly_reverts() public {
        _assertCancellationUnauthorized(ADMIN);
    }

    // Scenarios: DMCT-RESCUE-A07.
    function test_whenRescueCancelledByManagerOnly_reverts() public {
        _assertCancellationUnauthorized(DEPOSIT_MANAGER_ADMIN);
    }

    // Scenarios: DMCT-RESCUE-P14.
    function test_givenRescueExecuted_whenSameTokenRequeued(address caller_) public {
        _grantRole(DEPOSIT_MANAGER_ADMIN_ROLE, caller_);
        uint64 oldId = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(oldId).executableAt);
        _assertRescueExecuted(oldId, address(_rescueToken), 0, address(0xBEEF));
        bytes32 oldMetadata = keccak256(abi.encode(_configTimelock.getQueuedAction(oldId)));
        uint64 newId = _queueRescue(caller_, address(_rescueToken));
        assertGt(newId, oldId, "requeue obtains a new ID");
        _assertRescueQueued(newId, caller_, address(_rescueToken), 0);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(oldId))),
            oldMetadata,
            "requeue preserves executed metadata"
        );
    }

    // Scenarios: DMCT-RESCUE-P14.
    function test_givenRescueCancelled_whenSameTokenRequeued(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        uint64 oldId = _queueRescue(ADMIN, address(_rescueToken));
        _assertCancellation(oldId, EMERGENCY);
        bytes32 oldMetadata = keccak256(abi.encode(_configTimelock.getQueuedAction(oldId)));
        uint64 newId = _queueRescue(caller_, address(_rescueToken));
        assertGt(newId, oldId, "cancelled token obtains a new ID");
        _assertRescueQueued(newId, caller_, address(_rescueToken), 0);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(oldId))),
            oldMetadata,
            "requeue preserves cancellation metadata"
        );
    }

    // Scenarios: DMCT-RESCUE-I11.
    function test_givenRescueExecuted_whenExecutedAgain_reverts(address executor_) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(_configTimelock.getQueuedAction(id).executableAt);
        _assertRescueExecuted(id, address(_rescueToken), 0, executor_);
        _assertTerminalExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
    }

    // Scenarios: DMCT-RESCUE-I11.
    function test_givenRescueCancelled_whenExecuted_reverts(address executor_) public {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        _assertCancellation(id, EMERGENCY);
        _assertTerminalExecutionRejected(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
    }

    // Scenarios: DMCT-RESCUE-P15.
    function test_givenOlderRescueExpired_whenUnrelatedRescueExecuted(address executor_) public {
        uint64 older = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(uint256(_configTimelock.getQueuedAction(older).expiresAt) + 1);
        _assertIndependentRescue(older, executor_);
    }

    // Scenarios: DMCT-RESCUE-P15.
    function test_givenOlderRescueStale_whenUnrelatedRescueExecuted(address executor_) public {
        uint64 older = _queueRescue(ADMIN, address(_rescueToken));
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_rescueToken)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        _assertIndependentRescue(older, executor_);
    }

    // Scenarios: DMCT-RESCUE-A01.
    function test_givenAdminOnly_whenBothManagerPauseStatesQueued() public {
        uint256 snapshot = vm.snapshotState();
        test_givenAdminOnly_whenRescueQueued(address(0xCA11), 1, false);
        assertTrue(vm.revertToState(snapshot), "restore unpaused manager for second ADMIN seed");
        test_givenAdminOnly_whenRescueQueued(address(0xCA11), 1, true);
    }

    // Scenarios: DMCT-RESCUE-A01.
    function test_givenManagerOnly_whenBothManagerPauseStatesQueued() public {
        uint256 snapshot = vm.snapshotState();
        test_givenManagerOnly_whenRescueQueued(address(0xCA12), 1, false);
        assertTrue(vm.revertToState(snapshot), "restore unpaused manager for second manager seed");
        test_givenManagerOnly_whenRescueQueued(address(0xCA12), 1, true);
    }

    // Scenarios: DMCT-RESCUE-A01.
    function test_givenOverlappingRoles_whenBothManagerPauseStatesQueued() public {
        uint256 snapshot = vm.snapshotState();
        test_givenBothProposerRoles_whenRescueQueued(address(0xCA13), 1, false);
        assertTrue(
            vm.revertToState(snapshot),
            "restore unpaused manager for second overlapping seed"
        );
        test_givenBothProposerRoles_whenRescueQueued(address(0xCA13), 1, true);
    }

    // Scenarios: DMCT-RESCUE-A02.
    function test_givenUnauthorizedCaller_whenBothManagerPauseStatesQueued_revert() public {
        test_whenRescueProposerUnauthorized_reverts(address(0), false);
        test_whenRescueProposerUnauthorized_reverts(address(0), true);
    }

    // Scenarios: DMCT-RESCUE-A03.
    function test_givenAnotherController_whenBothManagerPauseStatesQueued_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_givenAnotherConfigOperator_whenRescueQueued_reverts(false);
        assertTrue(
            vm.revertToState(snapshot),
            "restore original controller before paused rotated-controller seed"
        );
        test_givenAnotherConfigOperator_whenRescueQueued_reverts(true);
    }

    // Scenarios: DMCT-RESCUE-A04.
    function test_givenNoController_whenBothManagerPauseStatesQueued_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_givenNoConfigOperator_whenRescueQueued_reverts(false);
        assertTrue(
            vm.revertToState(snapshot),
            "restore selected controller before paused cleared-controller seed"
        );
        test_givenNoConfigOperator_whenRescueQueued_reverts(true);
    }

    // Scenarios: DMCT-RESCUE-L04.
    function test_givenInactiveManager_whenBothLocalPauseStatesQueued_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_givenDepositManagerInactive_whenRescueQueued_reverts(false);
        assertTrue(vm.revertToState(snapshot), "restore active manager before pausing second seed");
        test_givenDepositManagerInactive_whenRescueQueued_reverts(true);
    }

    // Scenarios: DMCT-RESCUE-P03.
    function test_givenAdminAndManager_whenTypedBatchEquivalenceInBothPauseStates() public {
        uint256 snapshot = vm.snapshotState();
        test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees(ADMIN, true, false);
        assertTrue(vm.revertToState(snapshot), "restore before paused ADMIN batch seed");
        test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees(ADMIN, true, true);
        assertTrue(vm.revertToState(snapshot), "restore before manager batch seed");
        test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees(
            DEPOSIT_MANAGER_ADMIN,
            false,
            false
        );
        assertTrue(vm.revertToState(snapshot), "restore before paused manager batch seed");
        test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees(
            DEPOSIT_MANAGER_ADMIN,
            false,
            true
        );
    }

    // Scenarios: DMCT-RESCUE-L12.
    function test_givenInactiveTimelock_whenBothPauseStatesRetried() public {
        uint256 snapshot = vm.snapshotState();
        test_givenTimelockInactive_whenExecutionRetriedAfterActivation(address(0), false);
        assertTrue(vm.revertToState(snapshot), "restore before paused inactive timelock seed");
        test_givenTimelockInactive_whenExecutionRetriedAfterActivation(address(0), true);
    }

    // Scenarios: DMCT-RESCUE-L13.
    function test_givenInactiveManager_whenBothPauseStatesRetried() public {
        uint256 snapshot = vm.snapshotState();
        test_givenDepositManagerInactive_whenExecutionRetriedAfterActivation(address(0), false);
        assertTrue(vm.revertToState(snapshot), "restore before paused inactive manager seed");
        test_givenDepositManagerInactive_whenExecutionRetriedAfterActivation(address(0), true);
    }

    // Scenarios: DMCT-RESCUE-D04.
    function test_givenControllerRotatedOrCleared_whenBothRestoredAndRetried() public {
        uint256 snapshot = vm.snapshotState();
        test_givenManagerControllerRotated_whenExecutionRetriedAfterRestoration(address(0), false);
        assertTrue(vm.revertToState(snapshot), "restore before cleared controller seed");
        test_givenManagerControllerRotated_whenExecutionRetriedAfterRestoration(address(0), true);
    }

    function _assertIndependentRescue(uint64 older_, address executor_) private {
        bytes32 original = keccak256(abi.encode(_configTimelock.getQueuedAction(older_)));
        _otherToken.mint(address(depositManager), 3);
        uint64 newer = _queueRescue(ADMIN, address(_otherToken));
        vm.warp(_configTimelock.getQueuedAction(newer).executableAt);
        _assertRescueExecuted(newer, address(_otherToken), 3, executor_);
        _assertPending(older_);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(older_))),
            original,
            "unrelated execution preserves older operation"
        );
    }

    function _assertEligibilityDrift(uint64 id_, address token_, address executor_) private {
        vm.warp(_configTimelock.getQueuedAction(id_).executableAt);
        uint256 custody = IERC20(token_).balanceOf(address(depositManager));
        uint256 treasury = IERC20(token_).balanceOf(address(trsry));
        _assertExecutionRejected(
            id_,
            executor_,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id_,
                uint256(0),
                _rescueKey(token_),
                keccak256(abi.encode(true)),
                keccak256(abi.encode(false))
            )
        );
        assertEq(
            IERC20(token_).balanceOf(address(depositManager)),
            custody,
            "eligibility drift preserves now-managed token"
        );
        assertEq(
            IERC20(token_).balanceOf(address(trsry)),
            treasury,
            "eligibility drift prevents Treasury payout"
        );
    }

    function _cancelAtOffset(uint256 elapsed_, bool paused_) private {
        _rescueToken.mint(address(depositManager), 1);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(vm.getBlockTimestamp() + elapsed_);
        if (paused_) _pausePolicy(address(_configTimelock));
        _assertCancellation(id, EMERGENCY);
    }

    function _assertCancellation(uint64 id_, address caller_) private {
        ITimelockBatchQueue.QueuedAction memory oldAction = _configTimelock.getQueuedAction(id_);
        bytes32 beforeState = _targetState();
        uint256 custody = _rescueToken.balanceOf(address(depositManager));
        uint256 treasury = _rescueToken.balanceOf(address(trsry));
        vm.expectEmit(true, true, false, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id_, caller_);
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(id_);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id_);
        assertTrue(action.cancelled, "cancellation terminal flag");
        assertFalse(action.executed, "cancellation does not execute");
        assertEq(action.proposer, oldAction.proposer, "cancel retains proposer");
        assertEq(action.queuedAt, oldAction.queuedAt, "cancel retains queue timestamp");
        assertEq(action.executableAt, oldAction.executableAt, "cancel retains maturity");
        assertEq(action.expiresAt, oldAction.expiresAt, "cancel retains expiry");
        _assertReleased(id_, 0, _rescueKey(address(_rescueToken)));
        assertEq(_targetState(), beforeState, "cancellation preserves managed accounting");
        assertEq(
            _rescueToken.balanceOf(address(depositManager)),
            custody,
            "cancel preserves stray custody"
        );
        assertEq(_rescueToken.balanceOf(address(trsry)), treasury, "cancel pays no Treasury funds");
    }

    function _assertCancellationUnauthorized(address caller_) private {
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        bytes32 beforeAction = keccak256(abi.encode(_configTimelock.getQueuedAction(id)));
        bytes32 beforeState = _targetState();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(id);
        _assertPending(id);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(id))),
            beforeAction,
            "unauthorized cancellation preserves metadata"
        );
        assertEq(_targetState(), beforeState, "unauthorized cancellation preserves custody");
    }

    function _assertTerminalExecutionRejected(
        uint64 id_,
        address executor_,
        bytes memory error_
    ) private {
        bytes32 beforeAction = keccak256(abi.encode(_configTimelock.getQueuedAction(id_)));
        uint256 treasury = _rescueToken.balanceOf(address(trsry));
        vm.expectRevert(error_);
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id_);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(id_))),
            beforeAction,
            "repeat execution preserves terminal metadata"
        );
        assertEq(
            _rescueToken.balanceOf(address(trsry)),
            treasury,
            "repeat execution pays no additional funds"
        );
        _assertReleased(id_, 0, _rescueKey(address(_rescueToken)));
    }

    function _rescueBatch(
        address token_
    ) private view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(IDepositManagerV1_1.rescue.selector, abi.encode(token_));
    }

    function _mixedBatch(
        bool rescueFirst_
    ) private view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[rescueFirst_ ? 0 : 1] = _singleAction(
            IDepositManagerV1_1.rescue.selector,
            abi.encode(address(_rescueToken))
        );
        actions[rescueFirst_ ? 1 : 0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(1))
        );
    }

    function _assertInvalidRescuePayload(bytes memory payload_) private {
        ITimelockBatchQueue.BatchAction[] memory actions = _rescueBatch(address(_rescueToken));
        actions[0].payload = payload_;
        _assertRescueQueueRejected(
            ADMIN,
            abi.encodeCall(_configTimelock.queueBatch, (actions)),
            address(_rescueToken),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(depositManager),
                IDepositManagerV1_1.rescue.selector
            )
        );
    }

    function _assertPausedRescueBatch(uint256 length_) private {
        if (depositManager.isEnabled()) _pausePolicy(address(depositManager));
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            length_
        );
        for (uint256 i; i < length_; ++i) {
            MockERC20 token = new MockERC20("Batch rescue", "BATCH", 18);
            actions[i] = _singleAction(
                IDepositManagerV1_1.rescue.selector,
                abi.encode(address(token))
            );
        }
        bytes32 beforeState = _targetState();
        vm.prank(ADMIN);
        uint64 id = _configTimelock.queueBatch(actions);
        assertEq(_configTimelock.getQueuedActionLength(id), length_, "rescue batch length");
        for (uint256 i; i < length_; ++i) {
            address token = abi.decode(actions[i].payload, (address));
            assertEq(
                _configTimelock.pendingActionId(_rescueKey(token)),
                id,
                "one pending key per batch token"
            );
            assertEq(
                _configTimelock.getQueuedConfigStateCount(id, i),
                1,
                "one configuration guard per rescue"
            );
            assertEq(IERC20(token).balanceOf(address(depositManager)), 0, "queue moves no token");
        }
        assertEq(_targetState(), beforeState, "batch preserves managed custody and positions");
        assertFalse(depositManager.isEnabled(), "rescue-only batch preserves pause");
    }

    function _setNextId(uint256 id_) private {
        stdstore
            .enable_packed_slots()
            .target(address(_configTimelock))
            .sig("nextActionId()")
            .checked_write(id_);
    }

    function _setDelay(uint256 delay_) private {
        stdstore
            .enable_packed_slots()
            .target(address(_configTimelock))
            .sig("timelockDelay()")
            .checked_write(delay_);
    }

    function _assertMaximumExpiry(uint256 delay_) private {
        _setDelay(delay_);
        vm.warp(uint256(type(uint48).max) - delay_ - 3 days);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        _assertRescueQueued(id, ADMIN, address(_rescueToken), 0);
        assertEq(
            _configTimelock.getQueuedAction(id).expiresAt,
            type(uint48).max,
            "maximum expiry retained without truncation"
        );
    }

    function _assertExecutionAtWindowOffset(address executor_, uint256 offset_) private {
        _rescueToken.mint(address(depositManager), 1);
        uint64 id = _queueRescue(ADMIN, address(_rescueToken));
        vm.warp(uint256(_configTimelock.getQueuedAction(id).executableAt) + offset_);
        _assertRescueExecuted(id, address(_rescueToken), 1, executor_);
    }

    function _assertExecutionRejected(uint64 id_, address executor_, bytes memory error_) private {
        bytes32 beforeState = _targetState();
        uint256 beforeCustody = _rescueToken.balanceOf(address(depositManager));
        uint256 beforeTreasury = _rescueToken.balanceOf(address(trsry));
        bytes32 actionBefore = keccak256(abi.encode(_configTimelock.getQueuedAction(id_)));
        vm.expectRevert(error_);
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id_);
        _assertPending(id_);
        assertEq(
            keccak256(abi.encode(_configTimelock.getQueuedAction(id_))),
            actionBefore,
            "failed execution preserves full action metadata and payload"
        );
        assertEq(
            _rescueToken.balanceOf(address(depositManager)),
            beforeCustody,
            "failed execution preserves stray custody"
        );
        assertEq(
            _rescueToken.balanceOf(address(trsry)),
            beforeTreasury,
            "failed execution preserves Treasury balance"
        );
        assertEq(
            _targetState(),
            beforeState,
            "failed execution preserves managed custody/accounting"
        );
    }

    function _addExternalShareVault() private returns (MockERC7575Vault externalVault) {
        externalVault = new MockERC7575Vault(_otherToken, true);
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(_otherToken)),
            IERC4626(address(externalVault)),
            type(uint256).max,
            0
        );
    }

    function _addDisabledExternalShareRoute() private returns (MockERC7575Vault externalVault) {
        externalVault = _addExternalShareVault();
        vm.startPrank(ADMIN);
        depositManager.addAssetPeriod(
            IERC20(address(_otherToken)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        depositManager.disableAssetPeriod(
            IERC20(address(_otherToken)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        vm.stopPrank();
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(_otherToken)), DEPOSIT_OPERATOR),
            0,
            "disabled route has no liabilities"
        );
    }
}
