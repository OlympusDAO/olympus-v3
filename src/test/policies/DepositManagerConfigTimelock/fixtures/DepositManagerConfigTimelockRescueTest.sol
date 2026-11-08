// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "../DepositManagerConfigTimelockTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

// Test setup deliberately ignores action return values outside the assertion being tested.
// forge-lint: disable-start(unused-return)

abstract contract DepositManagerConfigTimelockRescueTest is DepositManagerConfigTimelockTest {
    error RescueBalanceReadFailed();
    error RescueTransferFailed();

    MockERC20 internal _rescueToken;
    MockERC20 internal _otherToken;
    IDepositManagerConfigTimelock internal _rescueQueue;
    IDepositManagerV1_1 internal _rescueManager;

    function setUp() public virtual override {
        super.setUp();
        _rescueToken = new MockERC20("Unmanaged rescue token", "RESCUE", 18);
        _otherToken = new MockERC20("Other unmanaged token", "OTHER", 6);
        _rescueQueue = IDepositManagerConfigTimelock(address(_configTimelock));
        _rescueManager = IDepositManagerV1_1(address(depositManager));

        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), MINT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    function _queueRescue(address caller_, address token_) internal returns (uint64 id) {
        vm.expectCall(
            address(depositManager),
            abi.encodeCall(_rescueManager.previewRescue, (token_))
        );
        vm.prank(caller_);
        return _rescueQueue.queueRescue(token_);
    }

    function _rescueKey(address token_) internal view returns (bytes32) {
        return _scopedKey(keccak256(abi.encode(keccak256("DEPOSIT_MANAGER_RESCUE"), token_)));
    }

    function _assertRescueQueueRejected(
        address caller_,
        bytes memory call_,
        address token_,
        bytes memory expectedError_
    ) internal {
        bytes32 custodyBefore = _targetState();
        uint64 nextBefore = _configTimelock.nextActionId();
        uint64 ownerBefore = _configTimelock.pendingActionId(_rescueKey(token_));
        uint256 balanceBefore = _rescueToken.balanceOf(address(depositManager));
        uint256 treasuryBefore = _rescueToken.balanceOf(address(trsry));
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_configTimelock).call(call_);
        assertFalse(success, "rescue queue should reject");
        assertEq(result, expectedError_, "rescue queue exact error and arguments");
        assertEq(_configTimelock.nextActionId(), nextBefore, "rejected rescue consumes no ID");
        assertEq(
            _configTimelock.pendingActionId(_rescueKey(token_)),
            ownerBefore,
            "rescue key owner unchanged"
        );
        assertEq(
            _configTimelock.getQueuedConfigStateCount(nextBefore, 0),
            0,
            "no partial rescue guard"
        );
        assertEq(
            _configTimelock.getQueuedConfigDestination(nextBefore, 0),
            address(0),
            "no partial rescue destination"
        );
        assertEq(_targetState(), custodyBefore, "managed custody and accounting unchanged");
        assertEq(
            _rescueToken.balanceOf(address(depositManager)),
            balanceBefore,
            "stray custody unchanged"
        );
        assertEq(
            _rescueToken.balanceOf(address(trsry)),
            treasuryBefore,
            "Treasury balance unchanged"
        );
    }

    function _assertRescueQueued(
        uint64 id_,
        address caller_,
        address token_,
        uint256 beforeBalance_
    ) internal view {
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id_);
        assertEq(action.proposer, caller_, "rescue proposer");
        assertEq(action.queuedAt, vm.getBlockTimestamp(), "rescue queued timestamp");
        assertEq(
            action.executableAt,
            vm.getBlockTimestamp() + _configTimelock.timelockDelay(),
            "rescue maturity"
        );
        assertEq(action.expiresAt, action.executableAt + 3 days, "rescue expiry");
        assertFalse(action.executed, "new rescue is unexecuted");
        assertFalse(action.cancelled, "new rescue is uncancelled");
        assertEq(action.actions.length, 1, "one rescue sub-action");
        assertEq(action.actions[0].target, address(depositManager), "rescue target");
        assertEq(
            action.actions[0].selector,
            IDepositManagerV1_1.rescue.selector,
            "rescue selector"
        );
        assertEq(action.actions[0].payload, abi.encode(token_), "rescue exact 32-byte payload");
        (address target, bytes4 selector, bytes memory payload) = _configTimelock
            .getQueuedSubAction(id_, 0);
        assertEq(target, action.actions[0].target, "sub-action target getter agrees");
        assertEq(selector, action.actions[0].selector, "sub-action selector getter agrees");
        assertEq(payload, action.actions[0].payload, "sub-action payload getter agrees");
        assertEq(_configTimelock.getQueuedActionLength(id_), 1, "rescue length getter");
        assertEq(
            _configTimelock.getQueuedConfigStateCount(id_, 0),
            1,
            "one rescue configuration guard"
        );
        (bytes32 key, bytes32 expectedHash) = _configTimelock.getQueuedConfigState(id_, 0, 0);
        assertEq(key, _rescueKey(token_), "rescue destination-scoped token key");
        assertEq(
            expectedHash,
            keccak256(abi.encode(true, address(_configTimelock))),
            "rescue commits eligibility and operator, not balance"
        );
        assertEq(
            _configTimelock.getQueuedConfigDestination(id_, 0),
            address(depositManager),
            "rescue configuration destination"
        );
        assertEq(_configTimelock.pendingActionId(key), id_, "rescue key owns action");
        assertEq(_configTimelock.nextActionId(), id_ + 1, "rescue consumes exactly one ID");
        assertEq(
            IERC20(token_).balanceOf(address(depositManager)),
            beforeBalance_,
            "queue does not move custody"
        );
        assertEq(
            _rescueManager.previewRescue(token_),
            beforeBalance_,
            "canonical quote equals queued live balance"
        );
        assertEq(
            IERC20(token_).allowance(address(depositManager), address(_configTimelock)),
            0,
            "queue creates no allowance"
        );
    }

    function _assertRescueExecuted(
        uint64 id_,
        address token_,
        uint256 amount_,
        address executor_
    ) internal {
        bytes32 custodyBefore = _targetState();
        uint256 treasuryBefore = IERC20(token_).balanceOf(address(trsry));
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(id_);
        assertEq(
            IERC20(token_).balanceOf(address(depositManager)),
            0,
            "execution sweeps full stray balance"
        );
        assertEq(
            IERC20(token_).balanceOf(address(trsry)),
            treasuryBefore + amount_,
            "Treasury receives exact live amount"
        );
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id_);
        assertTrue(action.executed, "rescue action executed");
        assertFalse(action.cancelled, "execution does not cancel");
        _assertReleased(id_, 0, _rescueKey(token_));
        assertEq(_targetState(), custodyBefore, "rescue preserves managed custody and accounting");
    }
}

// forge-lint: disable-end(unused-return)
