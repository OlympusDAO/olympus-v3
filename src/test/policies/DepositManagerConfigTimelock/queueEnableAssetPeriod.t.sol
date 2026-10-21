// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Setup and revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueEnableAssetPeriodTest is
    DepositManagerConfigTimelockTest
{
    function test_givenAssetPeriodIsEnabled_reverts() public {
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

    function test_givenAssetPeriodIsDisabled_queuesAndExecutesEnable(address executor_) public {
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
}

// forge-lint: disable-end(unused-return)
