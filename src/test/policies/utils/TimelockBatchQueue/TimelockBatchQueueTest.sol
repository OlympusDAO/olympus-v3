// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";
import {ReentrantSubAction} from "src/test/policies/utils/TimelockBatchQueue/fixtures/ReentrantSubAction.sol";

abstract contract TimelockBatchQueueTest is Test {
    uint48 internal constant TIMELOCK_DELAY = 1 days;
    uint48 internal constant EXECUTION_WINDOW = 7 days;

    address internal proposer = address(0x1111);
    address internal executor = address(0x2222);
    address internal canceller = address(0x3333);
    address internal target1 = address(0x4441);
    address internal target2 = address(0x4442);
    address internal target3 = address(0x4443);
    bytes4 internal selector1 = bytes4(keccak256("setValue(uint256)"));
    bytes4 internal selector2 = bytes4(keccak256("setOther(uint256)"));
    bytes4 internal selector3 = bytes4(keccak256("setThird(uint256)"));

    MockTimelockBatchQueue internal queue;
    ReentrantSubAction internal reentrant;

    function setUp() public virtual {
        queue = new MockTimelockBatchQueue(TIMELOCK_DELAY);
        reentrant = new ReentrantSubAction(address(queue));
    }

    function _newSubAction(
        address target_,
        bytes4 selector_,
        uint256 value_
    ) internal pure returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction({
                target: target_,
                selector: selector_,
                payload: abi.encode(value_)
            });
    }

    function _buildBatchOfThree()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](3);
        actions[0] = _newSubAction(target1, selector1, 0);
        actions[1] = _newSubAction(target2, selector2, 1);
        actions[2] = _newSubAction(target3, selector3, 2);
    }

    function _buildBatchOfSize(
        uint256 size_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](size_);
        for (uint256 i; i < size_; ++i) {
            actions[i] = ITimelockBatchQueue.BatchAction({
                target: address(uint160(0x1000 + i)),
                selector: bytes4(uint32(0xa0000000 + i)),
                payload: abi.encode(i)
            });
        }
    }

    function _queueSingleAction() internal returns (uint64 actionId) {
        vm.prank(proposer);
        return queue.queueAction(target1, selector1, abi.encode(uint256(11)));
    }

    function _queueThreeBatch()
        internal
        returns (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = _buildBatchOfThree();
        vm.prank(proposer);
        actionId = queue.queueBatchAction(actions);
    }

    function _warpReady(uint64 actionId_) internal {
        vm.warp(queue.getQueuedAction(actionId_).executableAt);
    }
}
