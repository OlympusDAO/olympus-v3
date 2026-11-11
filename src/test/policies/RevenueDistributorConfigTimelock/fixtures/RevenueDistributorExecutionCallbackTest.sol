// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {RevenueDistributorConfigTimelockTest} from "../RevenueDistributorConfigTimelockTest.sol";

abstract contract RevenueDistributorExecutionCallbackTest is RevenueDistributorConfigTimelockTest {
    ReentrantFeeToken internal _callbackAsset;
    MockERC20 internal _routeAsset;
    uint64 internal _outerId;
    bytes32 internal _outerKey;
    uint64 internal _nestedId;
    bytes32 internal _nestedKey;

    function setUp() public virtual override {
        super.setUp();
        _callbackAsset = new ReentrantFeeToken();
        _callbackAsset.mint(address(distributor), 10);
        vm.prank(admin);
        _outerId = configTimelock.queueRescue(address(_callbackAsset), bob);
        _outerKey = _queuedKey(_outerId, 0);
        _routeAsset = new MockERC20("Callback route", "CBR", 18);
    }

    function _sameActionCallback(bool bubble_) internal {
        _callbackAsset.setCallbackFrom(
            address(distributor),
            address(configTimelock),
            abi.encodeCall(configTimelock.executeQueuedAction, (_outerId))
        );
        _callbackAsset.setBubbleCallbackFailure(bubble_);
        vm.warp(configTimelock.getQueuedAction(_outerId).executableAt);
    }

    function _independentActionCallback(bool bubble_) internal {
        vm.prank(admin);
        _nestedId = configTimelock.queueSetAssetRoutes(address(_routeAsset), 0, _emptyRoutes());
        _nestedKey = _queuedKey(_nestedId, 0);
        _callbackAsset.setCallbackFrom(
            address(distributor),
            address(configTimelock),
            abi.encodeCall(configTimelock.executeQueuedAction, (_nestedId))
        );
        _callbackAsset.setBubbleCallbackFailure(bubble_);
        vm.warp(configTimelock.getQueuedAction(_outerId).executableAt);
    }

    function _assertOuterRetained() internal view {
        assertFalse(
            configTimelock.getQueuedAction(_outerId).executed,
            "Propagated callback retains outer action"
        );
        assertEq(
            configTimelock.pendingActionId(_outerKey),
            _outerId,
            "Propagated callback retains outer key"
        );
        assertEq(
            _callbackAsset.balanceOf(address(distributor)),
            10,
            "Propagated callback restores custody"
        );
        assertEq(_callbackAsset.balanceOf(bob), 0, "Propagated callback pays nothing");
        assertTrue(_callbackAsset.callbackEnabled(), "Propagated callback state rolls back");
    }

    function _assertOuterCompleted() internal view {
        assertFalse(_callbackAsset.callbackSucceeded(), "Nested execution is rejected");
        assertTrue(
            configTimelock.getQueuedAction(_outerId).executed,
            "Caught callback completes outer action"
        );
        assertEq(
            configTimelock.pendingActionId(_outerKey),
            0,
            "Caught callback releases outer key"
        );
        assertEq(
            _callbackAsset.balanceOf(address(distributor)),
            0,
            "Outer rescue spends custody once"
        );
        assertEq(_callbackAsset.balanceOf(bob), 10, "Outer rescue pays once");
    }

    function _assertNestedRetained() internal view {
        assertFalse(
            configTimelock.getQueuedAction(_nestedId).executed,
            "Nested configuration stays live"
        );
        assertEq(configTimelock.pendingActionId(_nestedKey), _nestedId, "Nested key remains owned");
        assertEq(
            uint8(distributor.assetState(address(_routeAsset))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "Nested route is not installed"
        );
    }
}
