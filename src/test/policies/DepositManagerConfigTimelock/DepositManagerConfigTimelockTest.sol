// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

// Test setup deliberately ignores return values that are not part of the configured state.
// forge-lint: disable-start(unused-return)

abstract contract DepositManagerConfigTimelockTest is DepositManagerTest {
    uint8 internal constant SECOND_PERIOD = 2;
    DepositManagerConfigTimelock internal _configTimelock;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        _configTimelock = new DepositManagerConfigTimelock(kernel, IDepositManager(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(_configTimelock));
        depositManager.setConfigOperator(address(_configTimelock));
        _configTimelock.enable("");
        vm.stopPrank();
    }

    function _singleAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(depositManager),
            selector: selector_,
            payload: payload_
        });
    }

    function _queueDepositCap(IERC20 asset_, uint256 cap_) internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueSetAssetDepositCap(asset_, cap_);
    }

    function _queueMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueSetAssetMinimumDeposit(asset_, minimumDeposit_);
    }

    function _queueEnablePeriod() internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueEnableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function _queueDisablePeriod() internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function _queueAddRoute() internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
    }

    function _warpReady() internal {
        vm.warp(vm.getBlockTimestamp() + _configTimelock.timelockDelay());
    }

    function _pausePolicy(address policy_) internal {
        vm.prank(EMERGENCY);
        IEnabler(policy_).disable("");
    }

    function _setPolicyActive(address policy_, bool active_) internal {
        vm.prank(ADMIN);
        kernel.executeAction(active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy, policy_);
    }

    function _grantRole(bytes32 role_, address caller_) internal {
        if (roles.hasRole(caller_, role_)) return;
        vm.prank(ADMIN);
        rolesAdmin.grantRole(role_, caller_);
    }

    function _limitsKey(IERC20 asset_) internal view returns (bytes32) {
        return _scopedKey(keccak256(abi.encode(keccak256("DEPOSIT_MANAGER_ASSET_LIMITS"), asset_)));
    }

    function _periodKey(uint8 period_, address operator_) internal view returns (bytes32) {
        return
            _scopedKey(
                keccak256(
                    abi.encode(
                        keccak256("DEPOSIT_MANAGER_ASSET_PERIOD"),
                        iAsset,
                        period_,
                        operator_
                    )
                )
            );
    }

    function _scopedKey(bytes32 localKey_) internal view returns (bytes32) {
        return keccak256(abi.encode(address(depositManager), localKey_));
    }

    function _targetState() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    depositManager.getAssetConfiguration(iAsset),
                    depositManager.getReceiptTokenIds(),
                    depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
                    asset.balanceOf(address(depositManager)),
                    asset.balanceOf(address(vault)),
                    asset.balanceOf(DEPOSITOR),
                    vault.balanceOf(address(depositManager)),
                    vault.totalSupply()
                )
            );
    }

    function _assertQueueRejected(
        address caller_,
        bytes memory call_,
        bytes memory error_
    ) internal {
        uint64 next = _configTimelock.nextActionId();
        bytes32 targetBefore = _targetState();
        uint64 ownerBefore = _configTimelock.pendingActionId(_limitsKey(iAsset));
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_configTimelock).call(call_);
        assertFalse(success, "queue rejects");
        assertEq(result, error_, "exact queue error and arguments");
        assertEq(_configTimelock.nextActionId(), next, "rejected queue consumes no ID");
        assertEq(
            _configTimelock.getQueuedConfigStateCount(next, 0),
            0,
            "no partial configuration guard"
        );
        assertEq(
            _configTimelock.getQueuedConfigDestination(next, 0),
            address(0),
            "no partial destination"
        );
        assertEq(
            _configTimelock.pendingActionId(_limitsKey(iAsset)),
            ownerBefore,
            "existing limits owner preserved"
        );
        assertEq(_targetState(), targetBefore, "target configuration and custody unchanged");
    }

    function _assertPending(uint64 actionId_) internal view {
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId_);
        assertFalse(action.executed, "rejection preserves pending execution flag");
        assertFalse(action.cancelled, "rejection preserves pending cancellation flag");
        assertGt(action.actions.length, 0, "rejection preserves payloads");
        (bytes32 key, ) = _configTimelock.getQueuedConfigState(actionId_, 0, 0);
        assertEq(
            _configTimelock.pendingActionId(key),
            actionId_,
            "rejection preserves key ownership"
        );
        assertEq(
            _configTimelock.getQueuedConfigDestination(actionId_, 0),
            address(depositManager),
            "rejection preserves destination"
        );
    }

    function _assertReleased(uint64 actionId_, uint256 index_, bytes32 key_) internal view {
        assertEq(
            _configTimelock.pendingActionId(key_),
            0,
            "terminal action releases key ownership"
        );
        assertEq(
            _configTimelock.getQueuedConfigStateCount(actionId_, index_),
            0,
            "terminal action removes guards"
        );
        assertEq(
            _configTimelock.getQueuedConfigDestination(actionId_, index_),
            address(0),
            "terminal action removes destination"
        );
        assertEq(
            _configTimelock.getQueuedAction(actionId_).actions.length,
            0,
            "terminal action deletes payloads"
        );
    }

    function _expectPendingKey(bytes32 key_, uint64 owner_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key_,
                owner_
            )
        );
    }

    function _expectStale(uint64 actionId_, uint256 index_, bytes32 currentHash_) internal {
        (bytes32 key, bytes32 expectedHash) = _configTimelock.getQueuedConfigState(
            actionId_,
            index_,
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId_,
                index_,
                key,
                expectedHash,
                currentHash_
            )
        );
    }

    function _assertTypedQueue(
        address caller_,
        bytes memory call_,
        bytes4 selector_,
        bytes memory payload_
    ) internal {
        bytes32 targetBefore = _targetState();
        uint64 next = _configTimelock.nextActionId();
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_configTimelock).call(call_);
        assertTrue(success, "authorized typed queue succeeds");
        assertEq(abi.decode(result, (uint64)), next, "exact queued action ID");
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(next);
        assertEq(action.proposer, caller_, "typed queue proposer");
        assertEq(action.actions.length, 1, "typed queue has one subaction");
        assertEq(action.actions[0].target, address(depositManager), "typed queue destination");
        assertEq(action.actions[0].selector, selector_, "typed queue target selector");
        assertEq(action.actions[0].payload, payload_, "typed queue exact payload");
        assertEq(action.queuedAt, vm.getBlockTimestamp(), "typed queue timestamp");
        assertEq(action.executableAt, vm.getBlockTimestamp() + 1 days, "typed queue delay");
        assertEq(action.expiresAt, vm.getBlockTimestamp() + 4 days, "typed queue expiry");
        assertEq(_configTimelock.nextActionId(), next + 1, "typed queue consumes exactly one ID");
        _assertPending(next);
        assertEq(_targetState(), targetBefore, "typed queue preserves target and custody");
    }
}

// forge-lint: disable-end(unused-return)
