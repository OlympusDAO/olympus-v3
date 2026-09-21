// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueAssetPeriodTest is DepositManagerConfigTimelockTest {
    function test_whenAssetIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(IERC20(address(0)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(
            IERC20(address(0)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
    }

    function test_whenDepositPeriodIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, 0, DEPOSIT_OPERATOR);
    }

    function test_whenOperatorIsZero_whenDisableIsQueued_reverts() public {
        _expectInvalidAssetPeriod(iAsset, DEPOSIT_PERIOD, address(0));

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, address(0));
    }

    function test_givenAssetPeriodIsEnabled_whenEnableIsQueued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodEnabled.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueEnableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function test_givenAssetPeriodIsDisabled_whenDisableIsQueued_reverts() public {
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodDisabled.selector,
                address(iAsset),
                DEPOSIT_PERIOD,
                DEPOSIT_OPERATOR
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function test_givenEnabledPeriod_queuesAndExecutesDisable(address executor_) public {
        uint64 actionId = _queuePeriod(false);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "timelock should disable period"
        );
    }

    function test_givenDisabledPeriod_queuesAndExecutesEnable(address executor_) public {
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        uint64 actionId = _queuePeriod(true);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "timelock should enable period"
        );
    }

    function test_givenPendingDisable_whenSamePeriodChangeIsQueued_reverts() public {
        _queuePeriod(false);

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueDisableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
    }

    function test_givenPendingDisable_whenDifferentPeriodIsQueued_succeeds() public {
        uint8 secondPeriod = DEPOSIT_PERIOD + 1;
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, secondPeriod, DEPOSIT_OPERATOR);
        uint64 firstActionId = _queuePeriod(false);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            secondPeriod,
            DEPOSIT_OPERATOR
        );

        assertEq(
            secondActionId,
            firstActionId + 1,
            "different asset periods should have independent keys"
        );
    }

    function test_givenPendingDisable_whenDifferentAssetIsQueued_executesBoth() public {
        MockERC20 secondAsset = new MockERC20("Second", "SECOND", 18);
        MockERC4626 secondVault = new MockERC4626(secondAsset, "Second Vault", "svSECOND");
        vm.startPrank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        vm.stopPrank();

        uint64 firstActionId = _queuePeriod(false);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            IERC20(address(secondAsset)),
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        _warpReady();

        _configTimelock.executeQueuedAction(firstActionId);
        _configTimelock.executeQueuedAction(secondActionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "first asset period should be disabled"
        );
        assertFalse(
            depositManager
                .isAssetPeriod(IERC20(address(secondAsset)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
                .isEnabled,
            "second asset period should be disabled"
        );
    }

    function test_givenPendingDisable_whenDifferentOperatorIsQueued_executesBoth() public {
        address secondOperator = makeAddr("secondOperator");
        vm.startPrank(ADMIN);
        depositManager.setOperatorName(secondOperator, "op2");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator);
        vm.stopPrank();

        uint64 firstActionId = _queuePeriod(false);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 secondActionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            secondOperator
        );
        _warpReady();

        _configTimelock.executeQueuedAction(firstActionId);
        _configTimelock.executeQueuedAction(secondActionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "first operator period should be disabled"
        );
        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator).isEnabled,
            "second operator period should be disabled"
        );
    }

    function test_whenDepositPeriodIsUint8Max_whenConfigured_executesDisable() public {
        uint8 maximumPeriod = type(uint8).max;
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, maximumPeriod, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueDisableAssetPeriod(
            iAsset,
            maximumPeriod,
            DEPOSIT_OPERATOR
        );
        _warpReady();
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, maximumPeriod, DEPOSIT_OPERATOR).isEnabled,
            "maximum deposit period should be disabled"
        );
    }

    function test_givenQueuedDisable_whenPeriodChanges_executionRevertsAsStale() public {
        uint64 actionId = _queuePeriod(false);
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        _warpReady();

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function _expectInvalidAssetPeriod(IERC20 asset_, uint8 period_, address operator_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                period_,
                operator_
            )
        );
    }
}

// forge-lint: disable-end(unused-return)
