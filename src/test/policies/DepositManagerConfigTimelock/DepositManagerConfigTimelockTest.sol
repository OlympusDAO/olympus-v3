// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test setup deliberately ignores return values that are not part of the configured state.
// forge-lint: disable-start(unused-return)

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

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

    function _queuePeriod(bool enable_) internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        if (enable_) {
            return _configTimelock.queueEnableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        }
        return _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function _queueAddRoute() internal returns (uint64 actionId) {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        return _configTimelock.queueAddAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
    }

    function _warpReady() internal {
        vm.warp(block.timestamp + _configTimelock.timelockDelay());
    }
}

// forge-lint: disable-end(unused-return)
